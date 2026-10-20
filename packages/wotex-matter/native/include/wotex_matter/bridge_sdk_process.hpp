#ifndef WOTEX_MATTER_BRIDGE_SDK_PROCESS_HPP
#define WOTEX_MATTER_BRIDGE_SDK_PROCESS_HPP

#include "wotex_matter/bridge_process.hpp"
#include "wotex_matter/bridge_sdk_bootstrap.hpp"
#include "wotex_matter/bridge_sdk_observations.hpp"

namespace wotex::matter {

// Internal request-owner composition port, never a consumer-policy substitute.
// Attach/Finish hold the SDK stack lock. Attach precedes event-loop startup;
// Finish follows input retirement and closes/drains every retained context
// before the event loop stops. Finish must support partial Attach failure.
// The receiver and its configuration outlive the driver. Queued SDK work must
// observe retirement and must not outlive joined SDK shutdown.
class BridgeSdkProcessReceiver : public BridgeReceiver {
 public:
  virtual CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, BridgeConsumerHandoff &shared,
                            BridgeHandoffOwner &custody, BridgeOutputOwner &output) noexcept = 0;
  // Input-thread notification after result resolution, without custody/SDK
  // locks. Must be bounded and nonblocking; SDK work is separately scheduled.
  virtual bool ResultReady(const BridgeConsumerHandoff::Ticket &ticket) noexcept = 0;
  virtual CHIP_ERROR Finish() noexcept = 0;
};

// One explicitly selected private configuration and one SDK lifetime in this
// native process. Construction performs no SDK, filesystem or network access.
// RunBridgeProcess owns open/ready/closed, deadlines, pipes and cancellation.
// This adapter owns memory, private loading, SDK resources, receiver attachment
// and joined shutdown. It supplies no default receiver or authentication claim.
class SdkBridgeProcessDriver final : public BridgeProcessDriver {
 public:
  SdkBridgeProcessDriver(std::string configuration, BridgeSdkProcessReceiver &receiver);
  ~SdkBridgeProcessDriver() override;
  SdkBridgeProcessDriver(const SdkBridgeProcessDriver &) = delete;
  SdkBridgeProcessDriver &operator=(const SdkBridgeProcessDriver &) = delete;

  bool Start(BridgeConsumerHandoff &custody, BridgeHandoffOwner &owner, BridgeOutputOwner &output,
             const std::atomic<bool> &cancel) noexcept override;
  bool Ready(const BridgeConsumerHandoff::Ticket &ticket) noexcept override;
  bool Observe(const BridgeConsumerHandoff::Generation &generation,
               BridgeObservationFrame &&frame) noexcept override;
  bool Stop() noexcept override;

 private:
  const std::string configuration_;
  BridgeSdkProcessReceiver &receiver_;
  BridgeHandoffOwner *custody_{nullptr};
  std::unique_ptr<BridgeBootstrap> bootstrap_;
  std::unique_ptr<SdkBridgeBootstrap> runtime_;
  std::unique_ptr<SdkBridgeObservationOwner> observations_;
  std::atomic<bool> accepting_{false};
  bool used_{false}, memory_{false}, initialized_{false}, attached_{false}, loop_{false},
      stopped_{false};
};

} // namespace wotex::matter
#endif
