// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "sdk.hpp"
#include "../../bluez/native/bytes.hpp"
#include "../../bluez/native/output.hpp"
#include <atomic>
#include <chrono>
#include <functional>
#include <mutex>
#include <poll.h>

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
};
using DriverFactory = std::function<std::unique_ptr<Driver>(SDKClock &, SDKSink &)>;

class Host final : public SDKSink {
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
  std::optional<Code> withheld_loss_;
  std::optional<NativeOutput::ReplySlot> close_slot_;
  std::vector<Characteristic> routes_;
  std::uint64_t generation_ = 0;
  std::int64_t last_ = 0, closing_deadline_ = 0;
  std::atomic<bool> stop_{false}, fatal_{false}, explicit_close_{false};
  bool stopped_ = false, ready_ = false, cleanup_failed_ = false;
  std::atomic<int> exit_{1};

  void fault() noexcept {
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
  void shutdown() {
    if (!stop_ || stopped_) return;
    stopped_ = true;
    const auto started = std::max(clock_.sample(), last_);
    closing_deadline_ = started + 500;
    if (driver_) driver_->close(started);
    const bool closed = !driver_ || driver_->closed();
    driver_.reset();
    const auto finished = clock_.sample();
    const bool released = closed && finished >= started && finished < closing_deadline_;
    std::lock_guard<std::mutex> lock(mutex_);
    const bool confirmed = released && !cleanup_failed_;
    if (withheld_ && pending_) {
      auto value = std::move(*withheld_);
      withheld_.reset();
      value.cleanup_confirmed = confirmed;
      if (!confirmed) value.code = Code::cleanup_timeout;
      result_locked(std::move(value));
    }
    if (withheld_loss_ && !explicit_close_) {
      if (!output_.control(EncodedFrame::from({{"version", 1},
                                               {"generation", generation_},
                                               {"event", "connection_lost"},
                                               {"code", code_name(*withheld_loss_)}})))
        fault();
      withheld_loss_.reset();
    }
    if (close_slot_) {
      if (confirmed) reply(*close_slot_, "close", nullptr);
      else error(*close_slot_, "close", "cleanup_timeout", "disconnected", false, false);
      close_slot_.reset();
    }
  }
  void receive(const Json &frame, std::int64_t now) {
    if (!sequence_.accept(frame)) throw InvalidFrame();
    const auto id = frame.at("id").get<std::string>();
    const auto op = frame.at("operation").get<std::string>();
    const auto &parameters = frame.at("parameters");
    if (op != "open" && op != "discover" && op != "read" && op != "write" &&
        op != "write_command" && op != "health" && op != "close")
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
    lock.unlock();
    const auto current = clock_.sample();
    if (current < now || current >= deadline) {
      lock.lock();
      timeout_locked();
      return;
    }
    const auto code = driver_->request(ticket, mode, bytes, current, deadline);
    if (code != Code::ok) result({ticket, code, code, Evidence::none, false, false, {}});
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
    if (driver_) driver_->close(std::max(last_, clock_.sample()));
  }
  Host(const Host &) = delete;
  Host &operator=(const Host &) = delete;
  bool opened(Code code, std::uint64_t generation,
              std::vector<Characteristic> routes) noexcept override try {
    std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
    if (!lock || !pending_ || pending_->operation != "open" || generation != generation_ ||
        routes.size() > 256) {
      fault();
      return false;
    }
    if (withheld_) return true;
    if (clock_.sample() >= pending_->deadline) {
      timeout_locked();
      return true;
    }
    if (code == Code::ok) {
      for (std::size_t i = 0; i < routes.size(); ++i)
        if (routes[i].route.generation != generation_ || routes[i].route.token != i + 1 ||
            !canonical_uuid(routes[i].service) || !canonical_uuid(routes[i].characteristic))
          throw InvalidFrame();
      routes_ = std::move(routes);
      ready_ = true;
    } else {
      stop_ = true;
      cleanup_failed_ = code == Code::cleanup_timeout;
    }
    result_locked({pending_->ticket,
                   code,
                   code,
                   Evidence::none,
                   false,
                   code != Code::ok && !cleanup_failed_,
                   {}});
    return true;
  } catch (...) {
    fault();
    return false;
  }
  bool submitted(Ticket ticket, Mode mode) noexcept override try {
    std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
    if (!lock || !pending_ || !(pending_->ticket == ticket) || mode == Mode::read ||
        pending_->submitted) {
      fault();
      return false;
    }
    if (clock_.sample() >= pending_->deadline) {
      timeout_locked();
      return false;
    }
    if (!output_.control(EncodedFrame::from({{"version", 1},
                                             {"generation", generation_},
                                             {"event", "write_submitted"},
                                             {"id", pending_->id}}))) {
      fault();
      return false;
    }
    pending_->submitted = true;
    return true;
  } catch (...) {
    fault();
    return false;
  }
  void result(Result value) noexcept override try {
    std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
    if (!lock || !pending_ || !(pending_->ticket == value.ticket)) {
      fault();
      return;
    }
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
    result_locked(std::move(value));
  } catch (...) {
    fault();
  }
  void lost(Code code) noexcept override try {
    std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
    if (!lock) {
      fault();
      return;
    }
    if (code == Code::cleanup_timeout) cleanup_failed_ = true;
    stop_ = true;
    if (withheld_) {
      withheld_loss_ = code;
      return;
    }
    if (!explicit_close_ &&
        !output_.control(EncodedFrame::from({{"version", 1},
                                             {"generation", generation_},
                                             {"event", "connection_lost"},
                                             {"code", code_name(code)}})))
      fault();
  } catch (...) {
    fault();
  }
  int run(int input, int output) {
    Lines lines;
    for (;;) {
      try {
        const auto now = clock_.sample();
        if (now < last_ || now < 0 || now > INT64_MAX - 60000) {
          stop_ = true;
          exit_ = 70;
        } else last_ = now;
        if (!stop_) {
          if (driver_) driver_->poll(now);
          std::lock_guard<std::mutex> lock(mutex_);
          if (pending_ && now >= pending_->deadline) timeout_locked();
        }
        shutdown();
        bool writing;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          output_.flush(output);
          writing = output_.pending_frames() != 0;
        }
        if (stopped_ && (!writing || clock_.sample() >= closing_deadline_))
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
