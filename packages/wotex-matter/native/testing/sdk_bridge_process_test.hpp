#ifndef WOTEX_MATTER_SDK_BRIDGE_PROCESS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_PROCESS_TEST_HPP
#include <string>
#include <string_view>
namespace wotex::matter::testing {
// Borrow the already generated private development fixture; SDK memory has
// been shut down before entry. Each executable owns one SDK server lifetime.
int RunSdkProcessProbe(const std::string &root, std::string_view mode);
}
#endif
