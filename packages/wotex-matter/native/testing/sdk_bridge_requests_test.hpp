#ifndef WOTEX_MATTER_SDK_BRIDGE_REQUESTS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_REQUESTS_TEST_HPP

#include "wotex_matter/bridge_requests.hpp"

#include <memory>
#include <functional>

namespace wotex::matter::testing {

class RequestProbe {
 public:
  virtual ~RequestProbe() = default;
  virtual void DuringLoop() = 0;
  virtual void Finish() = 0;
};

std::unique_ptr<RequestProbe> PrepareRequests(BridgeConsumerHandoff &handoff, bool invalidate);

// Runs the retained owner with an actual supplied guard. The explicit fixture
// mutation occurs after staging completion and before native rendering.
void VerifyGuardedCompletion(BridgeInvokeGuard &guard,
                             const chip::Access::SubjectDescriptor &principal,
                             const std::function<void()> &retire, CHIP_ERROR error,
                             chip::Protocols::InteractionModel::Status status);

} // namespace wotex::matter::testing

#endif
