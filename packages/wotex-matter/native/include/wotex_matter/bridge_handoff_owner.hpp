#ifndef WOTEX_MATTER_BRIDGE_HANDOFF_OWNER_HPP
#define WOTEX_MATTER_BRIDGE_HANDOFF_OWNER_HPP

#include "wotex_matter/bridge_handoff.hpp"

#include <condition_variable>
#include <mutex>
#include <utility>

namespace wotex::matter {

// Explicit elapsed-time port. Samples belong to one monotonic millisecond
// clock that advances during real waits. Calls are serialized by the owner;
// the clock must not block, throw or reenter that owner.
class BridgeHandoffClock {
 public:
  virtual ~BridgeHandoffClock() = default;
  virtual std::uint64_t NowMs() noexcept = 0;
};

// Internal thread owner for borrowed request custody and its explicit clock.
// SDK operations use With under the SDK stack lock; input resolution/closure
// use only this owner's mutex. Wait releases that mutex while blocked, so a
// synchronous SDK callback may retain its stack lock without blocking input.
// With callbacks must not block, reenter or let borrowed custody escape.
// Startup precedes reader threads. Close, drain contexts and join every caller
// before destruction or direct server shutdown touches the borrowed custody.
// This owner neither schedules SDK work nor authorizes consumer execution.
class BridgeHandoffOwner final {
 public:
  static constexpr int kUnconsumedExit = 70;

  BridgeHandoffOwner(BridgeConsumerHandoff &custody, BridgeHandoffClock &clock);
  ~BridgeHandoffOwner();
  BridgeHandoffOwner(const BridgeHandoffOwner &) = delete;
  BridgeHandoffOwner &operator=(const BridgeHandoffOwner &) = delete;

  template <class Callback>
  auto With(Callback &&callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    // SDK context cleanup can close custody through the borrowed reference.
    // Wake synchronous waiters on that path, including callback failure.
    struct Wake {
      std::condition_variable &changed;
      ~Wake() { changed.notify_all(); }
    } wake{changed_};
    return std::forward<Callback>(callback)(custody_, clock_.NowMs());
  }

  BridgeConsumerHandoff::Reply Resolve(const BridgeConsumerHandoff::Ticket &ticket,
                                       BridgeConsumerHandoff::Outcome outcome);
  BridgeConsumerHandoff::Consume Wait(const BridgeConsumerHandoff::Ticket &ticket,
                                      BridgeConsumerHandoff::Outcome &outcome);
  void Close();

 private:
  // Tests observe the wait handshake and inject spurious wakes; production
  // has no public waiter or notification controls.
  friend struct BridgeHandoffOwnerTestAccess;
  BridgeConsumerHandoff &custody_;
  BridgeHandoffClock &clock_;
  std::mutex mutex_;
  std::condition_variable changed_;
  unsigned waiting_{0};
};

} // namespace wotex::matter

#endif
