#ifndef WOTEX_MATTER_BRIDGE_BOOTSTRAP_HPP
#define WOTEX_MATTER_BRIDGE_BOOTSTRAP_HPP
#include "wotex_matter/bridge_configuration.hpp"
#include "wotex_matter/bridge_credentials.hpp"

namespace wotex::matter {
// Caller initializes SDK memory before Load, explicitly installs providers
// afterward, then retires their global references before releasing or replacing
// this owner. Provider references may not outlive their explicit configuration.
// Loading performs no platform/server startup, provider selection or network I/O.
// Failure preserves the prior owner and returns a fixed classification without paths.
struct BridgeBootstrap {
  std::unique_ptr<BridgeConfiguration> configuration;
  std::unique_ptr<SdkBridgeCredentials> credentials;
};
enum class BootstrapLoad { Loaded, File, Configuration, Credentials, NoMemory };
BootstrapLoad LoadBootstrap(std::string_view path,
                            std::unique_ptr<BridgeBootstrap> &result) noexcept;
} // namespace wotex::matter
#endif
