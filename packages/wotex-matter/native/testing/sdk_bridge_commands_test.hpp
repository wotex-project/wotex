#ifndef WOTEX_MATTER_SDK_BRIDGE_COMMANDS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_COMMANDS_TEST_HPP
#include <string>
#include <string_view>
namespace wotex::matter::testing {
int RunSdkCommandsProbe(const std::string &root, std::string_view mode);
}
#endif
