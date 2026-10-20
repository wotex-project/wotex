#ifndef WOTEX_MATTER_SDK_BRIDGE_COMMAND_ARGUMENTS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_COMMAND_ARGUMENTS_TEST_HPP

#include "wotex_matter/bridge_guard.hpp"

namespace wotex::matter::testing {
void VerifyBridgeCommandArguments(SdkBridgeInvokeGuard &guard,
                                  const chip::Access::SubjectDescriptor &principal);
}
#endif
