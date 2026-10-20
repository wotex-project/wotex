#include "wotex_matter/bridge_handoff_owner.hpp"

#include <chrono>
#include <algorithm>
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
  return Wait(ticket, outcome, nullptr);
}

BridgeConsumerHandoff::Consume BridgeHandoffOwner::Wait(const BridgeConsumerHandoff::Ticket &ticket,
                                                        BridgeConsumerHandoff::Outcome &outcome,
                                                        BridgeHandoffProgress &progress) {
  return Wait(ticket, outcome, &progress);
}

BridgeConsumerHandoff::Consume BridgeHandoffOwner::Wait(const BridgeConsumerHandoff::Ticket &ticket,
                                                        BridgeConsumerHandoff::Outcome &outcome,
                                                        BridgeHandoffProgress *progress) {
  std::unique_lock<std::mutex> lock(mutex_);
  for (;;) {
    auto now = clock_.NowMs();
    auto result = custody_.Take(ticket, now, outcome);
    if (result != BridgeConsumerHandoff::Consume::Pending) return result;
    const auto deadline = custody_.Deadline(ticket);
    if (!deadline || *deadline <= now) std::_Exit(kUnconsumedExit);
    if (progress) {
      lock.unlock();
      const bool advanced = progress->Advance();
      lock.lock();
      if (!advanced) {
        custody_.Close();
        changed_.notify_all();
      }
      // Progress may publish a result, close custody or consume real time.
      // Recheck before sleeping, using the same original absolute deadline.
      now = clock_.NowMs();
      result = custody_.Take(ticket, now, outcome);
      if (result != BridgeConsumerHandoff::Consume::Pending) return result;
    }
    ++waiting_;
    // Recheck the original absolute deadline after every wake. Neither a
    // spurious wake nor a delayed staged result can extend admission.
    const auto duration = progress ? std::min<std::uint64_t>(*deadline - now, 1) : *deadline - now;
    changed_.wait_for(lock, std::chrono::milliseconds(duration));
    --waiting_;
  }
}

void BridgeHandoffOwner::Close() {
  std::lock_guard<std::mutex> lock(mutex_);
  custody_.Close();
  changed_.notify_all();
}

} // namespace wotex::matter
