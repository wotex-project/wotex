#ifndef WOTEX_MATTER_SDK_BRIDGE_PROVIDER_TEST_HPP
#define WOTEX_MATTER_SDK_BRIDGE_PROVIDER_TEST_HPP

#include "wotex_matter/bridge_provider.hpp"

#include <memory>
#include <string>

namespace wotex::matter::testing {

// Explicit test receiver: attribute operations are refused and the selected
// invoke fixture retains a context for an explicit test completion. This is
// not a production policy or consumer-dispatch implementation.
class ProviderProbe {
 public:
  virtual ~ProviderProbe() = default;
  virtual BridgeReceiver &receiver() = 0;
  virtual void Verify(SdkBridgeServerBinding &server, SdkBridgeProviderBinding &provider,
                      chip::app::DataModel::Provider &delegate, const std::string &mode) = 0;
};

std::unique_ptr<ProviderProbe> PrepareProvider(BridgeConsumerHandoff &handoff);

} // namespace wotex::matter::testing

#endif
