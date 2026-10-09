#ifndef WOTEX_MATTER_SDK_BRIDGE_ENDPOINTS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_ENDPOINTS_TEST_HPP

#include "wotex_matter/bridge_endpoints.hpp"

namespace wotex::matter::testing {

std::unique_ptr<SdkBridgeEndpointBinding> PrepareEndpoints(SdkBridgeServerBinding &server,
                                                           const std::string &mode);
CHIP_ERROR ObserveDuringLoop(SdkBridgeEndpointBinding &endpoints);
void PoisonEndpoints(SdkBridgeEndpointBinding &endpoints, const std::string &mode);
void FinishEndpoints(SdkBridgeEndpointBinding &endpoints, SdkBridgeServerBinding &server);

} // namespace wotex::matter::testing

#endif
