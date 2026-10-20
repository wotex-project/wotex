#include "wotex_matter/bridge_handoff_owner.hpp"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <future>
#include <functional>
#include <iostream>
#include <thread>
#include <vector>
#include <sys/wait.h>
#include <unistd.h>

namespace wotex::matter {

struct BridgeHandoffOwnerTestAccess {
  static unsigned Waiters(BridgeHandoffOwner &owner) {
    std::lock_guard<std::mutex> lock(owner.mutex_);
    return owner.waiting_;
  }
  static void Wake(BridgeHandoffOwner &owner) { owner.changed_.notify_all(); }
};

} // namespace wotex::matter

namespace {

using Handoff = wotex::matter::BridgeConsumerHandoff;
using Owner = wotex::matter::BridgeHandoffOwner;
using Clock = wotex::matter::BridgeHandoffClock;
using Access = wotex::matter::BridgeHandoffOwnerTestAccess;

void Require(bool value, const char *stage) {
  if (!value) {
    std::cerr << stage << '\n';
    std::exit(1);
  }
}

class SteadyClock final : public Clock {
 public:
  std::uint64_t NowMs() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
};

class ControlledClock final : public Clock {
 public:
  std::atomic<std::uint64_t> now{100};
  std::uint64_t NowMs() noexcept override { return now.load(); }
};

class SamplingClock final : public Clock {
 public:
  std::uint64_t NowMs() noexcept override {
    Require(!sampling_.exchange(true), "clock sampled outside serialized custody");
    const auto now = next_++;
    std::this_thread::yield();
    sampling_ = false;
    return now;
  }

 private:
  std::atomic<bool> sampling_{false};
  std::uint64_t next_{100};
};

class Progress final : public wotex::matter::BridgeHandoffProgress {
 public:
  explicit Progress(std::function<bool()> callback) : callback_(std::move(callback)) {}
  bool Advance() noexcept override try {
    ++calls;
    return callback_();
  } catch (...) {
    std::_Exit(1);
  }
  unsigned calls{0};
 private:
  const std::function<bool()> callback_;
};

Handoff::Ticket Reserve(Owner &owner, std::uint64_t duration = 500) {
  Handoff::Ticket ticket;
  owner.With([&](Handoff &custody, std::uint64_t now) {
    Require(custody.Reserve(now, now + duration, ticket) == Handoff::Admission::Reserved,
            "request not admitted");
  });
  return ticket;
}

void AwaitWaiter(Owner &owner) {
  const auto limit = std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (Access::Waiters(owner) == 0 && std::chrono::steady_clock::now() < limit)
    std::this_thread::yield();
  Require(Access::Waiters(owner) != 0, "wait handshake did not complete");
}

void ResolveDuringSdkWait() {
  SteadyClock clock;
  Handoff custody({1});
  Owner owner(custody, clock);
  std::mutex sdk_lock;
  std::promise<Handoff::Ticket> admitted;
  auto ticket_future = admitted.get_future();
  std::thread sdk([&] {
    std::lock_guard<std::mutex> sdk_guard(sdk_lock);
    const auto ticket = Reserve(owner);
    admitted.set_value(ticket);
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(owner.Wait(ticket, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::Completed,
            "synchronous completion not consumed");
  });
  Require(ticket_future.wait_for(std::chrono::seconds(2)) == std::future_status::ready,
          "SDK admission deadline");
  const auto ticket = ticket_future.get();
  AwaitWaiter(owner);
  Require(!sdk_lock.try_lock(), "SDK callback did not retain its stack lock");
  Require(owner.Resolve(ticket, Handoff::Outcome::Completed) == Handoff::Reply::Stored,
          "input reader could not resolve without SDK stack lock");
  sdk.join();
  owner.With([](Handoff &value, std::uint64_t) {
    Require(value.pending() == 0, "synchronous credit not released");
  });
}

void ConcurrentCapacity() {
  SamplingClock clock;
  Handoff custody({2});
  Owner owner(custody, clock);
  std::atomic<bool> go{false};
  std::atomic<unsigned> admitted{0}, busy{0};
  std::vector<Handoff::Ticket> tickets;
  std::vector<std::thread> threads;
  tickets.reserve(Handoff::kCapacity);
  threads.reserve(64);
  for (unsigned index = 0; index < 64; ++index) {
    threads.emplace_back([&] {
      while (!go) std::this_thread::yield();
      owner.With([&](Handoff &value, std::uint64_t now) {
        Handoff::Ticket ticket;
        const auto result = value.Reserve(now, now + 500, ticket);
        if (result == Handoff::Admission::Reserved) {
          ++admitted;
          tickets.push_back(ticket);
        } else {
          Require(result == Handoff::Admission::Busy, "concurrent clock sample regressed");
          ++busy;
        }
      });
    });
  }
  go = true;
  for (auto &thread : threads) thread.join();
  Require(admitted == 16 && busy == 48, "concurrent capacity exceeded");
  for (const auto &ticket : tickets)
    Require(owner.Resolve(ticket, Handoff::Outcome::Denied) == Handoff::Reply::Stored,
            "concurrent refusal not staged");
  owner.With([](Handoff &value, std::uint64_t) {
    Require(value.pending() == 16, "staging released request credit");
  });
  for (const auto &ticket : tickets) {
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(owner.Wait(ticket, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::Denied,
            "concurrent refusal not consumed");
  }
}

void ExpiryClockAndIdentity() {
  ControlledClock clock;
  Handoff custody({3});
  Owner owner(custody, clock);
  const auto ticket = Reserve(owner);
  clock.now = 101;
  Require(owner.Resolve(ticket, Handoff::Outcome::Completed) == Handoff::Reply::Stored,
          "completion not staged");
  clock.now = 600;
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(owner.Wait(ticket, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::TimedOut,
          "staged completion revived after absolute expiry");
  const auto next = Reserve(owner);
  clock.now = 599;
  Require(owner.Resolve(next, Handoff::Outcome::Denied) == Handoff::Reply::InvalidClock &&
              owner.Wait(next, outcome) == Handoff::Consume::InvalidClock &&
              outcome == Handoff::Outcome::TimedOut,
          "clock regression changed custody or output");
  auto foreign = next;
  foreign.generation[15] = 1;
  Require(owner.Resolve(foreign, Handoff::Outcome::Completed) == Handoff::Reply::UnknownTicket &&
              owner.Wait(foreign, outcome) == Handoff::Consume::UnknownTicket,
          "foreign owner ticket admitted");
  clock.now = 600;
  owner.Close();
  Require(owner.Wait(next, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Closed,
          "closed context not consumed");
}

void ClosureWake(bool through_callback) {
  ControlledClock clock;
  Handoff custody({4});
  Owner owner(custody, clock);
  const auto ticket = Reserve(owner);
  auto waiting = std::async(std::launch::async, [&] {
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(owner.Wait(ticket, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::Closed,
            "closure did not retire synchronous request");
  });
  AwaitWaiter(owner);
  if (through_callback) owner.With([](Handoff &value, std::uint64_t) { value.Close(); });
  else owner.Close();
  Require(waiting.wait_for(std::chrono::milliseconds(200)) == std::future_status::ready,
          "closure waited for the 500 ms deadline");
  waiting.get();
  owner.With([](Handoff &value, std::uint64_t now) {
    Handoff::Ticket refused;
    Require(value.pending() == 0 &&
                value.Reserve(now, now + 500, refused) == Handoff::Admission::Closed,
            "closed owner admitted another request");
  });
}

void SpuriousWakeDeadline() {
  SteadyClock clock;
  Handoff custody({5});
  Owner owner(custody, clock);
  const auto ticket = Reserve(owner, 30);
  std::atomic<bool> done{false};
  std::thread waker([&] {
    while (!done) {
      Access::Wake(owner);
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  });
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  const auto start = clock.NowMs();
  Require(owner.Wait(ticket, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::TimedOut,
          "synchronous wait did not expire");
  done = true;
  waker.join();
  Require(clock.NowMs() - start < 500, "spurious wakes extended the absolute deadline");
}

void MissingDrain() {
  const auto child = fork();
  Require(child >= 0, "missing-drain child unavailable");
  if (child == 0) {
    ControlledClock clock;
    Handoff custody({6});
    {
      Owner owner(custody, clock);
      Reserve(owner);
      owner.Close();
    }
    std::_Exit(1);
  }
  int status = 0;
  Require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == Owner::kUnconsumedExit,
          "destruction released unconsumed custody");
}

void SynchronousProgress() {
  for (const bool refused : {false, true}) {
    ControlledClock clock;
    Handoff custody({7});
    Owner owner(custody, clock);
    const auto ticket = Reserve(owner);
    Progress progress([&] {
      // Reentry proves Advance runs after releasing the custody mutex.
      owner.With(
          [](auto &value, auto) { Require(value.pending() == 1, "progress lost request credit"); });
      Require(owner.Resolve(ticket, Handoff::Outcome::Completed) == Handoff::Reply::Stored,
              "progress could not publish completion");
      return !refused;
    });
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(owner.Wait(ticket, outcome, progress) == Handoff::Consume::Completed &&
                outcome == (refused ? Handoff::Outcome::Closed : Handoff::Outcome::Completed),
            "progress refusal promoted staged completion");
    Require(progress.calls == 1 && custody.pending() == 0 && custody.closed() == refused,
            "progress did not retain/consume exact custody");
  }
}

void ProgressDeadlineAndClock() {
  for (const auto finished_at : {599U, 600U}) {
    ControlledClock clock;
    Handoff custody({8});
    Owner owner(custody, clock);
    const auto ticket = Reserve(owner);
    Progress progress([&] {
      Require(owner.Resolve(ticket, Handoff::Outcome::Completed) == Handoff::Reply::Stored,
              "progress completion not staged");
      clock.now = finished_at;
      return true;
    });
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(owner.Wait(ticket, outcome, progress) == Handoff::Consume::Completed &&
                outcome ==
                    (finished_at == 599 ? Handoff::Outcome::Completed : Handoff::Outcome::TimedOut),
            "progress extended the original absolute deadline");
  }
  ControlledClock clock;
  Handoff custody({9});
  Owner owner(custody, clock);
  const auto ticket = Reserve(owner);
  Progress backwards([&] {
    clock.now = 99;
    return true;
  });
  Handoff::Outcome outcome = Handoff::Outcome::Denied;
  Require(owner.Wait(ticket, outcome, backwards) == Handoff::Consume::InvalidClock &&
              outcome == Handoff::Outcome::Denied && custody.pending() == 1,
          "progress clock regression changed output or consumed custody");
  clock.now = 100;
  owner.Close();
  Require(owner.Wait(ticket, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Closed,
          "progress clock refusal could not retire custody");
}

void PeriodicProgressAndClosedCustody() {
  ControlledClock clock;
  Handoff custody({10});
  Owner owner(custody, clock);
  const auto ticket = Reserve(owner, 20);
  Progress idle([&] {
    clock.now += 5;
    return true;
  });
  auto waiting = std::async(std::launch::async, [&] {
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(owner.Wait(ticket, outcome, idle) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::TimedOut,
            "idle progress wait did not expire");
  });
  Require(waiting.wait_for(std::chrono::seconds(2)) == std::future_status::ready,
          "progress required an external result notification");
  waiting.get();
  Require(idle.calls == 4, "progress did not recheck its original clock boundary");

  const auto closing = Reserve(owner);
  Progress close([&] {
    owner.Close();
    return true;
  });
  Handoff::Outcome outcome;
  Require(owner.Wait(closing, outcome, close) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Closed && close.calls == 1,
          "progress closure deadlocked or escaped as Success");
}

void NoUnneededProgress() {
  ControlledClock clock;
  Handoff custody({11});
  Owner owner(custody, clock);
  Progress forbidden([] { return false; });
  auto ticket = Reserve(owner);
  auto foreign = ticket;
  foreign.generation[0] = 12;
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(owner.Wait(foreign, outcome, forbidden) == Handoff::Consume::UnknownTicket,
          "foreign ticket gained progress");
  Require(owner.Resolve(ticket, Handoff::Outcome::Completed) == Handoff::Reply::Stored &&
              owner.Wait(ticket, outcome, forbidden) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Completed,
          "ready custody called unnecessary progress");
  ticket = Reserve(owner);
  clock.now = 600;
  Require(owner.Wait(ticket, outcome, forbidden) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::TimedOut && forbidden.calls == 0,
          "expired custody invoked progress");
}

} // namespace

int main() {
  MissingDrain();
  ResolveDuringSdkWait();
  ConcurrentCapacity();
  ExpiryClockAndIdentity();
  ClosureWake(false);
  ClosureWake(true);
  SpuriousWakeDeadline();
  SynchronousProgress();
  ProgressDeadlineAndClock();
  PeriodicProgressAndClosedCustody();
  NoUnneededProgress();
  std::cout << "bridge clocked custody, concurrent admission and synchronous deadlines passed\n";
}
