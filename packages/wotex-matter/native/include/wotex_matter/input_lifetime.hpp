#ifndef WOTEX_MATTER_INPUT_LIFETIME_HPP
#define WOTEX_MATTER_INPUT_LIFETIME_HPP

#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <mutex>
#include <poll.h>
#include <thread>

namespace wotex::matter {

// Observes the non-owned stdin descriptor without consuming command bytes.
// The monitor remains alive through controller destruction. EOF starts a
// 750 ms cooperative cleanup grace, as does an explicit channel failure.
// A blocked SDK or output writer then loses its entire process. This fallback cannot claim callback destruction or leak
// finalization. Normal shutdown joins the one owned monitoring thread.
class InputLifetime final {
 public:
  explicit InputLifetime(int input)
      : input_(input), worker_([this] { Watch(); }) {}

  ~InputLifetime() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
    }
    condition_.notify_one();
    worker_.join();
  }

  // May be called from SDK or writer threads. The first failure starts one
  // bounded grace; repeated failures cannot extend it or run SDK cleanup.
  void Fail() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      failed_ = true;
    }
    condition_.notify_one();
  }

  InputLifetime(const InputLifetime &) = delete;
  InputLifetime &operator=(const InputLifetime &) = delete;

 private:
  void Watch() {
    // HUP/ERR/NVAL are reported even with events=0. Ignoring readable data
    // avoids consuming it or busy-spinning while ProcessLine owns the input.
    pollfd descriptor{input_, 0, 0};
    while (true) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopping_) {
          return;
        }
        if (failed_) {
          break;
        }
      }
      const int result = poll(&descriptor, 1, 25);
      if ((result < 0 && errno == EINTR) || result == 0 ||
          (result > 0 &&
           (descriptor.revents & (POLLHUP | POLLERR | POLLNVAL)) == 0)) {
        continue;
      }
      break;
    }
    std::unique_lock<std::mutex> lock(mutex_);
    if (!condition_.wait_for(lock, std::chrono::milliseconds(750),
                              [this] { return stopping_; })) {
      std::_Exit(EXIT_FAILURE);
    }
  }

  const int input_;
  std::mutex mutex_;
  std::condition_variable condition_;
  bool stopping_{false};
  bool failed_{false};
  std::thread worker_;
};

} // namespace wotex::matter

#endif
