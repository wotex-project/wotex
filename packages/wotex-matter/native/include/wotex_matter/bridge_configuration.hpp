#ifndef WOTEX_MATTER_BRIDGE_CONFIGURATION_HPP
#define WOTEX_MATTER_BRIDGE_CONFIGURATION_HPP

#include "wotex_matter/bridge_endpoints.hpp"
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace wotex::matter {

// Explicit bootstrap configuration values. Credentials remain in
// separately bounded private files. Thing/bridge identities use lowercase hex
// so JSON cannot replace or constrain their opaque byte identity.
struct BridgeConfiguration {
  BridgeIdentity identity;
  std::string vendor_name, product_name, hardware_version_string;
  std::uint16_t hardware_version{0};
  std::string store_path;
  StorageMode store_mode{StorageMode::OpenExisting};
  std::string interface;
  std::uint16_t port{0};
  // Zero explicitly selects a closed window; 180..900 selects one finite
  // startup window. Decoding does not open it or perform commissioning.
  std::uint16_t commissioning_window_seconds{0};
  std::string dac_path, pai_path, declaration_path, key_path, commissioning_path;
  std::vector<BridgeDeviceConfiguration> devices;
};
enum class BridgeConfigurationDecode { Decoded, Malformed, Oversized, NoMemory };
// This bounded decoder performs no filesystem access, provider installation or
// SDK startup. Failure preserves the caller's existing configuration owner.
BridgeConfigurationDecode DecodeBridgeConfiguration(
    std::string_view bytes, std::unique_ptr<BridgeConfiguration> &result) noexcept;
} // namespace wotex::matter
#endif
