#ifndef WOTEX_THREAD_MANAGEMENT_HPP
#define WOTEX_THREAD_MANAGEMENT_HPP

#include "protocol.hpp"
#include <chrono>
#include <cstddef>
#include <optional>

namespace wotex::thread {
class ManagementOwner final {
 public:
  using Clock = std::chrono::steady_clock;
  enum class Outcome { accepted, rejected, timed_out };
  struct Result {
    Request command;
    Outcome outcome;
    std::optional<unsigned> status;
  };

  bool begin(const Request &command, Clock::time_point deadline) {
    if (busy()) return false;
    callback_pending_ = true;
    active_ = Active{command, deadline};
    result_.reset();
    return true;
  }

  void submission_failed() {
    callback_pending_ = false;
    active_.reset();
    result_.reset();
  }

  void complete(unsigned status) {
    if (!callback_pending_) return;
    callback_pending_ = false;
    if (active_) result_ = status;
  }

  std::optional<Result> take(Clock::time_point now) {
    if (!active_) {
      result_.reset();
      return std::nullopt;
    }
    if (now >= active_->deadline) {
      Result result{active_->command, Outcome::timed_out, std::nullopt};
      active_.reset();
      result_.reset();
      return result;
    }
    if (!result_) return std::nullopt;
    const unsigned status = *result_;
    Result result{active_->command, status == 0 ? Outcome::accepted : Outcome::rejected, status};
    active_.reset();
    result_.reset();
    return result;
  }

  bool busy() const { return callback_pending_ || active_.has_value(); }
  std::size_t active_contexts() const { return callback_pending_ ? 1 : 0; }

 private:
  struct Active {
    Request command;
    Clock::time_point deadline;
  };
  bool callback_pending_ = false;
  std::optional<Active> active_;
  std::optional<unsigned> result_;
};
} // namespace wotex::thread

#endif
