// SPDX-License-Identifier: Apache-2.0
#include "../../priv/corebluetooth/native/host.hpp"
#include <csignal>
#include <iostream>
#include <sys/wait.h>

using namespace wotex::ble;
using namespace wotex::ble::corebluetooth;
static const std::string service = "0000181a-0000-1000-8000-00805f9b34fb";
static const std::string characteristic = "00002a6e-0000-1000-8000-00805f9b34fb";
static void check(bool value) {
  if (!value) std::abort();
}
class Peer final : public Driver {
  SDKSink &sink_;
  std::string behavior_;
  bool closed_ = false;
  std::optional<Result> pending_;
  std::int64_t deliver_ = 0;
 public:
  Peer(SDKClock &, SDKSink &sink, std::string behavior)
      : sink_(sink), behavior_(std::move(behavior)) {}
  Code open(const SDKConfig &config, std::int64_t, std::int64_t) override {
    std::vector<Characteristic> routes;
    for (std::uint64_t i = 1; i <= 256; ++i)
      routes.push_back(
          {{config.generation, i, true, true, true}, service, characteristic, false, false});
    sink_.opened(Code::ok, config.generation, std::move(routes));
    return Code::ok;
  }
  Code request(Ticket ticket, Mode mode, const std::vector<std::uint8_t> &bytes, std::int64_t now,
               std::int64_t deadline) override {
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
    if (behavior_ == "hold" || behavior_ == "late" || behavior_ == "cleanup-failure") {
      deliver_ = behavior_ == "late" ? deadline : INT64_MAX;
      pending_ = std::move(result);
    } else sink_.result(std::move(result));
    (void)now;
    return Code::ok;
  }
  void poll(std::int64_t now) override {
    if (pending_ && now >= deliver_) {
      auto result = std::move(*pending_);
      pending_.reset();
      sink_.result(std::move(result));
    }
  }
  void close(std::int64_t) noexcept override {
    if (closed_) return;
    closed_ = true;
    if (pending_) {
      auto result = std::move(*pending_);
      pending_.reset();
      result.code = behavior_ == "cleanup-failure" ? Code::cleanup_timeout : Code::disconnected;
      result.cause = Code::disconnected;
      result.evidence = Evidence::none;
      result.bytes.clear();
      result.cleanup_confirmed = behavior_ != "cleanup-failure";
      sink_.result(std::move(result));
    }
    sink_.lost(behavior_ == "cleanup-failure" ? Code::cleanup_timeout : Code::disconnected);
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
int main(int argc, char **argv) {
  std::signal(SIGPIPE, SIG_IGN);
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
  if (argc > 2) return 64;
  const std::string behavior = argc == 2 ? argv[1] : "normal";
  if (behavior != "normal" && behavior != "hold" && behavior != "late" &&
      behavior != "missing-marker" && behavior != "cleanup-failure")
    return 64;
  SteadyClock clock;
  return run_host(clock, factory(behavior));
}
