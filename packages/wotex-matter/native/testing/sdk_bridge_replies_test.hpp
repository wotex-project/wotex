#ifndef WOTEX_MATTER_SDK_BRIDGE_REPLIES_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_REPLIES_TEST_HPP

#include "wotex_matter/bridge_server.hpp"

namespace wotex::matter::testing {

void VerifyBridgeReplies(SdkBridgeServerBinding &server, BridgeConsumerHandoff &handoff,
                         bool retain_adapter);

} // namespace wotex::matter::testing

#endif
