// SPDX-License-Identifier: Apache-2.0
#include "../../priv/corebluetooth/native/host.hpp"
#include <csignal>
#include <iostream>
#include <fstream>
#include <map>
#include <thread>
#include <sys/wait.h>

using namespace wotex::ble;
using namespace wotex::ble::corebluetooth;
static const std::string service = "0000181a-0000-1000-8000-00805f9b34fb";
static const std::string characteristic = "00002a6e-0000-1000-8000-00805f9b34fb";
static int progress_descriptor = -1;
static void check(bool value) {
  if (!value) std::abort();
}
class Peer final : public Driver {
  SDKSink &sink_;
  std::string behavior_;
  bool closed_ = false;
  std::optional<Result> pending_;
  std::int64_t deliver_ = 0;
  struct Stream {
    Ticket ticket;
    NotificationMode requested, effective;
    unsigned credit;
    std::uint64_t published = 0, acknowledged = 0;
    bool retired = false;
  };
  std::map<std::uint64_t, Stream> streams_;
  std::optional<NotificationResult> control_;
  std::thread producer_;
  std::mutex producer_mutex_;
  bool notifications() const { return behavior_.find("notification") == 0; }
  void values(Stream &stream) {
    const auto limit = stream.credit + (behavior_ == "notification-over-credit" ? 1u : 0u);
    while (stream.published - stream.acknowledged < limit && !stream.retired) {
      const auto sequence = ++stream.published;
      std::vector<std::uint8_t> bytes = behavior_ == "notification-async"
          ? std::vector<std::uint8_t>(512, 255)
          : std::vector<std::uint8_t>{0, 255};
      if (behavior_ == "notification-empty") bytes.clear();
      if (behavior_ == "notification-oversize") bytes.resize(513);
      const auto reported = behavior_ == "notification-gap" ? sequence + 1 : sequence;
      const auto id = behavior_ == "notification-foreign" ? 999 : stream.ticket.request;
      if (!sink_.notification_value(
              {stream.ticket.generation, id, stream.ticket.route, reported, std::move(bytes)}))
        break;
    }
  }
  void produce(Stream &stream) {
    if (producer_.joinable()) producer_.join();
    if (behavior_ == "notification-async") {
      producer_ = std::thread([this, &stream] {
        std::lock_guard<std::mutex> lock(producer_mutex_);
        values(stream);
        if (progress_descriptor >= 0) check(::write(progress_descriptor, "v", 1) == 1);
      });
    } else values(stream);
  }
 public:
  Peer(SDKClock &, SDKSink &sink, std::string behavior)
      : sink_(sink), behavior_(std::move(behavior)) {}
  Code open(const SDKConfig &config, std::int64_t, std::int64_t) override {
    std::vector<Characteristic> routes;
    for (std::uint64_t i = 1; i <= 256; ++i)
      routes.push_back({{config.generation, i, true, true, true},
                        service,
                        characteristic,
                        notifications() && i != 2 && (behavior_ != "notification-modes" || i != 4),
                        notifications() && (i == 2 || i == 3)});
    sink_.opened(Code::ok, config.generation, std::move(routes));
    return Code::ok;
  }
  Code request(Ticket ticket, Mode mode, const std::vector<std::uint8_t> &bytes, std::int64_t now,
               std::int64_t deadline) override {
    if (producer_.joinable()) producer_.join();
    if (closed_) return Code::disconnected;
    if (pending_) return Code::resource_limit;
    bool submitted = false;
    if (mode != Mode::read && behavior_ != "missing-marker") {
      if (!sink_.submitted(ticket, mode)) return Code::resource_limit;
      submitted = true;
    }
    Result result{
        ticket,
        Code::ok,
        Code::ok,
        mode == Mode::read        ? Evidence::value
            : mode == Mode::write ? Evidence::att_response
                                  : Evidence::native_queue_accepted,
        submitted,
        false,
        mode == Mode::read ? std::vector<std::uint8_t>{0, 255} : std::vector<std::uint8_t>{}};
    if (mode != Mode::read && bytes != std::vector<std::uint8_t>({0, 255}))
      return Code::invalid_value_length;
    if (behavior_ == "hold" || behavior_ == "late" || behavior_ == "cleanup-failure" ||
        behavior_ == "notification-point-hold" || behavior_ == "notification-close-success") {
      deliver_ = behavior_ == "late" ? deadline : INT64_MAX;
      pending_ = std::move(result);
    } else sink_.result(std::move(result));
    (void)now;
    return Code::ok;
  }
  void poll(std::int64_t now) override {
    if (pending_ && now >= deliver_) {
      if (producer_.joinable()) producer_.join();
      auto result = std::move(*pending_);
      pending_.reset();
      sink_.result(std::move(result));
    }
  }
  Code subscribe(Ticket ticket, NotificationMode requested, unsigned credit, std::int64_t,
                 std::int64_t) override {
    if (!notifications()) return Code::not_supported;
    if (producer_.joinable()) producer_.join();
    const auto effective = ticket.route == 2 ? NotificationMode::indicate
                                             : NotificationMode::notify;
    auto &stream = streams_.emplace(ticket.request, Stream{ticket, requested, effective, credit})
                       .first->second;
    NotificationResult result{ticket, ticket.request, requested, effective, true, Code::ok, false};
    if (behavior_ == "notification-hold" || behavior_ == "notification-cleanup") {
      control_ = result;
      return Code::ok;
    }
    if (behavior_ == "notification-early") values(stream);
    if (behavior_ == "notification-wrong-state") result.subscription = 999;
    sink_.notification_state(result);
    produce(stream);
    return Code::ok;
  }
  Code unsubscribe(Ticket ticket, std::uint64_t id, std::int64_t, std::int64_t) override {
    if (producer_.joinable()) producer_.join();
    std::lock_guard<std::mutex> lock(producer_mutex_);
    auto found = streams_.find(id);
    if (found == streams_.end() || found->second.retired) return Code::invalid_options;
    auto &stream = found->second;
    stream.retired = true;
    sink_.notification_state(
        {ticket, id, stream.requested, stream.effective, false, Code::ok, true});
    return Code::ok;
  }
  Code acknowledge(std::uint64_t id, std::uint64_t sequence, std::int64_t) override {
    if (producer_.joinable()) producer_.join();
    auto found = streams_.find(id);
    if (found == streams_.end() || sequence < found->second.acknowledged ||
        sequence > found->second.published)
      return Code::invalid_options;
    found->second.acknowledged = sequence;
    if (!found->second.retired) produce(found->second);
    return Code::ok;
  }
  void close(std::int64_t) noexcept override {
    if (closed_) return;
    closed_ = true;
    if (producer_.joinable()) producer_.join();
    if (control_) {
      control_->code = behavior_ == "notification-cleanup" ? Code::cleanup_timeout
                                                           : Code::disconnected;
      control_->cleanup_confirmed = behavior_ != "notification-cleanup";
      sink_.notification_state(*control_);
      control_.reset();
    }
    if (pending_) {
      auto result = std::move(*pending_);
      pending_.reset();
      if (behavior_ != "notification-close-success") {
        result.code = behavior_ == "cleanup-failure" ? Code::cleanup_timeout : Code::disconnected;
        result.cause = Code::disconnected;
        result.evidence = Evidence::none;
      }
      result.bytes.clear();
      result.cleanup_confirmed = behavior_ != "cleanup-failure";
      sink_.result(std::move(result));
    }
    sink_.lost(behavior_ == "cleanup-failure" || behavior_ == "notification-cleanup"
                   ? Code::cleanup_timeout
                   : Code::disconnected);
  }
  bool closed() const override { return closed_; }
};
static DriverFactory factory(const std::string &behavior) {
  return [behavior](SDKClock &clock, SDKSink &sink) {
    return std::make_unique<Peer>(clock, sink, behavior);
  };
}
static Json request(std::string id, std::string op, Json parameters) {
  return {{"version", 1},
          {"id", std::move(id)},
          {"operation", std::move(op)},
          {"parameters", std::move(parameters)},
          {"timeout_ms", 10000}};
}
static void blocked_output() {
  int input[2], output[2];
  check(pipe(input) == 0 && pipe(output) == 0);
  const auto child = fork();
  check(child >= 0);
  if (child == 0) {
    close(input[1]);
    close(output[0]);
    SteadyClock clock;
    _exit(run_host(clock, factory("normal"), input[0], output[1]));
  }
  close(input[0]);
  close(output[1]);
  std::string bytes = request("open", "open",
                              {{"identifier", "01234567-89ab-cdef-0123-456789abcdef"},
                               {"generation", 7},
                               {"permission", "require_authorized"},
                               {"pairing", "system"}})
                          .dump() +
      "\n";
  for (unsigned int i = 1; i <= 100; ++i)
    bytes += request(std::to_string(i), "discover", Json::object()).dump() + "\n";
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count = write(input[1], bytes.data() + offset, bytes.size() - offset);
    if (count < 0 && errno == EINTR) continue;
    check(count > 0);
    offset += count;
  }
  close(input[1]);
  SteadyClock clock;
  int status = 0;
  bool done = false;
  while (clock.sample() < 3000) {
    const auto result = waitpid(child, &status, WNOHANG);
    if (result == child) {
      done = true;
      break;
    }
    check(result == 0 || errno == EINTR);
    ::poll(nullptr, 0, 10);
  }
  if (!done) {
    kill(child, SIGKILL);
    waitpid(child, &status, 0);
  }
  close(output[0]);
  check(done && WIFEXITED(status) && WEXITSTATUS(status) == 2);
  std::cout << "ok blocked-output\n";
}
static void blocked_notifications(bool acknowledge) {
  int input[2], output[2], progress[2];
  check(pipe(input) == 0 && pipe(output) == 0 && pipe(progress) == 0);
  const auto child = fork();
  check(child >= 0);
  if (child == 0) {
    close(input[1]);
    close(output[0]);
    close(progress[0]);
    check(fcntl(output[1], F_SETFL, fcntl(output[1], F_GETFL) | O_NONBLOCK) == 0);
    char fill[4096]{};
    bool full = false;
    for (unsigned count = 0; count < 2048; ++count) {
      const auto written = ::write(output[1], fill, sizeof(fill));
      if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        full = true;
        break;
      }
      check(written > 0 || (written < 0 && errno == EINTR));
    }
    check(full);
    progress_descriptor = progress[1];
    check(::write(progress[1], "f", 1) == 1);
    SteadyClock clock;
    _exit(run_host(clock, factory("notification-async"), input[0], output[1]));
  }
  close(input[0]);
  close(output[1]);
  close(progress[1]);
  const auto signal = [&](char expected) {
    pollfd descriptor{progress[0], POLLIN, 0};
    check(::poll(&descriptor, 1, 2000) > 0);
    char value = 0;
    check(::read(progress[0], &value, 1) == 1 && value == expected);
  };
  const auto send = [&](const Json &frame) {
    const auto bytes = frame.dump() + "\n";
    check(::write(input[1], bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
  };
  signal('f');
  send(request("open", "open",
               {{"identifier", "01234567-89ab-cdef-0123-456789abcdef"},
                {"generation", 7},
                {"permission", "require_authorized"},
                {"pairing", "system"}}));
  send(request("1", "subscribe",
               {{"stream_version", 1},
                {"mode", "auto"},
                {"credit", 64},
                {"address", {{"generation", 7}, {"route", 1}}}}));
  signal('v');
  if (acknowledge)
    send({{"version", 1},
          {"generation", 7},
          {"stream_version", 1},
          {"event", "notification_ack"},
          {"subscription_id", "1"},
          {"sequence", 1}});
  else send(request("close", "close", Json::object()));
  SteadyClock clock;
  int status = 0;
  bool done = false;
  while (clock.sample() < 3000) {
    const auto result = waitpid(child, &status, WNOHANG);
    if (result == child) {
      done = true;
      break;
    }
    check(result == 0 || errno == EINTR);
    ::poll(nullptr, 0, 10);
  }
  if (!done) {
    kill(child, SIGKILL);
    waitpid(child, &status, 0);
  }
  close(input[1]);
  close(output[0]);
  close(progress[0]);
  check(done && WIFEXITED(status) && WEXITSTATUS(status) == (acknowledge ? 2 : 0));
  std::cout << (acknowledge ? "ok unsent-notification-ack\n" : "ok blocked-notifications\n");
}
int main(int argc, char **argv) {
  std::signal(SIGPIPE, SIG_IGN);
  if (argc == 2 && std::string(argv[1]) == "--clock-overflow") {
    class InvalidClock final : public SDKClock {
     public:
      std::int64_t sample() noexcept override { return INT64_MAX; }
    } clock;
    return run_host(clock, factory("normal"));
  }
  if (argc == 2 && std::string(argv[1]) == "--partial-eof") {
    int input[2];
    check(pipe(input) == 0);
    const std::string partial = "{\"private\":\"01234567-89ab-cdef-0123-456789abcdef\"";
    check(write(input[1], partial.data(), partial.size()) == static_cast<ssize_t>(partial.size()));
    close(input[1]);
    SteadyClock clock;
    const auto status = run_host(clock, factory("normal"), input[0]);
    close(input[0]);
    return status;
  }
  if (argc == 2 && std::string(argv[1]) == "--blocked-output") {
    blocked_output();
    return 0;
  }
  if (argc == 2 &&
      (std::string(argv[1]) == "--blocked-notifications" ||
       std::string(argv[1]) == "--unsent-notification-ack")) {
    blocked_notifications(std::string(argv[1]) == "--unsent-notification-ack");
    return 0;
  }
  if (argc > 2) return 64;
  std::string behavior = argc == 2 ? argv[1] : "normal";
  if (argc == 1) {
    std::ifstream(std::string(argv[0]) + ".mode") >> behavior;
    std::ofstream(std::string(argv[0]) + ".pid") << getpid();
  }
  if (behavior != "normal" && behavior != "hold" && behavior != "late" &&
      behavior != "missing-marker" && behavior != "cleanup-failure" &&
      behavior.find("notification") != 0)
    return 64;
  SteadyClock clock;
  return run_host(clock, factory(behavior));
}
