#ifndef WOTEX_MATTER_BRIDGE_ENDPOINTS_HPP
#define WOTEX_MATTER_BRIDGE_ENDPOINTS_HPP

#include "wotex_matter/bridge_server.hpp"
#include "wotex_matter/bridge_observation.hpp"

#include <app/util/af-types.h>
#include <protocols/interaction_model/StatusCode.h>

#include <optional>
#include <vector>

namespace wotex::matter {

// Explicit consumer mapping for the selected finite Device Types. Temperature
// values use Matter's signed hundredths of a degree Celsius. An absent bound
// is an explicit unknown bound. These capabilities are fixed while registered.
struct BridgeDeviceConfiguration {
  std::string thing_id;
  BridgedDeviceType device_type{BridgedDeviceType::OnOffLight};
  std::string node_label;
  std::optional<std::int16_t> minimum_temperature;
  std::optional<std::int16_t> maximum_temperature;
};

// Internal SDK endpoint owner. All calls are serialized under the SDK stack
// lock. Initialize after the server binding and before starting its event loop;
// stop that loop and Finish before finishing the server binding. Its borrowed
// server binding outlives this owner and supplies its single authoritative
// store. Each native process has one endpoint lifetime.
//
// This class binds metadata, approved state and SDK cluster custody. It has no
// consumer Port or authenticated request handoff. Those boundaries must precede
// serving requests through a consumer-facing host.
class SdkBridgeEndpointBinding final {
 public:
  explicit SdkBridgeEndpointBinding(SdkBridgeServerBinding &server);
  ~SdkBridgeEndpointBinding();
  SdkBridgeEndpointBinding(const SdkBridgeEndpointBinding &) = delete;
  SdkBridgeEndpointBinding &operator=(const SdkBridgeEndpointBinding &) = delete;

  CHIP_ERROR Init(const std::vector<BridgeDeviceConfiguration> &configurations);
  CHIP_ERROR Add(const BridgeDeviceConfiguration &configuration, BridgeEndpoint &endpoint);
  CHIP_ERROR Remove(const std::string &thing_id);
  CHIP_ERROR Observe(const std::string &thing_id, std::uint16_t endpoint,
                     const BridgeObservation &observation);
  void Finish();
  bool initialized() const;

  // SDK generated external-storage callback. It refuses when the explicitly
  // initialized owner is absent or the endpoint/path has not been admitted.
  static chip::Protocols::InteractionModel::Status ReadExternal(
      chip::EndpointId endpoint, chip::ClusterId cluster, const EmberAfAttributeMetadata *attribute,
      std::uint8_t *buffer, std::uint16_t capacity);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace wotex::matter

#endif
