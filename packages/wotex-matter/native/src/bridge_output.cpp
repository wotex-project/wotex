#include "wotex_matter/bridge_output.hpp"

#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <fcntl.h>
#include <limits>
#include <new>
#include <poll.h>
#include <unistd.h>

namespace wotex::matter {

BridgeOutputOwner::BridgeOutputOwner(BridgeHandoffOwner &custody, BridgeOutputSink &sink)
    : custody_(custody), sink_(sink) {}

BridgeOutputOwner::~BridgeOutputOwner() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (running_) std::_Exit(kUnjoinedExit);
  for (const auto &slot : slots_)
    if (slot.state != SlotState::Free) std::_Exit(kUnjoinedExit);
}

BridgeOutputOwner::Admission BridgeOutputOwner::Push(Kind kind, std::string_view frame) {
  if (kind != Kind::Request && kind != Kind::Control) return Admission::Malformed;
  const auto bound = kind == Kind::Request ? kMaximumRequestFrameBytes : kMaximumControlFrameBytes;
  if (frame.size() > bound) return Admission::Oversized;
  if (frame.empty() || frame.back() != '\n' ||
      frame.substr(0, frame.size() - 1).find('\n') != std::string_view::npos ||
      frame.find('\0') != std::string_view::npos || frame.find('\r') != std::string_view::npos)
    return Admission::Malformed;
  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) return Admission::Busy;
  if (state_ != State::Open || terminal_ != 0) return Admission::Closed;
  if (next_ == std::numeric_limits<std::uint64_t>::max()) return Admission::Exhausted;
  const std::size_t begin = kind == Kind::Request ? 0 : kRequestCapacity;
  const std::size_t end = kind == Kind::Request ? kRequestCapacity : slots_.size();
  for (std::size_t i = begin; i < end; ++i) {
    auto &slot = slots_[i];
    if (slot.state != SlotState::Free) continue;
    try {
      std::string owned(frame);
      slot.frame.swap(owned);
    } catch (const std::bad_alloc &) {
      return Admission::NoMemory;
    }
    slot.bytes = frame.size();
    slot.identity = ++next_;
    slot.state = SlotState::Queued;
    changed_.notify_one();
    return Admission::Accepted;
  }
  return Admission::Full;
}

BridgeOutputOwner::Admission BridgeOutputOwner::Finish(std::string_view frame) {
  if (frame.size() > kMaximumControlFrameBytes) return Admission::Oversized;
  if (frame.empty() || frame.back() != '\n' ||
      frame.substr(0, frame.size() - 1).find('\n') != std::string_view::npos ||
      frame.find('\0') != std::string_view::npos || frame.find('\r') != std::string_view::npos)
    return Admission::Malformed;
  std::lock_guard<std::mutex> lock(mutex_);
  if (state_ != State::Open || terminal_ != 0) return Admission::Closed;
  if (next_ == std::numeric_limits<std::uint64_t>::max()) return Admission::Exhausted;
  std::string owned;
  try {
    owned.assign(frame);
  } catch (const std::bad_alloc &) {
    return Admission::NoMemory;
  }
  // At most one slot is Writing, leaving at least three control slots.
  for (auto &slot : slots_)
    if (slot.state == SlotState::Queued) slot = {};
  for (std::size_t i = kRequestCapacity; i < slots_.size(); ++i) {
    auto &slot = slots_[i];
    if (slot.state != SlotState::Free) continue;
    slot.frame.swap(owned);
    slot.bytes = frame.size();
    terminal_ = slot.identity = ++next_;
    slot.state = SlotState::Queued;
    changed_.notify_one();
    return Admission::Accepted;
  }
  std::_Exit(kUnjoinedExit);
}

std::optional<std::size_t> BridgeOutputOwner::First(std::size_t begin, std::size_t end) const {
  std::optional<std::size_t> selected;
  for (std::size_t i = begin; i < end; ++i)
    if (slots_[i].state == SlotState::Queued &&
        (!selected || slots_[i].identity < slots_[*selected].identity))
      selected = i;
  return selected;
}

std::optional<BridgeOutputOwner::Pending> BridgeOutputOwner::Take(const std::atomic<bool> &stop) {
  std::unique_lock<std::mutex> lock(mutex_);
  changed_.wait_for(lock, std::chrono::milliseconds(50), [&] {
    return state_ != State::Open || stop.load() || First(0, slots_.size()).has_value();
  });
  if (state_ != State::Open || stop.load()) return std::nullopt;
  auto selected = First(kRequestCapacity, slots_.size());
  if (!selected) selected = First(0, kRequestCapacity);
  if (!selected) return std::nullopt;
  auto &slot = slots_[*selected];
  slot.state = SlotState::Writing;
  return Pending{*selected, slot.identity, std::move(slot.frame)};
}

bool BridgeOutputOwner::Release(Pending &pending) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto &slot = slots_[pending.slot];
  if (slot.state != SlotState::Writing || slot.identity != pending.identity)
    std::_Exit(kUnjoinedExit);
  // Free the writer's bytes before releasing the charged slot.
  std::string{}.swap(pending.frame);
  slot = {};
  return pending.identity == terminal_;
}

BridgeOutputOwner::State BridgeOutputOwner::End(State state) {
  State terminal;
  bool notify = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (state_ == State::Open) {
      state_ = state;
      for (auto &slot : slots_)
        if (slot.state == SlotState::Queued) slot = {};
      notify = true;
    }
    terminal = state_;
    changed_.notify_all();
  }
  // An SDK callback may hold custody while admitting output. Never acquire
  // custody or call the notification port under the output mutex.
  if (notify) {
    custody_.Close();
    sink_.Closed();
  }
  return terminal;
}

void BridgeOutputOwner::Close() { End(State::Ended); }
bool BridgeOutputOwner::Closed() {
  std::lock_guard<std::mutex> lock(mutex_);
  return state_ != State::Open;
}

BridgeOutputOwner::State BridgeOutputOwner::Run(int descriptor, const std::atomic<bool> &stop) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (running_) return State::AlreadyRunning;
    if (state_ != State::Open) return state_;
    running_ = true;
  }
  const int flags = fcntl(descriptor, F_GETFL);
  if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != 0) End(State::Write);
  else {
    while (!Closed()) {
      if (stop.load()) {
        End(State::Cancelled);
        break;
      }
      auto pending = Take(stop);
      if (!pending) {
        if (stop.load()) End(State::Cancelled);
        else {
          // A consumer can disappear after the last frame was sent while its
          // result is still pending. Detect loss even with an empty queue.
          // Request write readiness: macOS does not report a pipe's reader
          // loss when the requested event mask is empty.
          pollfd lifetime{descriptor, POLLOUT, 0};
          const int alive = poll(&lifetime, 1, 0);
          if ((alive < 0 && errno != EINTR) || (lifetime.revents & (POLLERR | POLLHUP | POLLNVAL)))
            End(State::Write);
        }
        continue;
      }
      std::size_t sent = 0;
      while (sent < pending->frame.size() && !Closed()) {
        if (stop.load()) {
          End(State::Cancelled);
          break;
        }
        pollfd writable{descriptor, POLLOUT, 0};
        const int ready = poll(&writable, 1, 50);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0 || (writable.revents & (POLLERR | POLLHUP | POLLNVAL))) {
          End(State::Write);
          break;
        }
        if (ready == 0) continue;
        const auto count = write(descriptor, pending->frame.data() + sent,
                                 pending->frame.size() - sent);
        if (count > 0) sent += static_cast<std::size_t>(count);
        else if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        else {
          End(State::Write);
          break;
        }
      }
      if (Release(*pending)) End(State::Ended);
    }
    if (fcntl(descriptor, F_SETFL, flags) != 0) {
      std::lock_guard<std::mutex> lock(mutex_);
      state_ = State::Write;
    }
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    running_ = false;
    return state_;
  }
}

} // namespace wotex::matter
