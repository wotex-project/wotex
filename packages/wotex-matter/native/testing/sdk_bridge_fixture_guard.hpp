#ifndef WOTEX_MATTER_SDK_BRIDGE_FIXTURE_GUARD_HPP
#define WOTEX_MATTER_SDK_BRIDGE_FIXTURE_GUARD_HPP

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Synthetic invoke guards require an explicit test build.
#endif

#include "wotex_matter/bridge_requests.hpp"

namespace wotex::matter::testing {

// Explicit synthetic ownership fixture, never an authentication/ACL fallback.
class FixtureInvokeGuard final : public BridgeInvokeGuard {
 public:
  CHIP_ERROR capture_error{CHIP_NO_ERROR};
  CHIP_ERROR validation_error{CHIP_NO_ERROR};
  unsigned captures{0}, validations{0};
  std::uint64_t capture_epoch{7};
  BridgeInvokeScope last;
  CHIP_ERROR Capture(const BridgeRequestMetadata &request,
                     BridgeInvokeScope &scope) noexcept override {
    ++captures;
    if (capture_error != CHIP_NO_ERROR) return capture_error;
    BridgeInvokeScope copied;
    copied.request = request;
    copied.fabric.principal = request.principal;
    copied.fabric.epoch = capture_epoch;
    scope = copied;
    return CHIP_NO_ERROR;
  }
  CHIP_ERROR Validate(const BridgeInvokeScope &scope) noexcept override {
    ++validations;
    last = scope;
    return validation_error;
  }
};

} // namespace wotex::matter::testing

#endif
