#ifndef WOTEX_MATTER_SDK_BRIDGE_REQUESTS_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_REQUESTS_TEST_HPP

#include "wotex_matter/bridge_handoff.hpp"

#include <memory>

namespace wotex::matter::testing {

class RequestProbe {
 public:
  virtual ~RequestProbe() = default;
  virtual void DuringLoop() = 0;
  virtual void Finish() = 0;
};

std::unique_ptr<RequestProbe> PrepareRequests(BridgeConsumerHandoff &handoff, bool invalidate);

} // namespace wotex::matter::testing

#endif
