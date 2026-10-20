// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "sdk.hpp"
#include "../../bluez/native/bytes.hpp"
#include "../../bluez/native/output.hpp"
#include <atomic>
#include <array>
#include <chrono>
#include <functional>
#include <mutex>
#include <poll.h>
#include <variant>

namespace wotex::ble::corebluetooth {
inline const char *code_name(Code code) {
  switch (code) {
  case Code::ok:
    return "ok";
  case Code::invalid_options:
    return "invalid_options";
  case Code::not_authorized:
    return "not_authorized";
  case Code::disconnected:
    return "disconnected";
  case Code::stale_discovery:
    return "stale_discovery";
  case Code::not_permitted:
    return "not_permitted";
  case Code::not_supported:
    return "not_supported";
  case Code::invalid_value_length:
    return "invalid_value_length";
  case Code::timeout:
    return "timeout";
  case Code::clock_regressed:
    return "clock_regressed";
  case Code::invalid_response:
    return "invalid_response";
  case Code::resource_limit:
    return "resource_limit";
  case Code::transport_error:
    return "transport_error";
  case Code::cleanup_timeout:
    return "cleanup_timeout";
  case Code::peer_not_found:
    return "peer_not_found";
  }
  return "invalid_response";
}
inline bool canonical_uuid(const std::string &value) {
  if (value.size() != 36) return false;
  for (std::size_t i = 0; i < value.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (value[i] != '-') return false;
    } else if (!((value[i] >= '0' && value[i] <= '9') || (value[i] >= 'a' && value[i] <= 'f')))
      return false;
  }
  return true;
}
class SteadyClock final : public SDKClock {
  const std::chrono::steady_clock::time_point start_ = std::chrono::steady_clock::now();
 public:
  std::int64_t sample() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() -
                                                                 start_)
        .count();
  }
};
class Driver {
 public:
  virtual ~Driver() = default;
  virtual Code open(const SDKConfig &, std::int64_t, std::int64_t) = 0;
  virtual Code request(Ticket, Mode, const std::vector<std::uint8_t> &, std::int64_t,
                       std::int64_t) = 0;
  virtual void poll(std::int64_t) = 0;
  virtual void close(std::int64_t) noexcept = 0;
  virtual bool closed() const = 0;
  virtual Code subscribe(Ticket, NotificationMode, unsigned, std::int64_t, std::int64_t) {
    return Code::not_supported;
  }
  virtual Code unsubscribe(Ticket, std::uint64_t, std::int64_t, std::int64_t) {
    return Code::not_supported;
  }
  virtual Code acknowledge(std::uint64_t, std::uint64_t, std::int64_t) {
    return Code::not_supported;
  }
};
using DriverFactory = std::function<std::unique_ptr<Driver>(SDKClock &, SDKSink &)>;

// The SDK serial queue is the sole producer. The Host loop is the sole consumer.
// Release/acquire publication protects each optional until the other side owns it.
class NotificationInbox {
 public:
  struct Opened {
    Code code;
    std::uint64_t generation;
    std::vector<Characteristic> routes;
  };
  struct Submitted {
    Ticket ticket;
    Mode mode;
  };
  using Event = std::variant<NotificationResult, NotificationValue, Opened, Submitted, Result>;
 private:
  static constexpr unsigned capacity = 80;
  std::array<std::optional<Event>, capacity> events_;
  std::atomic<std::uint64_t> head_{0}, tail_{0};
  std::atomic<unsigned> retained_{0};
  bool push(Event event) {
    const auto head = head_.load(std::memory_order_relaxed);
    const auto tail = tail_.load(std::memory_order_acquire);
    if (head == UINT64_MAX || head - tail == capacity) return false;
    events_[head % capacity].emplace(std::move(event));
    head_.store(head + 1, std::memory_order_release);
    return true;
  }
 public:
  bool state(NotificationResult value) { return push(value); }
  bool opened(Opened value) { return push(std::move(value)); }
  bool submitted(Submitted value) { return push(value); }
  bool result(Result value) { return push(std::move(value)); }
  bool value(NotificationValue value) {
    auto retained = retained_.load(std::memory_order_relaxed);
    do {
      if (retained == 64) return false;
    } while (!retained_.compare_exchange_weak(retained, retained + 1, std::memory_order_acq_rel));
    if (push(std::move(value))) return true;
    retained_.fetch_sub(1, std::memory_order_acq_rel);
    return false;
  }
  std::optional<Event> pop() {
    const auto tail = tail_.load(std::memory_order_relaxed);
    if (tail == head_.load(std::memory_order_acquire)) return std::nullopt;
    auto result = std::move(events_[tail % capacity]);
    events_[tail % capacity].reset();
    tail_.store(tail + 1, std::memory_order_release);
    return result;
  }
  bool release(unsigned count) {
    auto retained = retained_.load(std::memory_order_relaxed);
    do {
      if (count > retained) return false;
    } while (
        !retained_.compare_exchange_weak(retained, retained - count, std::memory_order_acq_rel));
    return true;
  }
};

class Host final : public SDKSink {
  struct Stream {
    enum class State { starting, active, stopping, retired };
    struct Record {
      std::uint64_t sequence, output;
    };
    State state = State::starting;
    std::uint64_t id, control, route, published = 0, acknowledged = 0;
    NotificationMode requested, effective;
    unsigned credit;
    std::deque<Record> records;
    Stream(std::uint64_t number, std::uint64_t token, NotificationMode requested_mode,
           NotificationMode effective_mode, unsigned limit)
        : id(number), control(number), route(token), requested(requested_mode),
          effective(effective_mode), credit(limit) {}
  };
  struct Pending {
    std::string id, operation;
    Ticket ticket;
    std::int64_t deadline;
    NativeOutput::ReplySlot slot;
    bool submitted = false;
  };
  SDKClock &clock_;
  DriverFactory factory_;
  std::unique_ptr<Driver> driver_;
  std::mutex mutex_;
  NativeOutput output_;
  Sequence sequence_;
  std::optional<Pending> pending_;
  std::optional<Result> withheld_;
  std::atomic<Code> loss_{Code::ok};
  std::optional<NativeOutput::ReplySlot> close_slot_;
  std::vector<Characteristic> routes_;
  NotificationInbox notifications_;
  std::array<std::optional<Stream>, 256> streams_;
  std::uint64_t report_sequence_ = 0;
  std::atomic<std::uint64_t> submission_request_{0}, submission_route_{0};
  std::atomic<Mode> submission_mode_{Mode::read};
  std::atomic<std::int64_t> submission_started_{0}, submission_deadline_{0};
  std::uint64_t generation_ = 0;
  std::int64_t last_ = 0, closing_deadline_ = 0;
  std::atomic<bool> stop_{false}, fatal_{false}, explicit_close_{false};
  bool stopped_ = false, ready_ = false, clock_failed_ = false;
  std::atomic<bool> cleanup_failed_{false};
  std::atomic<int> exit_{1};

  void fault() noexcept {
    auto expected = Code::ok;
    loss_.compare_exchange_strong(expected, Code::invalid_response);
    fatal_ = true;
    stop_ = true;
    exit_ = 70;
  }
  Json envelope(const std::string &id, bool ok) const {
    return {{"version", 1}, {"generation", generation_}, {"id", id}, {"ok", ok}};
  }
  void reply(const NativeOutput::ReplySlot &slot, const std::string &id, Json value) {
    auto frame = envelope(id, true);
    frame["result"] = std::move(value);
    if (!output_.reply(slot, EncodedFrame::from(frame))) throw InvalidFrame();
  }
  void error(const NativeOutput::ReplySlot &slot, const std::string &id, const char *code,
             const char *cause, bool submitted, bool confirmed) {
    auto frame = envelope(id, false);
    frame["error"] = {{"code", code},
                      {"cause", cause},
                      {"submitted", submitted},
                      {"cleanup_confirmed", confirmed}};
    if (!output_.reply(slot, EncodedFrame::from(frame))) throw InvalidFrame();
  }
  void result_locked(Result value) {
    if (!pending_) throw InvalidFrame();
    if (value.code != Code::ok) {
      error(pending_->slot, pending_->id, code_name(value.code), code_name(value.cause),
            value.submitted, value.cleanup_confirmed);
    } else if (pending_->operation == "open")
      reply(pending_->slot, pending_->id, {{"generation", generation_}});
    else if (value.evidence == Evidence::value && pending_->operation == "read" &&
             value.bytes.size() <= 512) {
      const std::string_view bytes(
          value.bytes.empty() ? "" : reinterpret_cast<const char *>(value.bytes.data()),
          value.bytes.size());
      reply(pending_->slot, pending_->id, AttributeBytes::from_bytes(bytes).envelope());
    } else if (value.evidence == Evidence::att_response && pending_->operation == "write")
      reply(pending_->slot, pending_->id, nullptr);
    else if (value.evidence == Evidence::native_queue_accepted &&
             pending_->operation == "write_command")
      reply(pending_->slot, pending_->id,
            {{"write_mode", "without_response"}, {"evidence", "native_queue_accepted"}});
    else throw InvalidFrame();
    submission_request_.store(0, std::memory_order_release);
    pending_.reset();
  }
  void timeout_locked() {
    if (!pending_ || withheld_) return;
    withheld_ = Result{pending_->ticket,
                       Code::timeout,
                       Code::timeout,
                       Evidence::none,
                       pending_->submitted,
                       false,
                       {}};
    stop_ = true;
  }
  static const char *mode_name(NotificationMode mode) {
    switch (mode) {
    case NotificationMode::automatic:
      return "auto";
    case NotificationMode::notify:
      return "notify";
    case NotificationMode::indicate:
      return "indicate";
    }
    throw InvalidFrame();
  }
  static std::optional<NotificationMode> requested_mode(const Json &value) {
    if (value == "auto") return NotificationMode::automatic;
    if (value == "notify") return NotificationMode::notify;
    if (value == "indicate") return NotificationMode::indicate;
    return std::nullopt;
  }
  static std::uint64_t identifier(const Json &value) {
    if (!value.is_string()) throw InvalidFrame();
    const auto &digits = value.get_ref<const std::string &>();
    if (digits.empty() || digits.size() > 20 || digits.front() == '0') throw InvalidFrame();
    std::uint64_t number = 0;
    for (const char digit : digits) {
      if (digit < '0' || digit > '9' || number > (UINT64_MAX - (digit - '0')) / 10)
        throw InvalidFrame();
      number = number * 10 + digit - '0';
    }
    return number;
  }
  Stream *stream(std::uint64_t id) {
    for (auto &value : streams_)
      if (value && value->id == id) return &*value;
    return nullptr;
  }
  unsigned reserved() const {
    unsigned total = 0;
    for (const auto &value : streams_)
      if (value)
        total += value->state == Stream::State::retired
            ? static_cast<unsigned>(value->records.size())
            : value->credit;
    return total;
  }
  unsigned live_streams() const {
    unsigned total = 0;
    for (const auto &value : streams_)
      if (value && value->state != Stream::State::retired) ++total;
    return total;
  }
  void notification_result_locked(const NotificationResult &value) {
    if (!pending_ || !(pending_->ticket == value.ticket) || !value.ticket.route ||
        value.ticket.route > routes_.size())
      throw InvalidFrame();
    const auto current = *pending_;
    auto &selected = streams_[value.ticket.route - 1];
    if (!selected || selected->id != value.subscription ||
        selected->control != value.ticket.request || selected->requested != value.requested ||
        selected->effective != value.effective ||
        (current.operation != "subscribe" && current.operation != "unsubscribe") ||
        value.enabled != (current.operation == "subscribe"))
      throw InvalidFrame();
    auto &binding = *selected;
    if (value.code != Code::ok && !value.cleanup_confirmed) cleanup_failed_ = true;
    if (value.code == Code::cleanup_timeout) cleanup_failed_ = true;
    const auto now = clock_.sample();
    if (now < last_) {
      withheld_ = Result{current.ticket,
                         Code::clock_regressed,
                         Code::clock_regressed,
                         Evidence::none,
                         false,
                         false,
                         {}};
      stop_ = true;
    } else if (now >= current.deadline) timeout_locked();
    if (withheld_) return;
    if (stop_ || value.code != Code::ok) {
      const auto code = value.code == Code::ok ? Code::disconnected : value.code;
      withheld_ = Result{current.ticket, code, code, Evidence::none, false, false, {}};
      stop_ = true;
      return;
    }
    if (value.enabled) {
      if (binding.state != Stream::State::starting || value.cleanup_confirmed) throw InvalidFrame();
      binding.state = Stream::State::active;
      reply(current.slot, current.id,
            {{"stream_version", 1},
             {"subscription_id", std::to_string(binding.id)},
             {"route", binding.route},
             {"requested_mode", mode_name(binding.requested)},
             {"effective_mode", mode_name(binding.effective)},
             {"credit", binding.credit}});
    } else {
      if (binding.state != Stream::State::stopping || !value.cleanup_confirmed)
        throw InvalidFrame();
      binding.state = Stream::State::retired;
      if (!output_.control(EncodedFrame::from({{"version", 1},
                                               {"generation", generation_},
                                               {"stream_version", 1},
                                               {"event", "notification_retired"},
                                               {"subscription_id", std::to_string(binding.id)},
                                               {"route", binding.route},
                                               {"last_sequence", binding.published}})))
        throw InvalidFrame();
      reply(current.slot, current.id, nullptr);
    }
    pending_.reset();
  }
  void notification_value_locked(const NotificationValue &value) {
    auto *selected = stream(value.subscription);
    if (!selected || value.generation != generation_ || value.route != selected->route ||
        (selected->state != Stream::State::active && selected->state != Stream::State::stopping) ||
        value.bytes.size() > 512 || selected->published == UINT64_MAX ||
        value.sequence != selected->published + 1 || selected->records.size() == selected->credit ||
        report_sequence_ == UINT64_MAX)
      throw InvalidFrame();
    const std::string_view bytes(
        value.bytes.empty() ? "" : reinterpret_cast<const char *>(value.bytes.data()),
        value.bytes.size());
    const auto ordinal = ++report_sequence_;
    const auto frame = EncodedFrame::from(
        {{"version", 1},
         {"generation", generation_},
         {"stream_version", 1},
         {"event", "notification"},
         {"subscription_id", std::to_string(selected->id)},
         {"route", selected->route},
         {"sequence", value.sequence},
         {"value", AttributeBytes::from_bytes(bytes).envelope()}});
    selected->records.push_back({value.sequence, ordinal});
    if (!output_.report(frame, ordinal)) throw InvalidFrame();
    selected->published = value.sequence;
  }
  void drain_notifications(bool closing = false) {
    for (unsigned count = 0; count < 80; ++count) {
      auto event = notifications_.pop();
      if (!event) return;
      if (auto *value = std::get_if<NotificationValue>(&*event)) {
        if (closing || stop_) {
          if (!notifications_.release(1)) fault();
        } else {
          try {
            notification_value_locked(*value);
          } catch (...) {
            notifications_.release(1);
            fault();
          }
        }
      } else {
        try {
          if (auto *value = std::get_if<NotificationResult>(&*event))
            notification_result_locked(*value);
          else if (auto *value = std::get_if<NotificationInbox::Opened>(&*event))
            accept_opened(std::move(*value));
          else if (auto *value = std::get_if<NotificationInbox::Submitted>(&*event))
            accept_submitted(*value);
          else accept_result(std::move(std::get<Result>(*event)));
        } catch (...) {
          fault();
        }
      }
    }
  }
  void acknowledge(const Json &frame, std::int64_t now) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (stop_ || !ready_ ||
        !fields(
            frame,
            {"version", "generation", "stream_version", "event", "subscription_id", "sequence"}) ||
        !integer(frame["version"], 1, 1) ||
        !integer(frame["generation"], generation_, generation_) ||
        !integer(frame["stream_version"], 1, 1) || frame["event"] != "notification_ack" ||
        !integer(frame["sequence"], 0, UINT64_MAX))
      throw InvalidFrame();
    const auto id = identifier(frame["subscription_id"]);
    auto *selected = stream(id);
    const auto sequence = frame["sequence"].get<std::uint64_t>();
    if (!selected || selected->state == Stream::State::starting ||
        sequence < selected->acknowledged || sequence > selected->published)
      throw InvalidFrame();
    if (sequence == selected->acknowledged) return;
    const auto found = std::find_if(
        selected->records.begin(), selected->records.end(),
        [&](const Stream::Record &record) { return record.sequence == sequence; });
    if (found == selected->records.end() || found->output > output_.transmitted_report_sequence())
      throw InvalidFrame();
    unsigned released = 0;
    while (!selected->records.empty() && selected->records.front().sequence <= sequence) {
      selected->records.pop_front();
      ++released;
    }
    selected->acknowledged = sequence;
    if (!notifications_.release(released)) throw InvalidFrame();
    lock.unlock();
    const auto at = clock_.sample();
    if (at < now) lost(Code::clock_regressed);
    else {
      const auto code = driver_->acknowledge(id, sequence, at);
      if (code != Code::ok) lost(code);
    }
  }
  void notification_request(const std::string &id, const std::string &op, const Json &parameters,
                            std::int64_t now, std::int64_t deadline,
                            const NativeOutput::ReplySlot &slot,
                            std::unique_lock<std::mutex> &lock) {
    const auto refuse = [&](Code code) {
      error(slot, id, code_name(code), code_name(code), false, false);
    };
    if (!parameters.contains("stream_version") || !integer(parameters["stream_version"], 1, 1)) {
      refuse(Code::invalid_options);
      return;
    }
    const auto number = identifier(id);
    Stream *selected = nullptr;
    if (op == "subscribe") {
      if (!fields(parameters, {"stream_version", "address", "mode", "credit"}) ||
          !fields(parameters["address"], {"generation", "route"}) ||
          !integer(parameters["address"]["generation"], generation_, generation_) ||
          !integer(parameters["address"]["route"], 1, routes_.size()) ||
          !integer(parameters["credit"], 1, 64)) {
        refuse(Code::invalid_options);
        return;
      }
      const auto requested = requested_mode(parameters["mode"]);
      if (!requested) {
        refuse(Code::invalid_options);
        return;
      }
      const auto route = parameters["address"]["route"].get<std::uint64_t>();
      const auto mode = *requested;
      const auto &characteristic = routes_[route - 1];
      const auto effective = characteristic.notify ? NotificationMode::notify
                                                   : NotificationMode::indicate;
      const auto credit = parameters["credit"].get<unsigned>();
      if (streams_[route - 1]) {
        refuse(Code::not_permitted);
        return;
      }
      if ((!characteristic.notify && !characteristic.indicate) ||
          (mode != NotificationMode::automatic && mode != effective)) {
        refuse(Code::not_supported);
        return;
      }
      if (live_streams() == 16 || credit > 64 - reserved()) {
        refuse(Code::resource_limit);
        return;
      }
      selected = &streams_[route - 1].emplace(number, route, mode, effective, credit);
    } else {
      if (!fields(parameters, {"stream_version", "subscription_id"})) {
        refuse(Code::invalid_options);
        return;
      }
      selected = stream(identifier(parameters["subscription_id"]));
      if (!selected || selected->state != Stream::State::active) {
        refuse(Code::invalid_options);
        return;
      }
      selected->state = Stream::State::stopping;
      selected->control = number;
    }
    const auto ticket = Ticket{generation_, number, selected->route};
    const auto subscription = selected->id;
    const auto mode = selected->requested;
    const auto credit = selected->credit;
    pending_ = Pending{id, op, ticket, deadline, slot};
    lock.unlock();
    const auto at = clock_.sample();
    if (at < now || at >= deadline) {
      lock.lock();
      timeout_locked();
      return;
    }
    const auto code = op == "subscribe" ? driver_->subscribe(ticket, mode, credit, at, deadline)
                                        : driver_->unsubscribe(ticket, subscription, at, deadline);
    if (code != Code::ok) {
      lock.lock();
      if (op == "subscribe") streams_[ticket.route - 1].reset();
      else selected->state = Stream::State::active;
      result_locked({ticket, code, code, Evidence::none, false, false, {}});
    }
  }
  void shutdown() {
    if (!stop_ || stopped_) return;
    stopped_ = true;
    const auto started = std::max(clock_.sample(), last_);
    closing_deadline_ = started > INT64_MAX - 500 ? INT64_MAX : started + 500;
    if (driver_) driver_->close(started);
    const bool closed = !driver_ || driver_->closed();
    driver_.reset();
    const auto finished = clock_.sample();
    clock_failed_ = clock_failed_ || finished < started || loss_.load() == Code::clock_regressed;
    const bool released = closed && finished >= started && finished < closing_deadline_;
    std::lock_guard<std::mutex> lock(mutex_);
    drain_notifications(true);
    if (pending_ && !withheld_ &&
        (!fatal_ || pending_->operation == "subscribe" || pending_->operation == "unsubscribe"))
      withheld_ = Result{pending_->ticket,
                         fatal_ ? Code::invalid_response : Code::disconnected,
                         fatal_ ? Code::invalid_response : Code::disconnected,
                         Evidence::none,
                         pending_->submitted,
                         false,
                         {}};
    const bool confirmed = released && !cleanup_failed_ && !clock_failed_;
    if (withheld_ && pending_) {
      auto value = std::move(*withheld_);
      withheld_.reset();
      value.cleanup_confirmed = confirmed;
      if (!confirmed) value.code = Code::cleanup_timeout;
      result_locked(std::move(value));
    }
    const auto loss = loss_.load();
    if (loss != Code::ok && !explicit_close_) {
      if (!output_.control(EncodedFrame::from({{"version", 1},
                                               {"generation", generation_},
                                               {"event", "connection_lost"},
                                               {"code", code_name(loss)}})))
        fault();
    }
    if (close_slot_) {
      if (confirmed) reply(*close_slot_, "close", nullptr);
      else error(*close_slot_, "close", "cleanup_timeout", "disconnected", false, false);
      close_slot_.reset();
    }
  }
  void receive(const Json &frame, std::int64_t now) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      drain_notifications();
    }
    if (frame.is_object() && frame.contains("event")) {
      acknowledge(frame, now);
      return;
    }
    if (!sequence_.accept(frame)) throw InvalidFrame();
    const auto id = frame.at("id").get<std::string>();
    const auto op = frame.at("operation").get<std::string>();
    const auto &parameters = frame.at("parameters");
    if (op != "open" && op != "discover" && op != "read" && op != "write" &&
        op != "write_command" && op != "health" && op != "close" && op != "subscribe" &&
        op != "unsubscribe")
      throw InvalidFrame();
    std::unique_lock<std::mutex> lock(mutex_);
    auto slot = output_.reserve_reply();
    if (!slot) throw InvalidFrame();
    if (op == "close") {
      close_slot_ = *slot;
      explicit_close_ = true;
      stop_ = true;
      exit_ = 0;
      return;
    }
    if (pending_) {
      error(*slot, id, "busy", "busy", false, false);
      return;
    }
    if (stop_) throw InvalidFrame();
    const auto invalid = [&] {
      error(*slot, id, "invalid_options", "invalid_options", false, false);
    };
    if (op == "open") {
      if (!fields(parameters, {"identifier", "generation", "permission", "pairing"}) ||
          !parameters["identifier"].is_string() ||
          !canonical_uuid(parameters["identifier"].get_ref<const std::string &>()) ||
          !integer(parameters["generation"], 1, UINT64_MAX) ||
          (parameters["permission"] != "require_authorized" &&
           parameters["permission"] != "request") ||
          parameters["pairing"] != "system") {
        invalid();
        stop_ = true;
        return;
      }
      generation_ = parameters["generation"].get<std::uint64_t>();
      SDKConfig config{parameters["identifier"].get<std::string>(), generation_,
                       parameters["permission"] == "request" ? Permission::request
                                                             : Permission::require_authorized,
                       Pairing::system};
      const auto deadline = now + frame["timeout_ms"].get<std::int64_t>();
      pending_ = Pending{id, op, {generation_, 0, 0}, deadline, *slot};
      lock.unlock();
      driver_ = factory_(clock_, *this);
      const auto current = clock_.sample();
      if (current < now || current >= deadline) {
        lock.lock();
        timeout_locked();
        return;
      }
      const auto code = driver_->open(config, current, deadline);
      if (code != Code::ok) {
        lock.lock();
        if (!pending_) throw InvalidFrame();
        withheld_ = Result{pending_->ticket, code, code, Evidence::none, false, false, {}};
        stop_ = true;
      }
      return;
    }
    if (!ready_) {
      error(*slot, id, "disconnected", "disconnected", false, false);
      return;
    }
    if (op == "subscribe" || op == "unsubscribe") {
      notification_request(id, op, parameters, now, now + frame["timeout_ms"].get<std::int64_t>(),
                           *slot, lock);
      return;
    }
    if (op == "discover" || op == "health") {
      if (!parameters.empty()) {
        invalid();
        return;
      }
      if (op == "health") reply(*slot, id, {{"connected", true}, {"services_resolved", true}});
      else {
        Json items = Json::array();
        for (const auto &value : routes_)
          items.push_back({{"route", value.route.token},
                           {"service_uuid", value.service},
                           {"characteristic_uuid", value.characteristic},
                           {"read", value.route.readable},
                           {"write", value.route.writable},
                           {"write_without_response", value.route.command},
                           {"notify", value.notify},
                           {"indicate", value.indicate}});
        reply(*slot, id, {{"characteristics", std::move(items)}});
      }
      return;
    }
    if ((op == "read" && !fields(parameters, {"address"})) ||
        (op != "read" && !fields(parameters, {"address", "value"})) ||
        !fields(parameters["address"], {"generation", "route"}) ||
        !integer(parameters["address"]["generation"], 1, UINT64_MAX) ||
        !integer(parameters["address"]["route"], 1, routes_.size())) {
      invalid();
      return;
    }
    if (parameters["address"]["generation"] != generation_) {
      error(*slot, id, "stale_discovery", "stale_discovery", false, false);
      return;
    }
    const auto token = parameters["address"]["route"].get<std::uint64_t>();
    if (op == "read" && streams_[token - 1]) {
      error(*slot, id, "not_supported", "not_supported", false, false);
      return;
    }
    const auto number = std::stoull(id);
    const auto mode = op == "read" ? Mode::read : op == "write" ? Mode::write : Mode::command;
    std::vector<std::uint8_t> bytes;
    try {
      if (mode != Mode::read) bytes = AttributeBytes::from(parameters["value"]).value();
    } catch (const InvalidValue &) {
      error(*slot, id, "invalid_value", "invalid_value", false, false);
      return;
    }
    const auto deadline = now + frame["timeout_ms"].get<std::int64_t>();
    const Ticket ticket{generation_, number, token};
    pending_ = Pending{id, op, ticket, deadline, *slot};
    submission_route_.store(token, std::memory_order_relaxed);
    submission_mode_.store(mode, std::memory_order_relaxed);
    submission_started_.store(now, std::memory_order_relaxed);
    submission_deadline_.store(deadline, std::memory_order_relaxed);
    submission_request_.store(number, std::memory_order_release);
    lock.unlock();
    const auto current = clock_.sample();
    if (current < now || current >= deadline) {
      lock.lock();
      timeout_locked();
      return;
    }
    const auto code = driver_->request(ticket, mode, bytes, current, deadline);
    if (code != Code::ok) {
      lock.lock();
      drain_notifications();
      accept_result({ticket, code, code, Evidence::none, false, false, {}});
    }
  }
  void accept_opened(NotificationInbox::Opened value) {
    if (!pending_ || pending_->operation != "open" || value.generation != generation_ ||
        value.routes.size() > 256)
      throw InvalidFrame();
    if (withheld_) return;
    if (clock_.sample() >= pending_->deadline) {
      timeout_locked();
      return;
    }
    if (value.code == Code::ok) {
      for (std::size_t i = 0; i < value.routes.size(); ++i)
        if (value.routes[i].route.generation != generation_ ||
            value.routes[i].route.token != i + 1 || !canonical_uuid(value.routes[i].service) ||
            !canonical_uuid(value.routes[i].characteristic))
          throw InvalidFrame();
      routes_ = std::move(value.routes);
      if (stop_) {
        withheld_ = Result{pending_->ticket,
                           Code::disconnected,
                           Code::disconnected,
                           Evidence::none,
                           false,
                           false,
                           {}};
        return;
      }
      ready_ = true;
    } else {
      stop_ = true;
      if (value.code == Code::cleanup_timeout) cleanup_failed_ = true;
      withheld_ = Result{
          pending_->ticket, value.code, value.code, Evidence::none, false, false, {}};
      return;
    }
    result_locked({pending_->ticket, value.code, value.code, Evidence::none, false, false, {}});
  }
  void accept_submitted(NotificationInbox::Submitted value) {
    if (fatal_) return;
    if (!pending_ || !(pending_->ticket == value.ticket) || pending_->submitted ||
        (value.mode == Mode::write
             ? pending_->operation != "write"
             : value.mode != Mode::command || pending_->operation != "write_command"))
      throw InvalidFrame();
    pending_->submitted = true;
    if (withheld_) withheld_->submitted = true;
    if (!output_.control(EncodedFrame::from({{"version", 1},
                                             {"generation", generation_},
                                             {"event", "write_submitted"},
                                             {"id", pending_->id}})))
      throw InvalidFrame();
  }
  void accept_result(Result value) {
    if (fatal_) return;
    if (!pending_ || !(pending_->ticket == value.ticket) || pending_->operation == "subscribe" ||
        pending_->operation == "unsubscribe")
      throw InvalidFrame();
    if (value.code == Code::cleanup_timeout) cleanup_failed_ = true;
    if (withheld_) return;
    const bool write = pending_->operation == "write" || pending_->operation == "write_command";
    if (value.code == Code::ok &&
        (write ? (!pending_->submitted || !value.submitted) : value.submitted))
      throw InvalidFrame();
    value.submitted = value.submitted || pending_->submitted;
    if (clock_.sample() >= pending_->deadline) {
      const bool submitted = value.submitted || pending_->submitted;
      timeout_locked();
      if (!withheld_) throw InvalidFrame();
      withheld_->submitted = submitted;
      return;
    }
    if (stop_) {
      const auto loss = loss_.load();
      const auto cause = loss == Code::ok ? Code::disconnected : loss;
      withheld_ = Result{pending_->ticket,
                         value.code == Code::ok ? cause : value.code,
                         value.code == Code::ok ? cause : value.cause,
                         Evidence::none,
                         value.submitted,
                         false,
                         {}};
      return;
    }
    result_locked(std::move(value));
  }
 public:
  Host(SDKClock &clock, DriverFactory factory) : clock_(clock), factory_(std::move(factory)) {
    if (!output_.control(EncodedFrame::from({{"version", 1},
                                             {"event", "ready"},
                                             {"backend", "corebluetooth-native"},
                                             {"revision", "1"}})))
      throw InvalidFrame();
  }
  ~Host() {
    if (driver_) {
      driver_->close(std::max(last_, clock_.sample()));
      driver_.reset();
    }
  }
  Host(const Host &) = delete;
  Host &operator=(const Host &) = delete;
  bool opened(Code code, std::uint64_t generation,
              std::vector<Characteristic> routes) noexcept override try {
    if (generation != generation_ || routes.size() > 256) throw InvalidFrame();
    if (notifications_.opened({code, generation, std::move(routes)})) return true;
    lost(Code::resource_limit);
    return false;
  } catch (...) {
    fault();
    return false;
  }
  bool submitted(Ticket ticket, Mode mode) noexcept override try {
    if (stop_) return false;
    auto request = submission_request_.load(std::memory_order_acquire);
    if (!request || request != ticket.request || ticket.generation != generation_ ||
        ticket.route != submission_route_.load(std::memory_order_relaxed) || mode == Mode::read ||
        mode != submission_mode_.load(std::memory_order_relaxed))
      throw InvalidFrame();
    const auto now = clock_.sample();
    if (now < submission_started_.load(std::memory_order_relaxed)) {
      lost(Code::clock_regressed);
      return false;
    }
    if (now >= submission_deadline_.load(std::memory_order_relaxed)) {
      lost(Code::timeout);
      return false;
    }
    if (stop_) return false;
    if (!submission_request_.compare_exchange_strong(request, 0, std::memory_order_acq_rel))
      throw InvalidFrame();
    if (notifications_.submitted({ticket, mode})) return true;
    lost(Code::resource_limit);
    return false;
  } catch (...) {
    fault();
    return false;
  }
  void result(Result value) noexcept override try {
    if (value.ticket.generation != generation_ || value.bytes.size() > 512) throw InvalidFrame();
    if (!notifications_.result(std::move(value))) lost(Code::resource_limit);
  } catch (...) {
    fault();
  }
  void lost(Code code) noexcept override {
    if (code == Code::cleanup_timeout) cleanup_failed_ = true;
    auto expected = Code::ok;
    loss_.compare_exchange_strong(expected, code == Code::ok ? Code::invalid_response : code);
    stop_ = true;
  }
  bool notification_state(NotificationResult value) noexcept override try {
    if (notifications_.state(value)) return true;
    lost(Code::resource_limit);
    return false;
  } catch (...) {
    fault();
    return false;
  }
  bool notification_value(NotificationValue &&value) noexcept override try {
    if (value.bytes.size() > 512 || value.generation != generation_ || !value.route ||
        value.route > 256 || !value.sequence) {
      fault();
      return false;
    }
    if (notifications_.value(std::move(value))) return true;
    lost(Code::resource_limit);
    return false;
  } catch (...) {
    fault();
    return false;
  }
  int run(int input, int output) {
    Lines lines;
    for (;;) {
      try {
        const auto now = clock_.sample();
        if (now < last_ || now < 0 || now > INT64_MAX - 60000) {
          clock_failed_ = true;
          lost(Code::clock_regressed);
          exit_ = 70;
        } else last_ = now;
        if (!stop_) {
          if (driver_) driver_->poll(now);
          std::lock_guard<std::mutex> lock(mutex_);
          drain_notifications();
          if (pending_ && now >= pending_->deadline) timeout_locked();
        }
        shutdown();
        bool writing;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          output_.flush(output);
          writing = output_.pending_frames() != 0;
        }
        if (stopped_ && (!writing || clock_failed_ || clock_.sample() >= closing_deadline_))
          return fatal_ ? 70 : exit_.load();
        pollfd descriptors[] = {{input, short(stopped_ ? 0 : POLLIN), 0},
                                {output, short(writing ? POLLOUT : 0), 0}};
        if (::poll(descriptors, 2, 10) < 0) {
          if (errno == EINTR) continue;
          throw InvalidFrame();
        }
        if (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) throw InvalidFrame();
        if (!stopped_ && descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
          char bytes[4096];
          const auto count = ::read(input, bytes, sizeof(bytes));
          if (count == 0) {
            lines.eof();
            stop_ = true;
          } else if (count > 0)
            lines.feed(std::string_view(bytes, count), [&](std::string_view line) {
              const auto at = clock_.sample();
              if (at < last_ || at > INT64_MAX - 60000) throw InvalidFrame();
              last_ = at;
              receive(parse_line(line), at);
            });
          else if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) throw InvalidFrame();
        }
      } catch (const InvalidFrame &) {
        if (!stopped_) {
          stop_ = true;
          exit_ = 2;
        } else return 2;
      } catch (...) {
        if (!stopped_) fault();
        else return 70;
      }
    }
  }
};
class DescriptorFlags {
  int descriptor_, flags_;
 public:
  explicit DescriptorFlags(int descriptor)
      : descriptor_(descriptor), flags_(::fcntl(descriptor, F_GETFL)) {
    if (flags_ < 0 || ::fcntl(descriptor_, F_SETFL, flags_ | O_NONBLOCK) < 0) throw InvalidFrame();
  }
  ~DescriptorFlags() { ::fcntl(descriptor_, F_SETFL, flags_); }
  DescriptorFlags(const DescriptorFlags &) = delete;
  DescriptorFlags &operator=(const DescriptorFlags &) = delete;
};
inline int run_host(SDKClock &clock, DriverFactory factory, int input = STDIN_FILENO,
                    int output = STDOUT_FILENO) noexcept {
  try {
    DescriptorFlags input_flags(input), output_flags(output);
    Host host(clock, std::move(factory));
    return host.run(input, output);
  } catch (...) {
    return 70;
  }
}
} // namespace wotex::ble::corebluetooth
