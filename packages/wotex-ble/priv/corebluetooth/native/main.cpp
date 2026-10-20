// SPDX-License-Identifier: Apache-2.0
#include "host.hpp"
#include <csignal>

using namespace wotex::ble::corebluetooth;
class SDKDriver final : public Driver {
  SDK sdk_;
 public:
  SDKDriver(SDKClock &clock, SDKSink &sink) : sdk_(clock, sink) {}
  Code open(const SDKConfig &config, std::int64_t now, std::int64_t deadline) override {
    return sdk_.open(config, now, deadline);
  }
  Code request(Ticket ticket, Mode mode, const std::vector<std::uint8_t> &bytes, std::int64_t now,
               std::int64_t deadline) override {
    return sdk_.request(ticket.request, ticket.route, mode, bytes, now, deadline);
  }
  void poll(std::int64_t now) override { sdk_.poll(now); }
  void close(std::int64_t now) noexcept override try { sdk_.close(now); } catch (...) {
    _exit(70);
  }
  bool closed() const override { return sdk_.closed(); }
};
int main(int argc, char **) {
  if (argc != 1) return 64;
  std::signal(SIGPIPE, SIG_IGN);
  SteadyClock clock;
  return run_host(clock, [](SDKClock &clock, SDKSink &sink) {
    return std::make_unique<SDKDriver>(clock, sink);
  });
}
