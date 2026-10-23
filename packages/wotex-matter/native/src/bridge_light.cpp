#include "wotex_matter/bridge_light.hpp"
#include "wotex_matter/bridge_server.hpp"

#include <app/persistence/AttributePersistenceProvider.h>
#include <app/server-cluster/ServerClusterContext.h>
#include <cstdlib>

namespace wotex::matter {
namespace {
using Action = chip::app::DataModel::ActionReturnStatus;
using Status = chip::Protocols::InteractionModel::Status;
using Base = chip::app::Clusters::OnOffLightingCluster;
using StartupValue = chip::app::DataModel::Nullable<chip::app::Clusters::OnOff::StartUpOnOffEnum>;
StartupValue ConfiguredStartup(std::uint8_t value) {
  if (value == 0xFF) return StartupValue();
  return StartupValue(static_cast<chip::app::Clusters::OnOff::StartUpOnOffEnum>(value));
}
}
class SdkBridgeLightCluster::Impl final : public chip::app::AttributePersistenceProvider {
 public:
  Impl(chip::EndpointId path, chip::scenes::ScenesIntegrationDelegate &delegate,
       BridgeStorage &store, std::optional<bool> &observed, std::uint8_t &configured)
      : endpoint(path), scenes(delegate), storage(store), approved(observed), startup(configured) {}
  void Healthy() const {
    if (storage.poisoned()) std::_Exit(SdkBridgeServerBinding::kStoreFailureExit);
  }
  bool OnOff(const chip::app::ConcreteAttributePath &path) const {
    return path.mEndpointId == endpoint && path.mClusterId == 6 && path.mAttributeId == 0;
  }
  CHIP_ERROR ReadValue(const chip::app::ConcreteAttributePath &path,
                       chip::MutableByteSpan &value) override {
    Healthy();
    if (OnOff(path)) return CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND;
    const auto result = persistence->ReadValue(path, value);
    Healthy();
    return result;
  }
  CHIP_ERROR WriteValue(const chip::app::ConcreteAttributePath &path,
                        const chip::ByteSpan &value) override {
    Healthy();
    if (OnOff(path)) return CHIP_NO_ERROR; // Volatile command/timer bookkeeping only.
    const auto result = persistence->WriteValue(path, value);
    Healthy();
    return result;
  }
  chip::EndpointId endpoint;
  chip::scenes::ScenesIntegrationDelegate &scenes;
  BridgeStorage &storage;
  std::optional<bool> &approved;
  std::uint8_t &startup;
  chip::app::AttributePersistenceProvider *persistence{nullptr};
  std::optional<chip::app::ServerClusterContext> context;
};
SdkBridgeLightCluster::SdkBridgeLightCluster(chip::EndpointId endpoint, chip::TimerDelegate &timer,
                                             chip::scenes::ScenesIntegrationDelegate &scenes,
                                             BridgeStorage &storage, std::optional<bool> &approved,
                                             std::uint8_t &startup)
    : Base(endpoint,
           {.timerDelegate = timer, .effectDelegate = *this, .scenesIntegrationDelegate = &scenes}),
      impl_(std::make_unique<Impl>(endpoint, scenes, storage, approved, startup)) {}
SdkBridgeLightCluster::~SdkBridgeLightCluster() = default;
CHIP_ERROR SdkBridgeLightCluster::Startup(chip::app::ServerClusterContext &context) {
  impl_->Healthy();
  if (impl_->context) return CHIP_ERROR_INCORRECT_STATE;
  impl_->persistence = &context.attributeStorage;
  impl_->context.emplace(chip::app::ServerClusterContext{context.provider, context.storage, *impl_,
                                                         context.interactionContext});
  return Base::Startup(*impl_->context);
}
Action SdkBridgeLightCluster::ReadAttribute(
    const chip::app::DataModel::ReadAttributeRequest &request,
    chip::app::AttributeValueEncoder &encoder) {
  impl_->Healthy();
  if (request.path.mAttributeId == 0) {
    const auto approved = impl_->approved;
    return approved ? encoder.Encode(*approved) : Action(Status::Failure);
  }
  if (request.path.mAttributeId == 0x4003) return encoder.Encode(ConfiguredStartup(impl_->startup));
  return Base::ReadAttribute(request, encoder);
}
Action SdkBridgeLightCluster::WriteAttribute(
    const chip::app::DataModel::WriteAttributeRequest &request,
    chip::app::AttributeValueDecoder &decoder) {
  impl_->Healthy();
  if (request.path.mAttributeId != 0x4003) return Base::WriteAttribute(request, decoder);
  StartupValue decoded;
  ReturnErrorOnFailure(decoder.Decode(decoded));
  if (!decoded.IsNull() && static_cast<std::uint8_t>(decoded.Value()) > 2)
    return Status::ConstraintError;
  const std::uint8_t copied = decoded.IsNull() ? 0xFF : static_cast<std::uint8_t>(decoded.Value());
  if (copied == impl_->startup) return Action::FixedStatus::kWriteSuccessNoOp;
  ReturnErrorOnFailure(impl_->WriteValue(request.path, chip::ByteSpan(&copied, 1)));
  impl_->startup = copied;
  NotifyAttributeChanged(0x4003);
  return Status::Success;
}
CHIP_ERROR SdkBridgeLightCluster::SerializeSave(chip::EndpointId endpoint, chip::ClusterId cluster,
                                                chip::MutableByteSpan &serialized) {
  impl_->Healthy();
  if (endpoint != impl_->endpoint || cluster != 6) return CHIP_ERROR_INVALID_ARGUMENT;
  const auto approved = impl_->approved;
  if (!approved) return CHIP_ERROR_READ_FAILED;
  using Pair = chip::app::Clusters::ScenesManagement::Structs::AttributeValuePairStruct::Type;
  Pair value;
  value.attributeID = 0;
  value.valueUnsigned8.SetValue(*approved ? 1 : 0);
  return EncodeAttributeValueList(chip::app::DataModel::List<Pair>(&value, 1), serialized);
}
void SdkBridgeLightCluster::Observed() {
  impl_->Healthy();
  const auto approved = impl_->approved;
  if (!approved) return;
  mOnOff = *approved;
  if (impl_->scenes.MakeSceneInvalidForAllFabrics() != CHIP_NO_ERROR)
    std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  NotifyAttributeChanged(0);
}
Action SdkBridgeLightCluster::TriggerDelayedAllOff(
    chip::app::Clusters::OnOff::DelayedAllOffEffectVariantEnum) {
  // Physical effects were handled by the completed consumer operation.
  return Status::Success;
}
Action SdkBridgeLightCluster::TriggerDyingLight(
    chip::app::Clusters::OnOff::DyingLightEffectVariantEnum) {
  return Status::Success;
}
}
