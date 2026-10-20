// SPDX-License-Identifier: Apache-2.0
#include "wotex_matter/bridge_process.hpp"
#include <atomic>
#include <cassert>
#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <iostream>
#include <poll.h>
#include <string>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

namespace {
using namespace wotex::matter;
using Exit = BridgeProcessExit;
using Time = std::chrono::steady_clock;
using namespace std::chrono_literals;
const std::string generation = "01000000000000000000000000000000";
std::string Control(const char *role) {
  return "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"" + std::string(role) +
      "\",\"generation\":\"" + generation + "\"}\n";
}
const std::string probe =
    "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-probe\",\"generation\":\"" +
    generation + "\",\"id\":\"1\"}\n";
const std::string result =
    "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"result\",\"generation\":\"" + generation +
    "\",\"id\":\"1\",\"outcome\":\"completed\"}\n";

class Clock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override { return 100; }
};
class Driver final : public BridgeProcessDriver {
 public:
  Driver(std::string mode, int audit = -1) : mode(std::move(mode)), audit(audit) {}
  bool Start(BridgeConsumerHandoff &custody, BridgeHandoffOwner &owner, BridgeOutputOwner &output,
             const std::atomic<bool> &cancel) noexcept override try {
    assert(!started && custody.Sample({1}, 100) == BridgeConsumerHandoff::ClockSample::Sampled);
    started = true;
    this->owner = &owner;
    if (mode == "slow-start") std::this_thread::sleep_for(60ms);
    if (mode == "stuck-start-lock")
      owner.With([&](auto &, auto) {
        assert(write(audit, "S", 1) == 1);
        while (true) std::this_thread::sleep_for(10ms);
      });
    if (mode == "stuck-start")
      while (true) std::this_thread::sleep_for(10ms);
    if (mode == "wait-start") {
      while (!cancel.load()) std::this_thread::sleep_for(1ms);
      return false;
    }
    if (mode == "fail-start") return false;
    if (mode == "requests" || mode == "blocked-output") {
      assert(custody.Reserve(100, 500, ticket) == BridgeConsumerHandoff::Admission::Reserved);
      const auto frame = mode == "requests"
          ? std::string("{\"request\":1}\n")
          : std::string(BridgeOutputOwner::kMaximumRequestFrameBytes - 1, 'x') + "\n";
      assert(output.Push(BridgeOutputOwner::Kind::Request, frame) ==
             BridgeOutputOwner::Admission::Accepted);
    }
    return true;
  } catch (...) {
    return false;
  }
  bool Ready(const BridgeConsumerHandoff::Ticket &received) noexcept override {
    assert(started && !stopped && mode == "requests" && received.id == ticket.id);
    return owner->With([&](auto &custody, auto now) {
      BridgeConsumerHandoff::Outcome outcome;
      assert(custody.Take(received, now, outcome) == BridgeConsumerHandoff::Consume::Completed);
      assert(outcome == BridgeConsumerHandoff::Outcome::Completed);
      consumed.store(true);
      return true;
    });
  }
  bool Stop() noexcept override {
    assert(started && !stopped);
    stopped = true;
    if (mode == "stuck-stop-lock")
      owner->With([&](auto &, auto) {
        assert(write(audit, "T", 1) == 1);
        while (true) std::this_thread::sleep_for(10ms);
      });
    if (mode == "stuck-stop")
      while (true) std::this_thread::sleep_for(10ms);
    owner->With([&](auto &custody, auto now) {
      assert(custody.closed());
      if (ticket.id && !consumed.load()) {
        BridgeConsumerHandoff::Outcome outcome;
        assert(custody.Take(ticket, now, outcome) == BridgeConsumerHandoff::Consume::Completed);
        assert(outcome == BridgeConsumerHandoff::Outcome::Closed);
      }
      assert(custody.pending() == 0);
    });
    return mode != "fail-stop";
  }
  std::string mode;
  const int audit;
  BridgeHandoffOwner *owner{nullptr};
  BridgeConsumerHandoff::Ticket ticket;
  std::atomic<bool> consumed{false};
  bool started{false}, stopped{false};
};

struct Child {
  pid_t pid;
  int input, output, audit;
};
Child Spawn(const std::string &mode = "normal", std::uint32_t timeout = 1000) {
  int incoming[2], outgoing[2], audit[2];
  assert(pipe(incoming) == 0 && pipe(outgoing) == 0 && pipe(audit) == 0);
  const auto pid = fork();
  assert(pid >= 0);
  if (pid == 0) {
    for (int descriptor = 3; descriptor < 1024; ++descriptor)
      if (descriptor != incoming[0] && descriptor != outgoing[1] && descriptor != audit[1])
        close(descriptor);
    std::signal(SIGPIPE, SIG_IGN);
    Clock clock;
    Driver driver(mode, audit[1]);
    std::atomic<bool> cancel{false};
    std::thread cancellation;
    if (mode == "cancel")
      cancellation = std::thread([&] {
        std::this_thread::sleep_for(100ms);
        cancel.store(true);
      });
    const auto flags_in = fcntl(incoming[0], F_GETFL), flags_out = fcntl(outgoing[1], F_GETFL);
    const auto status = RunBridgeProcess(incoming[0], outgoing[1], timeout, clock, driver, cancel);
    if (cancellation.joinable()) cancellation.join();
    // macOS also exposes kernel write-history bits. Only public status flags
    // are settable/restorable; retain every one, including the access mode.
    constexpr int status_flags = O_ACCMODE | O_APPEND | O_ASYNC | O_SYNC | O_DSYNC | O_NONBLOCK;
    const int restored_in = fcntl(incoming[0], F_GETFL), restored_out = fcntl(outgoing[1], F_GETFL);
    assert(restored_in >= 0 && (restored_in & status_flags) == (flags_in & status_flags));
    assert(restored_out >= 0 && (restored_out & status_flags) == (flags_out & status_flags));
    assert(!driver.started || driver.stopped);
    close(incoming[0]);
    close(outgoing[1]);
    std::_Exit(static_cast<int>(status));
  }
  close(incoming[0]);
  close(outgoing[1]);
  close(audit[1]);
  return {pid, incoming[1], outgoing[0], audit[0]};
}
void Send(Child &child, std::string_view bytes) {
  assert(write(child.input, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
}
std::string Line(Child &child) {
  std::string output;
  const auto deadline = Time::now() + 2s;
  while (Time::now() < deadline) {
    pollfd readable{child.output, POLLIN, 0};
    assert(poll(&readable, 1, 100) >= 0);
    if (!(readable.revents & (POLLIN | POLLHUP))) continue;
    char byte = 0;
    const auto count = read(child.output, &byte, 1);
    if (count == 0) return output;
    assert(count == 1);
    output += byte;
    if (byte == '\n') return output;
  }
  kill(child.pid, SIGKILL);
  int status = 0;
  assert(waitpid(child.pid, &status, 0) == child.pid);
  assert(false && "bounded process output wait expired");
  return {};
}
void Ready(Child &child) {
  Send(child, Control("open"));
  const auto frame = Line(child);
  assert(frame.find("\"type\":\"ready\"") != std::string::npos);
  assert(frame.find("\"generation\":\"" + generation + "\"") != std::string::npos);
  assert(frame.find("\"sdk_revision\":\"250a9e6c50ee2068107f3c4808b680f5f2925415\"") !=
         std::string::npos);
  assert(frame.find("\"model_sha256\":"
                    "\"dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671\"") !=
         std::string::npos);
}
void Join(Child &child, Exit expected, int alternative = -1) {
  const auto deadline = Time::now() + 3s;
  int status = 0;
  while (waitpid(child.pid, &status, WNOHANG) == 0) {
    if (Time::now() >= deadline) {
      kill(child.pid, SIGKILL);
      assert(waitpid(child.pid, &status, 0) == child.pid);
      assert(false && "native process did not retire");
    }
    std::this_thread::sleep_for(1ms);
  }
  assert(WIFEXITED(status) &&
         (WEXITSTATUS(status) == static_cast<int>(expected) || WEXITSTATUS(status) == alternative));
  if (child.input >= 0) close(child.input);
  if (child.output >= 0) close(child.output);
  close(child.audit);
}
void Close(Child &child) {
  Send(child, Control("close"));
  assert(Line(child) == Control("closed"));
  assert(Line(child).empty());
  Join(child, Exit::Closed);
}
} // namespace

int main() {
  std::signal(SIGPIPE, SIG_IGN);
  Clock clock;
  Driver unstarted("normal");
  std::atomic<bool> cancel{false};
  assert(RunBridgeProcess(-1, 1, 1, clock, unstarted, cancel) == Exit::Invalid);
  assert(RunBridgeProcess(0, 0, 1, clock, unstarted, cancel) == Exit::Invalid);
  assert(RunBridgeProcess(0, 1, 0, clock, unstarted, cancel) == Exit::Invalid);
  assert(RunBridgeProcess(0, 1, 5001, clock, unstarted, cancel) == Exit::Invalid);
  assert(!unstarted.started);
  {
    auto child = Spawn("requests");
    const auto open = Control("open");
    Send(child, open.substr(0, 7));
    Send(child, open.substr(7));
    assert(Line(child).find("\"type\":\"ready\"") != std::string::npos);
    assert(Line(child) == "{\"request\":1}\n");
    Send(child, result + probe);
    assert(Line(child) ==
           "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-sample\",\"generation\":\"" +
               generation + "\",\"id\":\"1\",\"native_ms\":\"100\"}\n");
    Close(child);
  }
  for (const auto &bad : {std::string("{}\n"), std::string(512, 'x') + "\n", Control("close"),
                          Control("open").insert(1, "\"v\":1,"), Control("open").substr(0, 30)}) {
    auto child = Spawn();
    Send(child, bad);
    close(child.input);
    child.input = -1;
    assert(Line(child).empty());
    Join(child, Exit::Input);
  }
  {
    auto child = Spawn("normal", 30);
    assert(Line(child).empty());
    Join(child, Exit::Startup);
  }
  {
    auto child = Spawn("slow-start", 150);
    const auto open = Control("open");
    Send(child, open.substr(0, open.size() - 1));
    std::this_thread::sleep_for(120ms);
    Send(child, "\n");
    assert(Line(child).empty());
    // Expiry before SDK entry is a safe refusal; expiry after entry is fatal.
    // Neither phase may reset the budget and publish ready after this delay.
    Join(child, Exit::Cleanup, static_cast<int>(Exit::Startup));
  }
  for (const auto *mode : {"normal", "fail-stop", "stuck-stop", "cancel"}) {
    auto child = Spawn(mode);
    Ready(child);
    if (std::string(mode) != "cancel") Send(child, Control("close"));
    if (std::string(mode) == "normal") assert(Line(child) == Control("closed"));
    assert(Line(child).empty());
    Join(child,
         std::string(mode) == "normal"       ? Exit::Closed
             : std::string(mode) == "cancel" ? Exit::Cancelled
                                             : Exit::Cleanup);
  }
  {
    auto child = Spawn();
    Ready(child);
    close(child.input);
    child.input = -1;
    assert(Line(child).empty());
    Join(child, Exit::Input);
  }
  {
    auto child = Spawn("wait-start");
    Send(child, Control("open") + probe);
    assert(Line(child).empty());
    Join(child, Exit::Input);
  }
  {
    auto child = Spawn("fail-start");
    Send(child, Control("open"));
    assert(Line(child).empty());
    Join(child, Exit::Startup);
  }
  {
    auto child = Spawn("stuck-start", 50);
    Send(child, Control("open"));
    assert(Line(child).empty());
    Join(child, Exit::Cleanup);
  }
  {
    auto child = Spawn("wait-start");
    Send(child, Control("open"));
    close(child.output);
    child.output = -1;
    Join(child, Exit::Output);
  }
  for (const auto *mode : {"stuck-start-lock", "stuck-stop-lock"}) {
    auto child = Spawn(mode, 100);
    if (std::string(mode) == "stuck-start-lock") Send(child, Control("open"));
    else {
      Ready(child);
      Send(child, Control("close"));
    }
    pollfd audit{child.audit, POLLIN, 0};
    assert(poll(&audit, 1, 2000) > 0);
    char mark = 0;
    assert(read(child.audit, &mark, 1) == 1);
    assert(mark == (std::string(mode) == "stuck-start-lock" ? 'S' : 'T'));
    close(child.output);
    child.output = -1;
    Join(child, Exit::Cleanup);
  }
  {
    auto first = Spawn(), second = Spawn();
    Ready(first);
    Ready(second);
    Close(first);
    Send(second, probe);
    assert(Line(second).find("\"native_ms\":\"100\"") != std::string::npos);
    Close(second);
  }
  {
    auto child = Spawn("blocked-output");
    Ready(child);
    // Let a maximum-sized frame start and block. Closing cannot fabricate a
    // terminal receipt by abandoning that frame or wait forever for its reader.
    std::this_thread::sleep_for(30ms);
    Send(child, Control("close"));
    Join(child, Exit::Cleanup);
  }
  std::cout << "bridge-process-cases=22\n";
}
