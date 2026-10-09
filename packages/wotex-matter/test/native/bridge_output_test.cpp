#include "wotex_matter/bridge_output.hpp"

#include <cassert>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <fcntl.h>
#include <future>
#include <iostream>
#include <limits>
#include <new>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {
std::atomic<bool> allocation_failure{false};
}
void *operator new(std::size_t size) {
  if (allocation_failure.exchange(false)) throw std::bad_alloc();
  if (auto *memory = std::malloc(size == 0 ? 1 : size)) return memory;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete[](void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, std::size_t) noexcept { std::free(memory); }
void operator delete[](void *memory, std::size_t) noexcept { std::free(memory); }

namespace wotex::matter {
struct BridgeOutputOwnerTestAccess {
  static std::size_t Bytes(BridgeOutputOwner &owner, BridgeOutputOwner::Kind kind) {
    std::lock_guard<std::mutex> lock(owner.mutex_);
    const auto begin = kind == BridgeOutputOwner::Kind::Request ? 0 : owner.kRequestCapacity;
    const auto end = kind == BridgeOutputOwner::Kind::Request ? owner.kRequestCapacity
                                                              : owner.slots_.size();
    std::size_t result = 0;
    for (std::size_t i = begin; i < end; ++i) result += owner.slots_[i].bytes;
    return result;
  }
  static void Exhaust(BridgeOutputOwner &owner) {
    std::lock_guard<std::mutex> lock(owner.mutex_);
    owner.next_ = std::numeric_limits<std::uint64_t>::max();
  }
  static BridgeOutputOwner::Admission Busy(BridgeOutputOwner &owner) {
    std::lock_guard<std::mutex> lock(owner.mutex_);
    auto result = BridgeOutputOwner::Admission::Accepted;
    std::thread contender([&] { result = owner.Push(BridgeOutputOwner::Kind::Control, "test\n"); });
    contender.join();
    return result;
  }
};
}

using namespace wotex::matter;
namespace {
using Output = BridgeOutputOwner;
using Kind = Output::Kind;
using Admission = Output::Admission;
using State = Output::State;
using Handoff = BridgeConsumerHandoff;

class Clock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
};
class Sink final : public BridgeOutputSink {
 public:
  explicit Sink(BridgeHandoffOwner &owner) : owner_(owner) {}
  void Closed() noexcept override {
    // Reenter custody to prove closure unlocks it before notifying.
    owner_.With([&](auto &core, auto) { assert(core.closed()); });
    ++closed;
  }
  BridgeHandoffOwner &owner_;
  std::atomic<unsigned> closed{0};
};
struct Fixture {
  Handoff core{{1}};
  Clock clock;
  BridgeHandoffOwner custody{core, clock};
  Sink sink{custody};
  Output output{custody, sink};
  Handoff::Ticket Reserve() {
    Handoff::Ticket ticket;
    custody.With([&](auto &owner, auto now) {
      assert(owner.Reserve(now, now + 500, ticket) == Handoff::Admission::Reserved);
    });
    return ticket;
  }
  void Drain(const Handoff::Ticket &ticket) {
    Handoff::Outcome result = Handoff::Outcome::Unknown;
    assert(custody.Wait(ticket, result) == Handoff::Consume::Completed &&
           result == Handoff::Outcome::Closed);
  }
};
std::string Maximum() { return std::string(Output::kMaximumRequestFrameBytes - 1, 'r') + '\n'; }

void AdmissionBounds() {
  Fixture fixture;
  auto &output = fixture.output;
  for (const auto &bytes : {std::string{}, std::string("missing LF"), std::string("\n\n"),
                            std::string("bad\r\n"), std::string("bad\0\n", 5)})
    assert(output.Push(Kind::Request, bytes) == Admission::Malformed);
  // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): deliberately forge an unsupported scoped-enum value to verify structured refusal.
  assert(output.Push(static_cast<Kind>(99), "test\n") == Admission::Malformed);
  assert(output.Push(Kind::Request, Maximum() + '\n') == Admission::Oversized);
  assert(output.Push(Kind::Control, std::string(512, 'c') + '\n') == Admission::Oversized);
  assert(BridgeOutputOwnerTestAccess::Busy(output) == Admission::Busy);
  auto maximum = Maximum();
  allocation_failure = true;
  assert(output.Push(Kind::Request, maximum) == Admission::NoMemory);
  for (unsigned i = 0; i < Output::kRequestCapacity; ++i) {
    assert(output.Push(Kind::Request, maximum) == Admission::Accepted);
  }
  maximum[0] = 'x'; // Caller storage is never retained.
  assert(output.Push(Kind::Request, maximum) == Admission::Full);
  const std::string control = std::string(511, 'c') + '\n';
  for (unsigned i = 0; i < Output::kControlCapacity; ++i)
    assert(output.Push(Kind::Control, control) == Admission::Accepted);
  assert(output.Push(Kind::Control, control) == Admission::Full);
  assert(BridgeOutputOwnerTestAccess::Bytes(output, Kind::Request) ==
         Output::kRequestCapacity * Output::kMaximumRequestFrameBytes);
  assert(BridgeOutputOwnerTestAccess::Bytes(output, Kind::Control) ==
         Output::kControlCapacity * Output::kMaximumControlFrameBytes);
  output.Close();
  output.Close();
  assert(fixture.sink.closed == 1 && output.Push(Kind::Control, control) == Admission::Closed);
  assert(BridgeOutputOwnerTestAccess::Bytes(output, Kind::Request) == 0);
  Fixture exhausted;
  BridgeOutputOwnerTestAccess::Exhaust(exhausted.output);
  assert(exhausted.output.Push(Kind::Request, "test\n") == Admission::Exhausted);
}

void Blocked(bool cancel, bool initially_nonblocking) {
  Fixture fixture;
  const auto ticket = fixture.Reserve();
  const auto maximum = Maximum();
  for (unsigned i = 0; i < Output::kRequestCapacity; ++i)
    assert(fixture.output.Push(Kind::Request, maximum) == Admission::Accepted);
  int descriptors[2];
  assert(pipe(descriptors) == 0);
  assert(fcntl(descriptors[1], F_SETFL, O_APPEND | (initially_nonblocking ? O_NONBLOCK : 0)) == 0);
  const int flags = fcntl(descriptors[1], F_GETFL);
  assert(flags >= 0);
  std::atomic<bool> stop{false};
  State terminal = State::Open;
  std::thread writer([&] { terminal = fixture.output.Run(descriptors[1], stop); });
  char first;
  assert(read(descriptors[0], &first, 1) == 1 && first == 'r');
  assert(BridgeOutputOwnerTestAccess::Bytes(fixture.output, Kind::Request) ==
         Output::kRequestCapacity * maximum.size());
  const auto full = fixture.output.Push(Kind::Request, maximum);
  assert(full == Admission::Full || full == Admission::Busy);
  // Contention refusal is explicit; this fixture retries only to inspect the
  // reserved control capacity while the writer remains blocked on the pipe.
  auto control = Admission::Busy;
  while (control == Admission::Busy) control = fixture.output.Push(Kind::Control, "control\n");
  assert(control == Admission::Accepted);
  assert(fixture.output.Run(-1, stop) == State::AlreadyRunning);
  if (cancel) stop = true;
  else assert(close(descriptors[0]) == 0);
  fixture.Drain(ticket);
  writer.join();
  assert(terminal == (cancel ? State::Cancelled : State::Write) && fixture.sink.closed == 1);
  assert(BridgeOutputOwnerTestAccess::Bytes(fixture.output, Kind::Request) == 0);
  assert(BridgeOutputOwnerTestAccess::Bytes(fixture.output, Kind::Control) == 0);
  // macOS exposes kernel write-history bits through F_GETFL. Compare the
  // public status flags, including every F_SETFL flag and the access mode.
  constexpr int status_flags = O_ACCMODE | O_APPEND | O_ASYNC | O_SYNC | O_DSYNC | O_NONBLOCK;
  const int restored = fcntl(descriptors[1], F_GETFL);
  assert(restored >= 0 && (restored & status_flags) == (flags & status_flags));
  if (cancel) assert(close(descriptors[0]) == 0);
  assert(close(descriptors[1]) == 0);
}

void Ordering() {
  Fixture fixture;
  std::string first = Maximum(), second = "second\n", control = "control\n";
  const std::string third = "third\n", next_control = "control-two\n";
  const auto expected = first + control + next_control + second + third;
  assert(fixture.output.Push(Kind::Request, first) == Admission::Accepted);
  assert(fixture.output.Push(Kind::Request, second) == Admission::Accepted);
  assert(fixture.output.Push(Kind::Request, third) == Admission::Accepted);
  first[0] = 'x';
  int descriptors[2];
  assert(pipe(descriptors) == 0);
  std::atomic<bool> stop{false};
  State terminal = State::Open;
  std::thread writer([&] { terminal = fixture.output.Run(descriptors[1], stop); });
  std::string received(1, '\0');
  assert(read(descriptors[0], received.data(), 1) == 1 && received[0] == 'r');
  auto pushed = Admission::Busy;
  while (pushed == Admission::Busy) pushed = fixture.output.Push(Kind::Control, control);
  assert(pushed == Admission::Accepted);
  pushed = Admission::Busy;
  while (pushed == Admission::Busy) pushed = fixture.output.Push(Kind::Control, next_control);
  assert(pushed == Admission::Accepted);
  control[0] = 'x';
  std::array<char, 8192> chunk{};
  while (received.size() < expected.size()) {
    const auto count = read(descriptors[0], chunk.data(),
                            std::min(chunk.size(), expected.size() - received.size()));
    assert(count > 0);
    received.append(chunk.data(), static_cast<std::size_t>(count));
  }
  assert(received == expected);
  fixture.output.Close();
  writer.join();
  assert(terminal == State::Ended && fixture.sink.closed == 1);
  assert(close(descriptors[0]) == 0 && close(descriptors[1]) == 0);
}

void IdleAndFailure() {
  Fixture fixture;
  const auto ticket = fixture.Reserve();
  int descriptors[2];
  assert(pipe(descriptors) == 0);
  assert(fcntl(descriptors[1], F_SETFL, O_NONBLOCK) == 0);
  const int flags = fcntl(descriptors[1], F_GETFL);
  std::atomic<bool> stop{false};
  State terminal = State::Open;
  std::thread writer([&] { terminal = fixture.output.Run(descriptors[1], stop); });
  stop = true;
  fixture.Drain(ticket);
  writer.join();
  assert(terminal == State::Cancelled && fcntl(descriptors[1], F_GETFL) == flags);
  assert(close(descriptors[0]) == 0 && close(descriptors[1]) == 0);
  assert(fixture.output.Run(-1, stop) == State::Cancelled);
  Fixture failed;
  const auto pending = failed.Reserve();
  assert(failed.output.Run(-1, stop) == State::Write);
  failed.Drain(pending);
  assert(failed.sink.closed == 1);
  Fixture lost;
  const auto awaiting = lost.Reserve();
  assert(pipe(descriptors) == 0);
  stop = false;
  std::thread idle([&] { terminal = lost.output.Run(descriptors[1], stop); });
  assert(close(descriptors[0]) == 0);
  lost.Drain(awaiting);
  idle.join();
  assert(terminal == State::Write && lost.sink.closed == 1);
  assert(close(descriptors[1]) == 0);
}

void LockOrdering() {
  Fixture fixture;
  std::future<void> closing;
  fixture.custody.With([&](auto &, auto) {
    closing = std::async(std::launch::async, [&] { fixture.output.Close(); });
    // The closer has retired output admission but waits for this custody
    // callback. Push must still return, proving no output-to-custody lock cycle.
    auto status = Admission::Accepted;
    while (status != Admission::Closed) {
      status = fixture.output.Push(Kind::Control, "test\n");
      assert(status == Admission::Accepted || status == Admission::Busy ||
             status == Admission::Full || status == Admission::Closed);
      std::this_thread::yield();
    }
  });
  assert(closing.wait_for(std::chrono::seconds(1)) == std::future_status::ready);
  closing.get();
  assert(fixture.sink.closed == 1);
}

void Concurrent() {
  Fixture fixture;
  std::atomic<unsigned> accepted{0}, refused{0};
  std::vector<std::thread> producers;
  producers.reserve(32);
  const auto maximum = Maximum();
  for (unsigned i = 0; i < 32; ++i)
    producers.emplace_back([&] {
      const auto result = fixture.output.Push(Kind::Request, maximum);
      if (result == Admission::Accepted) ++accepted;
      else {
        assert(result == Admission::Busy || result == Admission::Full);
        ++refused;
      }
    });
  for (auto &producer : producers) producer.join();
  assert(accepted <= Output::kRequestCapacity && accepted + refused == 32);
  assert(BridgeOutputOwnerTestAccess::Bytes(fixture.output, Kind::Request) ==
         accepted * maximum.size());
  fixture.output.Close();
}

void MissingClose() {
  const auto child = fork();
  assert(child >= 0);
  if (child == 0) {
    {
      Fixture fixture;
      assert(fixture.output.Push(Kind::Control, "test\n") == Admission::Accepted);
    }
    std::_Exit(1);
  }
  int status = 0;
  assert(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
         WEXITSTATUS(status) == Output::kUnjoinedExit);
}
}

int main() {
  std::signal(SIGPIPE, SIG_IGN);
  AdmissionBounds();
  Blocked(true, false);
  Blocked(false, false);
  Blocked(true, true);
  Blocked(false, true);
  Ordering();
  IdleAndFailure();
  LockOrdering();
  Concurrent();
  MissingClose();
  std::cout << "bridge output credit, control ordering, cancellation and custody closure passed\n";
}
