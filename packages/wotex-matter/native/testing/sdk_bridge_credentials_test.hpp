#ifndef WOTEX_MATTER_SDK_BRIDGE_CREDENTIALS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_CREDENTIALS_TEST_HPP

#include "wotex_matter/bridge_credentials.hpp"

namespace wotex::matter::testing {
// Explicit test-only SDK development material, never a production fallback.
std::unique_ptr<SdkBridgeCredentials> CreateTestCredentials();
void TestCredentials();
}
#endif
