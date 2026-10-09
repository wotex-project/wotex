#ifndef WOTEX_MATTER_BRIDGE_REPLIES_HPP
#define WOTEX_MATTER_BRIDGE_REPLIES_HPP

#include "wotex_matter/bridge_requests.hpp"

#include <array>

namespace wotex::matter {

// Internal scoped adapter for a command-specific native renderer. The live
// SDK handler is borrowed only during rendering on the SDK owner. The request
// principal/path and permitted response IDs are copied. They grant no policy
// authority. Construct only after a retained context has become Completed.
// Metadata never queries the asynchronous SDK handler or its exchange.
class SdkBridgeCommandReply final : public chip::app::CommandHandler {
 public:
  static constexpr std::size_t kMaximumResponseIds = 8;

  SdkBridgeCommandReply(chip::app::CommandHandler &handler, const BridgeRequestMetadata &request,
                        chip::Span<const chip::CommandId> responses);
  SdkBridgeCommandReply(const SdkBridgeCommandReply &) = delete;
  SdkBridgeCommandReply &operator=(const SdkBridgeCommandReply &) = delete;

  CHIP_ERROR configuration_status() const;
  // Requires one written reply. An encoding failure remains visible even if
  // the SDK-defined fallback Failure status was successfully written.
  CHIP_ERROR result() const;
  bool replied() const;

  CHIP_ERROR FallibleAddStatus(const chip::app::ConcreteCommandPath &path,
                               const chip::Protocols::InteractionModel::ClusterStatusCode &status,
                               const char *context = nullptr) override;
  void AddStatus(const chip::app::ConcreteCommandPath &path,
                 const chip::Protocols::InteractionModel::ClusterStatusCode &status,
                 const char *context = nullptr) override;
  CHIP_ERROR AddResponseData(const chip::app::ConcreteCommandPath &path, chip::CommandId response,
                             const chip::app::DataModel::EncodableToTLV &value) override;
  void AddResponse(const chip::app::ConcreteCommandPath &path, chip::CommandId response,
                   const chip::app::DataModel::EncodableToTLV &value) override;
  chip::FabricIndex GetAccessingFabricIndex() const override;
  chip::Access::SubjectDescriptor GetSubjectDescriptor() const override;
  bool IsTimedInvoke() const override;
  chip::Messaging::ExchangeContext *GetExchangeContext() const override;
  // Any explicit acknowledgement flush belongs to the original synchronous
  // admission callback. Delayed rendering cannot touch an exchange.
  void FlushAcksRightAwayOnSlowCommand() override;

 protected:
  // The adapter has only a renderer-call lifetime. Retaining a child handle
  // would leave a dangling SDK handler; terminate rather than permit it.
  void IncrementHoldOff(Handle *) override;
  void DecrementHoldOff(Handle *) override;

 private:
  CHIP_ERROR CheckPath(const chip::app::ConcreteCommandPath &path);
  CHIP_ERROR CheckResponse(const chip::app::ConcreteCommandPath &path, chip::CommandId response);
  CHIP_ERROR EncodeData(chip::CommandId response,
                        const chip::app::DataModel::EncodableToTLV &value);
  CHIP_ERROR Remember(CHIP_ERROR error);

  chip::app::CommandHandler &handler_;
  const BridgeRequestMetadata request_;
  const chip::app::ConcreteCommandPath path_;
  std::array<chip::CommandId, kMaximumResponseIds> responses_{};
  std::size_t count_{0};
  bool replied_{false};
  CHIP_ERROR error_{CHIP_NO_ERROR};
  CHIP_ERROR validation_error_{CHIP_NO_ERROR};
};

} // namespace wotex::matter

#endif
