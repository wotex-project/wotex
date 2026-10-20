#ifndef WOTEX_MATTER_BRIDGE_PROCESS_HPP
#define WOTEX_MATTER_BRIDGE_PROCESS_HPP

#include "wotex_matter/bridge_output.hpp"

namespace wotex::matter {

// Internal role-specific SDK composition port. The process owner supplies
// generation custody, its explicit native clock and bounded output. Start
// owns initialization and may enqueue requests, but may not publish controls
// or wait for consumer results before returning. Cancellation is cooperative;
// exceeding the original startup budget terminates the native process.
// Ready runs on the reader thread without an SDK/custody lock and must perform
// only bounded notification. Stop runs once after reader retirement and shared
// admission closure, including failed Start. It must drain all contexts and
// join/release SDK resources before returning true. It runs outside SDK locks;
// returning false or exceeding the one-second cleanup budget terminates the process.
// This port neither authenticates principals nor supplies a default SDK driver.
class BridgeProcessDriver {
 public:
  virtual ~BridgeProcessDriver() = default;
  virtual bool Start(BridgeConsumerHandoff &custody, BridgeHandoffOwner &owner,
                     BridgeOutputOwner &output, const std::atomic<bool> &cancel) noexcept = 0;
  virtual bool Ready(const BridgeConsumerHandoff::Ticket &ticket) noexcept = 0;
  virtual bool Stop() noexcept = 0;
};

enum class BridgeProcessExit : int {
  Closed = 0,
  Invalid = 64,
  Input = 65,
  Startup = 69,
  Cleanup = 70,
  Output = 74,
  Cancelled = 75
};

// Explicit process-lifetime coordinator, not an SDK implementation or generic
// process launcher. Borrows distinct exclusive input/output pipe descriptors,
// clock, driver and cancellation flag; all outlive this call. The caller owns
// descriptors and SIGPIPE disposition. Settable flags are restored on return.
// Startup milliseconds are 1..5000 and cover first open through ready admission.
// No driver call precedes an exact bounded open. Ready precedes queued requests;
// closed follows successful driver cleanup and completion of any active frame.
// Input/output loss produces no closed receipt. A stuck driver or final output
// exits the process with Cleanup; no unsafe SDK lifetime escapes by return.
BridgeProcessExit RunBridgeProcess(int input, int output, std::uint32_t startup_ms,
                                   BridgeHandoffClock &clock, BridgeProcessDriver &driver,
                                   const std::atomic<bool> &cancel) noexcept;

} // namespace wotex::matter
#endif
