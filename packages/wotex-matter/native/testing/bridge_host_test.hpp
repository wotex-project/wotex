#ifndef WOTEX_MATTER_BRIDGE_HOST_TEST_HPP
#define WOTEX_MATTER_BRIDGE_HOST_TEST_HPP
#include <string>
#include <string_view>
namespace wotex::matter::testing {
int RunBridgeHostProbe(const std::string &root, std::string_view mode, const char *executable);
}
#endif
