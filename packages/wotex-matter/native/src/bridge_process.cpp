#include "wotex_matter/bridge_process.hpp"
#include "wotex_matter/bridge_control.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <fcntl.h>
#include <poll.h>
#include <thread>
#include <unistd.h>

namespace wotex::matter {
namespace {
using Time = std::chrono::steady_clock;
using Exit = BridgeProcessExit;
using Generation = BridgeConsumerHandoff::Generation;

Exit Open(int descriptor, Time::time_point deadline, const std::atomic<bool> &cancel,
          Generation &generation) {
  const int flags = fcntl(descriptor, F_GETFL);
  if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != 0) return Exit::Input;
  std::array<char, kMaximumBridgeResultFrameBytes> bytes{};
  std::size_t used = 0;
  Exit result = Exit::Input;
  while (true) {
    if (cancel.load()) {
      result = Exit::Cancelled;
      break;
    }
    const auto now = Time::now();
    if (now >= deadline) {
      result = Exit::Startup;
      break;
    }
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
    pollfd incoming{descriptor, POLLIN, 0};
    const int ready = poll(&incoming, 1,
                           static_cast<int>(std::clamp<long long>(remaining.count(), 1, 50)));
    if (ready < 0 && errno == EINTR) continue;
    if (ready < 0 || (incoming.revents & (POLLERR | POLLNVAL))) break;
    if (ready == 0) continue;
    char byte = 0;
    const auto count = read(descriptor, &byte, 1);
    if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
    if (count != 1) break;
    if (cancel.load()) {
      result = Exit::Cancelled;
      break;
    }
    if (Time::now() >= deadline) {
      result = Exit::Startup;
      break;
    }
    if (byte == '\n') {
      if (DecodeBridgeOpenFrame(std::string_view(bytes.data(), used), generation) ==
          BridgeResultDecode::Decoded)
        result = Exit::Closed;
      break;
    }
    if (used == bytes.size() - 1) break;
    bytes[used++] = byte;
  }
  if (fcntl(descriptor, F_SETFL, flags) != 0) return Exit::Input;
  return result;
}

class Session final : public BridgeResultSink, public BridgeOutputSink {
 public:
  Session(BridgeProcessDriver &driver, Generation generation, Time::time_point deadline)
      : driver(driver), generation(generation), deadline(deadline) {}
  bool Ready(const BridgeConsumerHandoff::Ticket &ticket) noexcept override {
    return driver.Ready(ticket);
  }
  bool ClockSample(const BridgeConsumerHandoff::Ticket &probe,
                   std::uint64_t now) noexcept override {
    std::string frame;
    return EncodeBridgeClockSample(generation, probe.id, now, frame) ==
        BridgeClockEncode::Encoded &&
        output->Push(BridgeOutputOwner::Kind::Control, frame) ==
        BridgeOutputOwner::Admission::Accepted;
  }
  void Closed() noexcept override {
    {
      std::lock_guard<std::mutex> lock(mutex);
      cancel.store(true);
    }
    changed.notify_all();
  }
  void Fail(Exit reason, bool startup_only = false) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (startup_only && !starting) return;
      int empty = 0;
      failure.compare_exchange_strong(empty, static_cast<int>(reason));
      cancel.store(true);
      reader_stop.store(true);
      writer_stop.store(true);
    }
    // The watchdog must never wait for a custody/output lock held by stuck
    // SDK work. Publish cancellation only; the coordinator retires the pipes.
    // This also leaves raw startup custody exclusive until Start returns.
    changed.notify_all();
  }
  void Phase(bool cleanup) {
    std::lock_guard<std::mutex> lock(mutex);
    starting = false;
    cleaning = cleanup;
    if (cleanup) deadline = Time::now() + std::chrono::seconds(1);
    changed.notify_all();
  }
  void Watch(int input_descriptor, int output_descriptor, const std::atomic<bool> &external) {
    std::unique_lock<std::mutex> lock(mutex);
    while (!watcher_stop) {
      const bool startup = starting;
      const bool expired = (starting || cleaning) && Time::now() >= deadline;
      if (expired) std::_Exit(static_cast<int>(Exit::Cleanup));
      lock.unlock();
      if (external.load()) Fail(Exit::Cancelled);
      pollfd outgoing{output_descriptor, POLLOUT, 0};
      const int written = poll(&outgoing, 1, 0);
      if ((written < 0 && errno != EINTR) || (outgoing.revents & (POLLERR | POLLHUP | POLLNVAL)))
        Fail(Exit::Output);
      if (startup && !input_done.load()) {
        pollfd incoming{input_descriptor, POLLIN, 0};
        const int read = poll(&incoming, 1, 0);
        if ((read < 0 && errno != EINTR) ||
            (incoming.revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL)))
          Fail(Exit::Input, true);
      }
      lock.lock();
      changed.wait_for(lock, std::chrono::milliseconds(10));
    }
  }
  BridgeProcessDriver &driver;
  const Generation generation;
  BridgeOutputOwner *output{nullptr};
  std::atomic<bool> cancel{false}, reader_stop{false}, writer_stop{false}, input_done{false};
  std::atomic<int> failure{0};
  BridgeResultInput::State input_state{BridgeResultInput::State::Open};
  BridgeOutputOwner::State output_state{BridgeOutputOwner::State::Open};
  std::mutex mutex;
  std::condition_variable changed;
  bool starting{true}, cleaning{false}, watcher_stop{false};
  Time::time_point deadline;
};
} // namespace

BridgeProcessExit RunBridgeProcess(int input, int output, std::uint32_t startup_ms,
                                   BridgeHandoffClock &clock, BridgeProcessDriver &driver,
                                   const std::atomic<bool> &cancel) noexcept {
  if (input < 0 || output < 0 || input == output || startup_ms < 1 || startup_ms > 5000)
    return Exit::Invalid;
  const auto deadline = Time::now() + std::chrono::milliseconds(startup_ms);
  Generation generation{};
  const auto opened = Open(input, deadline, cancel, generation);
  if (opened != Exit::Closed) return opened;
  BridgeConsumerHandoff custody(generation);
  BridgeHandoffOwner owner(custody, clock);
  Session session(driver, generation, deadline);
  BridgeOutputOwner outgoing(owner, session);
  session.output = &outgoing;
  BridgeResultInput incoming(owner, generation, session);
  std::thread reader, writer, watcher;
  bool entered = false, started = false;
  try {
    watcher = std::thread([&] { session.Watch(input, output, cancel); });
    if (!session.cancel.load() && !cancel.load() && Time::now() < deadline) {
      entered = true;
      started = driver.Start(custody, owner, outgoing, session.cancel);
    }
    // No consumer result/probe can belong to a not-yet-published generation.
    // Observe queued early bytes even when Start completed before the watcher
    // got its first turn; leave them unconsumed and retire startup instead.
    pollfd early{input, POLLIN, 0};
    const int available = poll(&early, 1, 0);
    if ((available < 0 && errno != EINTR) ||
        (early.revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL)))
      session.Fail(Exit::Input, true);
    std::string ready;
    if (!started || session.cancel.load() || cancel.load() || Time::now() >= deadline ||
        EncodeBridgeControlReply(BridgeControlReply::Ready, generation, ready) !=
            BridgeControlEncode::Encoded ||
        outgoing.Push(BridgeOutputOwner::Kind::Control, ready) !=
            BridgeOutputOwner::Admission::Accepted ||
        Time::now() >= deadline || session.cancel.load() || cancel.load()) {
      session.Fail(Exit::Startup);
    } else {
      session.Phase(false);
      reader = std::thread([&] {
        session.input_state = incoming.Run(input, session.reader_stop);
        if (session.input_state != BridgeResultInput::State::Requested) {
          int empty = 0;
          session.failure.compare_exchange_strong(empty, static_cast<int>(Exit::Input));
        }
        session.input_done.store(true);
        session.Closed();
      });
      writer = std::thread([&] {
        session.output_state = outgoing.Run(output, session.writer_stop);
        if (session.output_state == BridgeOutputOwner::State::Write) session.Fail(Exit::Output);
        session.Closed();
      });
      std::unique_lock<std::mutex> lock(session.mutex);
      session.changed.wait(lock, [&] { return session.cancel.load(); });
    }
  } catch (...) {
    session.Fail(Exit::Startup);
  }
  session.Phase(true);
  session.reader_stop.store(true);
  owner.Close();
  if (reader.joinable()) reader.join();
  const bool cleaned = !entered || driver.Stop();
  bool terminal = false;
  if (!cleaned) std::_Exit(static_cast<int>(Exit::Cleanup));
  if (started && session.failure.load() == 0 && !cancel.load() &&
      session.input_state == BridgeResultInput::State::Requested) {
    std::string closed;
    terminal = EncodeBridgeControlReply(BridgeControlReply::Closed, generation, closed) ==
            BridgeControlEncode::Encoded &&
        outgoing.Finish(closed) == BridgeOutputOwner::Admission::Accepted;
    if (!terminal) session.Fail(Exit::Output);
  }
  if (!terminal) {
    session.writer_stop.store(true);
    outgoing.Close();
  }
  if (writer.joinable()) writer.join();
  {
    std::lock_guard<std::mutex> lock(session.mutex);
    session.watcher_stop = true;
    session.cleaning = false;
    session.changed.notify_all();
  }
  if (watcher.joinable()) watcher.join();
  const int failed = session.failure.load();
  if (failed) return static_cast<Exit>(failed);
  return terminal && session.output_state == BridgeOutputOwner::State::Ended ? Exit::Closed
                                                                             : Exit::Startup;
}
} // namespace wotex::matter
