#ifndef WOTEX_THREAD_OUTPUT_HPP
#define WOTEX_THREAD_OUTPUT_HPP

#include <unistd.h>
#include <array>
#include <cerrno>
#include <cstddef>
#include <deque>
#include <string>
#include <stdexcept>
#include <utility>

namespace wotex::thread {
class ChannelError final : public std::runtime_error {
 public:
  ChannelError() : std::runtime_error("channel_exhausted") {}
};

// Host-to-owner frames keep one stdout order but charge separate reservations:
// successful operation replies, control/terminal frames and credited reports.
// Exhausting any reservation terminates the owned generation instead of
// waiting for the owner or evicting admitted work.
enum class Lane : std::size_t { reply = 0, control = 1, report = 2 };

struct LaneLimit {
  std::size_t frames;
  std::size_t frame_bytes;
  std::size_t bytes;
};

constexpr std::array<LaneLimit, 3> kLaneLimits{{
    {64, 131072, 8388608},
    {256, 4096, 1048576},
    {64, 131072, 1048576},
}};

class Output final {
 public:
  struct Usage {
    std::size_t frames = 0;
    std::size_t bytes = 0;
  };
  enum class Flush { idle, pending, failed };

  // Accepts one frame without its newline when the lane reservation admits it.
  bool push(Lane lane, std::string frame) {
    const auto index = static_cast<std::size_t>(lane);
    const LaneLimit &limit = kLaneLimits[index];
    Usage &usage = usage_[index];
    const std::size_t bytes = frame.size() + 1;
    if (frame.empty() || frame.find('\n') != std::string::npos || bytes > limit.frame_bytes ||
        usage.frames == limit.frames || bytes > limit.bytes - usage.bytes) return false;
    frame.push_back('\n');
    frames_.push_back({lane, std::move(frame)});
    ++usage.frames;
    usage.bytes += bytes;
    if (usage.frames > maximum_[index].frames) maximum_[index].frames = usage.frames;
    if (usage.bytes > maximum_[index].bytes) maximum_[index].bytes = usage.bytes;
    return true;
  }

  // Writes whole or partial frames to a nonblocking descriptor; a frame keeps
  // its reservation until its final byte is written.
  Flush flush(int descriptor) {
    while (!frames_.empty()) {
      const std::string &bytes = frames_.front().bytes;
      const ssize_t written = ::write(descriptor, bytes.data() + offset_, bytes.size() - offset_);
      if (written < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? Flush::pending : Flush::failed;
      offset_ += static_cast<std::size_t>(written);
      if (offset_ < bytes.size()) return Flush::pending;
      Usage &usage = usage_[static_cast<std::size_t>(frames_.front().lane)];
      --usage.frames;
      usage.bytes -= bytes.size();
      frames_.pop_front();
      offset_ = 0;
    }
    return Flush::idle;
  }

  bool empty() const { return frames_.empty(); }
  Usage usage(Lane lane) const { return usage_[static_cast<std::size_t>(lane)]; }
  Usage maximum(Lane lane) const { return maximum_[static_cast<std::size_t>(lane)]; }

 private:
  struct Frame {
    Lane lane;
    std::string bytes;
  };
  std::deque<Frame> frames_;
  std::size_t offset_ = 0;
  std::array<Usage, 3> usage_{};
  std::array<Usage, 3> maximum_{};
};
}  // namespace wotex::thread
#endif
