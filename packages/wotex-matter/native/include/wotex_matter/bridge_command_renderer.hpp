#ifndef WOTEX_MATTER_BRIDGE_COMMAND_RENDERER_HPP
#define WOTEX_MATTER_BRIDGE_COMMAND_RENDERER_HPP

#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_requests.hpp"

namespace wotex::matter {

// Internal finite command renderer. Explicit attachment precedes consumer
// receiver admission; Finish follows receiver retirement. The endpoint owner
// outlives this renderer. Calls hold the SDK lock and Completed is valid only
// after consumer completion and current scope validation. It grants no policy.
// Construction starts no SDK, filesystem or thread work.
class SdkBridgeCommandRenderer final : public BridgeInvokeReply {
 public:
  SdkBridgeCommandRenderer() = default;
  ~SdkBridgeCommandRenderer() override;
  SdkBridgeCommandRenderer(const SdkBridgeCommandRenderer &) = delete;
  SdkBridgeCommandRenderer &operator=(const SdkBridgeCommandRenderer &) = delete;
  CHIP_ERROR Attach(SdkBridgeEndpointBinding &endpoints) noexcept;
  CHIP_ERROR Finish() noexcept;
  CHIP_ERROR Completed(chip::app::CommandHandler &handler,
                       const BridgeInvocation &invocation) noexcept override;

 private:
  SdkBridgeEndpointBinding *endpoints_{nullptr};
  bool used_{false}, finished_{false};
};
}
#endif
