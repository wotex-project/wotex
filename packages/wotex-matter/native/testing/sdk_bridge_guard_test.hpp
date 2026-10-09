#ifndef WOTEX_MATTER_SDK_BRIDGE_GUARD_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_GUARD_TEST_HPP

#include "wotex_matter/bridge_server.hpp"
#include <app/data-model-provider/Provider.h>

namespace wotex::matter::testing {
void VerifyBridgeGuard(SdkBridgeServerBinding &server, chip::app::DataModel::Provider &provider,
                       bool omit_finish);
} // namespace wotex::matter::testing

#endif
