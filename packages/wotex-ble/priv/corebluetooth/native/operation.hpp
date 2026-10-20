// SPDX-License-Identifier: Apache-2.0
// Explicit-clock operation ownership. The selected SDK adapter owns all objects,
// callback serialization and actual retirement; this component performs no I/O.
#pragma once
#include <algorithm>
#include <cstdint>
#include <exception>
#include <limits>
#include <utility>
#include <vector>

namespace wotex::ble::corebluetooth {
enum class Mode { read, write, command };
enum class Code {
  ok,
  invalid_options,
  not_authorized,
  disconnected,
  stale_discovery,
  not_permitted,
  not_supported,
  invalid_value_length,
  timeout,
  clock_regressed,
  invalid_response,
  resource_limit,
  transport_error,
  cleanup_timeout,
  peer_not_found
};
enum class Evidence { none, value, att_response, native_queue_accepted };
enum class Retirement { pending, confirmed, unconfirmed };
enum class Submission { accepted, refused, uncertain };
struct SubmissionResult {
  Submission status;
  Code cause;
  std::int64_t observed;
};

struct Ticket {
  std::uint64_t generation, request, route;
  bool operator==(const Ticket &other) const {
    return generation == other.generation && request == other.request && route == other.route;
  }
};
struct Route {
  std::uint64_t generation, token;
  bool readable, writable, command;
};
struct Result {
  Ticket ticket;
  Code code, cause;
  Evidence evidence;
  bool submitted, cleanup_confirmed;
  std::vector<std::uint8_t> bytes;
};

class Port {
 public:
  virtual ~Port() = default;
  virtual bool authorized() const noexcept = 0;
  virtual bool connected() const noexcept = 0;
  virtual bool current(const Route &) const noexcept = 0;
  virtual std::size_t maximum(Mode) const noexcept = 0;
  virtual bool ready() const noexcept = 0;
  virtual SubmissionResult submit(Ticket, const Route &, Mode, const std::vector<std::uint8_t> &,
                                  std::int64_t now, std::int64_t deadline) noexcept = 0;
  virtual void retire(Ticket) noexcept = 0;
  virtual Retirement retirement(Ticket) const noexcept = 0;
};
class Sink {
 public:
  virtual ~Sink() = default;
  virtual bool submitted(Ticket, Mode) noexcept = 0;
  virtual void result(Result) noexcept = 0;
};

class Operation {
  enum class State { idle, ready, reply, closing, finished };
  State state_ = State::idle;
  Port &port_;
  Sink &sink_;
  Ticket ticket_{};
  Route route_{};
  Mode mode_ = Mode::read;
  std::vector<std::uint8_t> bytes_;
  std::int64_t deadline_ = 0, last_ = 0, cleanup_ = 0;
  Code cause_ = Code::ok;
  bool submitted_ = false;

  void finish(Code code, Evidence evidence = Evidence::none, std::vector<std::uint8_t> bytes = {},
              bool confirmed = false) noexcept {
    state_ = State::finished;
    bytes_.clear();
    sink_.result({ticket_, code, cause_, evidence, submitted_, confirmed, std::move(bytes)});
  }
  void close(Code cause, std::int64_t now) noexcept {
    if (state_ == State::closing || state_ == State::finished) return;
    cause_ = cause;
    state_ = State::closing;
    cleanup_ = now > std::numeric_limits<std::int64_t>::max() - 500
        ? std::numeric_limits<std::int64_t>::max()
        : now + 500;
    port_.retire(ticket_);
    closing(now);
  }
  void closing(std::int64_t now) noexcept {
    last_ = std::max(now, last_);
    const auto retirement = port_.retirement(ticket_);
    if (last_ >= cleanup_ || retirement == Retirement::unconfirmed) finish(Code::cleanup_timeout);
    else if (retirement == Retirement::confirmed) finish(cause_, Evidence::none, {}, true);
  }
  Code premises(std::int64_t now) const noexcept {
    if (now < last_) return Code::clock_regressed;
    if (now >= deadline_) return Code::timeout;
    if (!port_.authorized()) return Code::not_authorized;
    if (!port_.connected()) return Code::disconnected;
    if (!port_.current(route_)) return Code::stale_discovery;
    return Code::ok;
  }
  void dispatch(std::int64_t now) noexcept {
    const auto valid = premises(now);
    if (valid != Code::ok) {
      close(valid, std::max(now, last_));
      return;
    }
    last_ = now;
    if (mode_ != Mode::read) {
      const auto maximum = port_.maximum(mode_);
      if (!maximum) {
        finish(Code::not_supported);
        return;
      }
      if (bytes_.size() > std::min<std::size_t>(512, maximum)) {
        finish(Code::invalid_value_length);
        return;
      }
    }
    if (mode_ == Mode::command && !port_.ready()) return;
    if (mode_ != Mode::read) {
      if (!sink_.submitted(ticket_, mode_)) {
        finish(Code::resource_limit);
        return;
      }
      submitted_ = true;
    }
    state_ = State::reply;
    const auto sent = port_.submit(ticket_, route_, mode_, bytes_, now, deadline_);
    if (sent.observed < last_) {
      close(Code::clock_regressed, last_);
      return;
    }
    last_ = sent.observed;
    if (last_ >= deadline_) {
      close(Code::timeout, last_);
      return;
    }
    if (sent.status != Submission::accepted) {
      close(sent.cause == Code::ok ? Code::transport_error : sent.cause, last_);
      return;
    }
    if (mode_ == Mode::command) finish(Code::ok, Evidence::native_queue_accepted);
  }
 public:
  Operation(Port &port, Sink &sink) : port_(port), sink_(sink) {}
  Operation(const Operation &) = delete;
  Operation &operator=(const Operation &) = delete;
  ~Operation() {
    if (state_ != State::idle && state_ != State::finished) std::terminate();
  }

  bool start(Ticket ticket, Route route, Mode mode, const std::vector<std::uint8_t> &bytes,
             std::int64_t now, std::int64_t deadline) {
    if (state_ != State::idle || !ticket.generation || !ticket.request || !ticket.route ||
        ticket.generation != route.generation || ticket.route != route.token || now < 0 ||
        deadline <= now || deadline - now > 60000 || bytes.size() > 512 ||
        (mode != Mode::read && mode != Mode::write && mode != Mode::command) ||
        (mode == Mode::read && !bytes.empty()))
      return false;
    bytes_ = bytes;
    ticket_ = ticket;
    route_ = route;
    mode_ = mode;
    deadline_ = deadline;
    last_ = now;
    state_ = State::ready;
    if ((mode == Mode::read && !route.readable) || (mode == Mode::write && !route.writable) ||
        (mode == Mode::command && !route.command)) {
      finish(Code::not_permitted);
      return true;
    }
    dispatch(now);
    return true;
  }
  void poll(std::int64_t now) noexcept {
    if (state_ == State::idle || state_ == State::finished) return;
    if (state_ == State::closing) {
      closing(std::max(now, last_));
      return;
    }
    const auto valid = premises(now);
    if (valid != Code::ok) {
      close(valid, std::max(now, last_));
      return;
    }
    last_ = now;
    if (state_ == State::ready) dispatch(now);
  }
  bool ready(Ticket ticket, std::int64_t now) noexcept {
    if (!(ticket == ticket_) || state_ != State::ready || mode_ != Mode::command) return false;
    poll(now);
    return true;
  }
  bool complete(Ticket ticket, Mode mode, Code code, std::vector<std::uint8_t> bytes,
                std::int64_t now) noexcept {
    if (!(ticket == ticket_) || state_ != State::reply) return false;
    const auto valid = premises(now);
    if (valid != Code::ok) {
      close(valid, std::max(now, last_));
      return true;
    }
    last_ = now;
    if (mode != mode_ || bytes.size() > 512 || (mode != Mode::read && !bytes.empty())) {
      close(Code::invalid_response, now);
      return true;
    }
    if (code != Code::ok) {
      close(code, now);
      return true;
    }
    finish(Code::ok, mode_ == Mode::read ? Evidence::value : Evidence::att_response,
           std::move(bytes));
    return true;
  }
  void cancel(std::int64_t now, Code cause = Code::disconnected) noexcept {
    if (state_ != State::idle && state_ != State::finished) close(cause, std::max(now, last_));
  }
  bool finished() const noexcept { return state_ == State::finished; }
  bool active() const noexcept { return state_ != State::idle && state_ != State::finished; }
};
} // namespace wotex::ble::corebluetooth
