#ifndef WOTEX_MATTER_BRIDGE_PROVIDER_HPP
#define WOTEX_MATTER_BRIDGE_PROVIDER_HPP

#include "wotex_matter/bridge_requests.hpp"
#include "wotex_matter/bridge_server.hpp"

#include <app/data-model-provider/Provider.h>
#include <cstdlib>

namespace wotex::matter {

// Explicit native receiver. Child operations have no delegate fallback; the
// receiver owns consumer admission and the operation-specific result path.
// Metadata arguments own their principal. Decoder/encoder/reader references
// remain callback-scoped, and invoke retention belongs to the context owner.
// Invoke returns nullopt after writing a reply or retaining the SDK handler;
// returning Success instructs the SDK to write an automatic Success status.
// Any retained arguments must be copied before this callback returns.
class BridgeReceiver {
 public:
  virtual ~BridgeReceiver() = default;
  virtual chip::app::DataModel::ActionReturnStatus Read(
      BridgeRequestMetadata request, chip::app::AttributeValueEncoder &encoder) = 0;
  virtual chip::app::DataModel::ActionReturnStatus Write(
      BridgeRequestMetadata request, chip::app::AttributeValueDecoder &decoder) = 0;
  virtual std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(
      BridgeRequestMetadata request, chip::TLV::TLVReader &arguments,
      chip::app::CommandHandler *handler) = 0;
  virtual void ListNotification(const chip::app::ConcreteAttributePath &path,
                                chip::app::DataModel::ListWriteOperation operation,
                                chip::FabricIndex fabric) = 0;
};

// Internal single-lifetime SDK provider. Calls and listener changes remain
// under the SDK stack lock. The borrowed provider and receiver outlive this
// owner. Root operations and metadata stay with the generated provider; live
// children require the explicit receiver, after the SDK's path/ACL checks.
// Startup/shutdown failure terminates because the SDK logs those errors and
// continues. Shutdown unregisters the borrowed listener before releasing its
// context. Closed owners cannot restart or admit operations.
class SdkBridgeProviderBinding final : public chip::app::DataModel::Provider,
                                       private chip::app::DataModel::AttributeChangeListener {
 public:
  SdkBridgeProviderBinding(chip::app::DataModel::Provider &delegate, BridgeReceiver &receiver)
      : delegate_(delegate), receiver_(receiver) {}
  SdkBridgeProviderBinding(const SdkBridgeProviderBinding &) = delete;
  SdkBridgeProviderBinding &operator=(const SdkBridgeProviderBinding &) = delete;
  ~SdkBridgeProviderBinding() override {
    if (state_ == State::Active) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  }

  CHIP_ERROR Startup(chip::app::DataModel::InteractionModelContext context) override {
    if (state_ != State::Fresh) return CHIP_ERROR_INCORRECT_STATE;
    const auto error = delegate_.Startup(context);
    if (error != CHIP_NO_ERROR) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    delegate_.RegisterAttributeChangeListener(*this);
    state_ = State::Active;
    return CHIP_NO_ERROR;
  }
  CHIP_ERROR Shutdown() override {
    if (state_ != State::Active) return CHIP_NO_ERROR;
    state_ = State::Closed;
    delegate_.UnregisterAttributeChangeListener(*this);
    const auto error = delegate_.Shutdown();
    if (error != CHIP_NO_ERROR) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    return CHIP_NO_ERROR;
  }

  CHIP_ERROR Endpoints(
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::EndpointEntry> &builder) override {
    return delegate_.Endpoints(builder);
  }
  CHIP_ERROR DeviceTypes(
      chip::EndpointId endpoint,
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::DeviceTypeEntry> &builder) override {
    return delegate_.DeviceTypes(endpoint, builder);
  }
  CHIP_ERROR ClientClusters(chip::EndpointId endpoint,
                            chip::ReadOnlyBufferBuilder<chip::ClusterId> &builder) override {
    return delegate_.ClientClusters(endpoint, builder);
  }
  CHIP_ERROR ServerClusters(
      chip::EndpointId endpoint,
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::ServerClusterEntry> &builder) override {
    return delegate_.ServerClusters(endpoint, builder);
  }
#if CHIP_CONFIG_USE_ENDPOINT_UNIQUE_ID
  CHIP_ERROR EndpointUniqueID(chip::EndpointId endpoint, chip::MutableCharSpan &id) override {
    return delegate_.EndpointUniqueID(endpoint, id);
  }
#endif
  CHIP_ERROR EventInfo(const chip::app::ConcreteEventPath &path,
                       chip::app::DataModel::EventEntry &info) override {
    return delegate_.EventInfo(path, info);
  }
  CHIP_ERROR Attributes(
      const chip::app::ConcreteClusterPath &path,
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::AttributeEntry> &builder) override {
    return delegate_.Attributes(path, builder);
  }
  CHIP_ERROR GeneratedCommands(const chip::app::ConcreteClusterPath &path,
                               chip::ReadOnlyBufferBuilder<chip::CommandId> &builder) override {
    return delegate_.GeneratedCommands(path, builder);
  }
  CHIP_ERROR AcceptedCommands(
      const chip::app::ConcreteClusterPath &path,
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::AcceptedCommandEntry> &builder) override {
    return delegate_.AcceptedCommands(path, builder);
  }

  chip::app::DataModel::ActionReturnStatus ReadAttribute(
      const chip::app::DataModel::ReadAttributeRequest &request,
      chip::app::AttributeValueEncoder &encoder) override {
    if (state_ != State::Active) return CHIP_ERROR_INCORRECT_STATE;
    if (request.path.mEndpointId < 2) return delegate_.ReadAttribute(request, encoder);
    const auto admission = ChildStatus(request.path.mEndpointId);
    if (!admission.IsSuccess()) return admission;
    return receiver_.Read(CaptureBridgeRequest(request), encoder);
  }
  chip::app::DataModel::ActionReturnStatus WriteAttribute(
      const chip::app::DataModel::WriteAttributeRequest &request,
      chip::app::AttributeValueDecoder &decoder) override {
    if (state_ != State::Active) return CHIP_ERROR_INCORRECT_STATE;
    if (request.path.mEndpointId < 2) return delegate_.WriteAttribute(request, decoder);
    const auto admission = ChildStatus(request.path.mEndpointId);
    if (!admission.IsSuccess()) return admission;
    return receiver_.Write(CaptureBridgeRequest(request), decoder);
  }
  std::optional<chip::app::DataModel::ActionReturnStatus> InvokeCommand(
      const chip::app::DataModel::InvokeRequest &request, chip::TLV::TLVReader &arguments,
      chip::app::CommandHandler *handler) override {
    if (state_ != State::Active)
      return chip::app::DataModel::ActionReturnStatus(CHIP_ERROR_INCORRECT_STATE);
    if (request.path.mEndpointId < 2) return delegate_.InvokeCommand(request, arguments, handler);
    const auto admission = ChildStatus(request.path.mEndpointId);
    if (!admission.IsSuccess()) return admission;
    return receiver_.Invoke(CaptureBridgeRequest(request), arguments, handler);
  }
  void ListAttributeWriteNotification(const chip::app::ConcreteAttributePath &path,
                                      chip::app::DataModel::ListWriteOperation operation,
                                      chip::FabricIndex fabric) override {
    if (state_ != State::Active) return;
    if (path.mEndpointId < 2) {
      delegate_.ListAttributeWriteNotification(path, operation, fabric);
    } else if (ChildStatus(path.mEndpointId).IsSuccess()) {
      receiver_.ListNotification(path, operation, fabric);
    }
  }

 private:
  chip::app::DataModel::ActionReturnStatus ChildStatus(chip::EndpointId endpoint) {
    if (endpoint < 3 || endpoint == chip::kInvalidEndpointId)
      return chip::Protocols::InteractionModel::Status::UnsupportedEndpoint;
    chip::ReadOnlyBufferBuilder<chip::app::DataModel::EndpointEntry> builder;
    const auto error = delegate_.Endpoints(builder);
    if (error != CHIP_NO_ERROR) return error;
    const auto endpoints = builder.TakeBuffer();
    for (const auto &entry : endpoints) {
      if (entry.id == endpoint) return CHIP_NO_ERROR;
    }
    return chip::Protocols::InteractionModel::Status::UnsupportedEndpoint;
  }
  void OnAttributeChanged(const chip::app::ConcreteAttributePath &path,
                          chip::app::DataModel::AttributeChangeType type) override {
    NotifyAttributeChanged(path, type);
  }
  void OnEndpointChanged(chip::EndpointId endpoint,
                         chip::app::DataModel::EndpointChangeType type) override {
    NotifyEndpointChanged(endpoint, type);
  }

  chip::app::DataModel::Provider &delegate_;
  BridgeReceiver &receiver_;
  enum class State { Fresh, Active, Closed };
  State state_{State::Fresh};
};

} // namespace wotex::matter

#endif
