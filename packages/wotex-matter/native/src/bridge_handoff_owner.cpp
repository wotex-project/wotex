#include "wotex_matter/bridge_handoff_owner.hpp"

#include <chrono>
#include <cstdlib>

namespace wotex::matter {

BridgeHandoffOwner::BridgeHandoffOwner(BridgeConsumerHandoff &custody, BridgeHandoffClock &clock)
    : custody_(custody), clock_(clock) {}

BridgeHandoffOwner::~BridgeHandoffOwner() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (waiting_ != 0 || custody_.pending() != 0) std::_Exit(kUnconsumedExit);
}

BridgeConsumerHandoff::Reply BridgeHandoffOwner::Resolve(
    const BridgeConsumerHandoff::Ticket &ticket, BridgeConsumerHandoff::Outcome outcome) {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto result = custody_.Resolve(ticket, outcome, clock_.NowMs());
  changed_.notify_all();
  return result;
}

BridgeConsumerHandoff::Consume BridgeHandoffOwner::Wait(const BridgeConsumerHandoff::Ticket &ticket,
                                                        BridgeConsumerHandoff::Outcome &outcome) {
  std::unique_lock<std::mutex> lock(mutex_);
  for (;;) {
    const auto now = clock_.NowMs();
    const auto result = custody_.Take(ticket, now, outcome);
    if (result != BridgeConsumerHandoff::Consume::Pending) return result;
    const auto deadline = custody_.Deadline(ticket);
    if (!deadline || *deadline <= now) std::_Exit(kUnconsumedExit);
    ++waiting_;
    // Recheck the original absolute deadline after every wake. Neither a
    // spurious wake nor a delayed staged result can extend admission.
    changed_.wait_for(lock, std::chrono::milliseconds(*deadline - now));
    --waiting_;
  }
}

void BridgeHandoffOwner::Close() {
  std::lock_guard<std::mutex> lock(mutex_);
  custody_.Close();
  changed_.notify_all();
}

} // namespace wotex::matter
