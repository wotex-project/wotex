// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "host.hpp"

namespace wotex::ble::corebluetooth {
class SDKDriver final : public Driver {
  SDK sdk_;
 public:
  SDKDriver(SDKClock &clock, SDKSink &sink) : sdk_(clock, sink) {}
  SDKDriver(SDKClock &clock, SDKSink &sink, const SDKEnvironment &environment)
      : sdk_(clock, sink, environment) {}
  Code open(const SDKConfig &config, std::int64_t now, std::int64_t deadline) override {
    return sdk_.open(config, now, deadline);
  }
  Code request(Ticket ticket, Mode mode, const std::vector<std::uint8_t> &bytes, std::int64_t now,
               std::int64_t deadline) override {
    return sdk_.request(ticket.request, ticket.route, mode, bytes, now, deadline);
  }
  Code subscribe(Ticket ticket, NotificationMode mode, unsigned credit, std::int64_t now,
                 std::int64_t deadline) override {
    return sdk_.subscribe(ticket.request, ticket.route, mode, credit, now, deadline);
  }
  Code unsubscribe(Ticket ticket, std::uint64_t subscription, std::int64_t now,
                   std::int64_t deadline) override {
    return sdk_.unsubscribe(ticket.request, subscription, now, deadline);
  }
  Code acknowledge(std::uint64_t subscription, std::uint64_t sequence, std::int64_t now) override {
    return sdk_.acknowledge(subscription, sequence, now);
  }
  void poll(std::int64_t now) override { sdk_.poll(now); }
  void close(std::int64_t now) noexcept override try { sdk_.close(now); } catch (...) {
    _exit(70);
  }
  bool closed() const override { return sdk_.closed(); }
};
} // namespace wotex::ble::corebluetooth
