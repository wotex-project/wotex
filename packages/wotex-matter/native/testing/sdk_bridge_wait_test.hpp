#ifndef WOTEX_MATTER_SDK_BRIDGE_WAIT_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_WAIT_TEST_HPP

#include "wotex_matter/bridge_provider.hpp"

#include <memory>

namespace wotex::matter::testing {

// Explicit read-completion fixture. Synthetic principals and input results
// test native waiting ownership, without consumer policy or ACL claims.
class WaitProbe : public BridgeReceiver {
 public:
  virtual void Prepare(SdkBridgeServerBinding &server, SdkBridgeProviderBinding &provider) = 0;
  virtual void DuringLoop() = 0;
  virtual void Finish() = 0;
};

std::unique_ptr<WaitProbe> PrepareWait(BridgeConsumerHandoff &handoff,
                                       chip::app::DataModel::Provider &delegate);

} // namespace wotex::matter::testing

#endif
