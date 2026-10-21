#ifndef WOTEX_MATTER_BRIDGE_LIGHT_HPP
#define WOTEX_MATTER_BRIDGE_LIGHT_HPP

#include "wotex_matter/bridge_storage.hpp"

#include <app/clusters/on-off-server/OnOffLightingCluster.h>
#include <memory>
#include <optional>

namespace wotex::matter {

// Internal finite lighting adapter. SDK commands/timers own protocol state;
// only the explicit observation reference supplies public OnOff truth and
// scene snapshots. Command-generated OnOff writes are never persisted.
// All calls hold the SDK stack lock. The state/storage/delegates outlive this
// cluster, which is unregistered and destroyed before endpoint retirement.
class SdkBridgeLightCluster final : public chip::app::Clusters::OnOffLightingCluster,
                                    private chip::app::Clusters::OnOffEffectDelegate {
 public:
  SdkBridgeLightCluster(chip::EndpointId endpoint, chip::TimerDelegate &timer,
                        chip::scenes::ScenesIntegrationDelegate &scenes, BridgeStorage &storage,
                        std::optional<bool> &approved, std::uint8_t &startup);
  ~SdkBridgeLightCluster() override;
  CHIP_ERROR Startup(chip::app::ServerClusterContext &context) override;
  chip::app::DataModel::ActionReturnStatus ReadAttribute(
      const chip::app::DataModel::ReadAttributeRequest &request,
      chip::app::AttributeValueEncoder &encoder) override;
  chip::app::DataModel::ActionReturnStatus WriteAttribute(
      const chip::app::DataModel::WriteAttributeRequest &request,
      chip::app::AttributeValueDecoder &decoder) override;
  CHIP_ERROR SerializeSave(chip::EndpointId endpoint, chip::ClusterId cluster,
                           chip::MutableByteSpan &serialized) override;
  // Called only for an actual change in the approved observation reference.
  void Observed();

 private:
  chip::app::DataModel::ActionReturnStatus TriggerDelayedAllOff(
      chip::app::Clusters::OnOff::DelayedAllOffEffectVariantEnum) override;
  chip::app::DataModel::ActionReturnStatus TriggerDyingLight(
      chip::app::Clusters::OnOff::DyingLightEffectVariantEnum) override;
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
#endif
