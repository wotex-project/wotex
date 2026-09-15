#ifndef WOTEX_MATTER_INPUT_HPP
#define WOTEX_MATTER_INPUT_HPP

#include "wotex_matter/protocol.hpp"

#include <array>
#include <cerrno>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

namespace wotex::matter {

// One input owner retains at most a partial frame and one fixed read buffer.
// The same parser is used both between requests and inside cooperative waits.
class BoundedInput final {
 public:
  enum class Result { Line, Waiting, End, Invalid };

  explicit BoundedInput(int fd) : fd_(fd), flags_(fcntl(fd, F_GETFL)) {
    valid_ = flags_ >= 0 && fcntl(fd_, F_SETFL, flags_ | O_NONBLOCK) == 0;
  }
  ~BoundedInput() {
    if (flags_ >= 0) {
      (void) fcntl(fd_, F_SETFL, flags_);
    }
  }
  BoundedInput(const BoundedInput &) = delete;
  BoundedInput &operator=(const BoundedInput &) = delete;

  Result Next(std::string &line, int wait_ms) {
    if (!valid_) {
      return Result::Invalid;
    }
    bool read_once = false;
    for (;;) {
      while (offset_ < size_) {
        const char byte = buffer_[offset_++];
        if (byte == '\n') {
          line = std::move(partial_);
          partial_.clear();
          return Result::Line;
        }
        if (partial_.size() >= kMaximumFrameBytes - 1) {
          valid_ = false;
          return Result::Invalid;
        }
        partial_.push_back(byte);
      }
      if (read_once) {
        return Result::Waiting;
      }
      pollfd descriptor{fd_, POLLIN, 0};
      const int ready = poll(&descriptor, 1, wait_ms);
      if (ready == 0 || (ready < 0 && errno == EINTR)) {
        return Result::Waiting;
      }
      if (ready < 0 || (descriptor.revents & (POLLERR | POLLNVAL))) {
        return Result::Invalid;
      }
      const auto count = read(fd_, buffer_.data(), buffer_.size());
      if (count < 0) {
        return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR
            ? Result::Waiting : Result::Invalid;
      }
      if (count == 0) {
        return partial_.empty() ? Result::End : Result::Invalid;
      }
      offset_ = 0;
      size_ = static_cast<std::size_t>(count);
      read_once = true;
    }
  }

 private:
  int fd_;
  int flags_;
  bool valid_{false};
  std::array<char, 4096> buffer_{};
  std::size_t offset_{0};
  std::size_t size_{0};
  std::string partial_;
};

} // namespace wotex::matter

#endif
