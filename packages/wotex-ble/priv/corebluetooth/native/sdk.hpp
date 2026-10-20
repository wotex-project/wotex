// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "operation.hpp"
#include <memory>
#include <string>

namespace wotex::ble::corebluetooth {
enum class Permission { require_authorized, request };
enum class Pairing { unspecified, system };
enum class NotificationMode { automatic, notify, indicate };
struct NotificationResult {
  Ticket ticket;
  std::uint64_t subscription;
  NotificationMode requested, effective;
  bool enabled;
  Code code;
  bool cleanup_confirmed;
};
struct NotificationValue {
  std::uint64_t generation, subscription, route, sequence;
  std::vector<std::uint8_t> bytes;
};
struct SDKConfig {
  std::string identifier;
  std::uint64_t generation = 0;
  Permission permission = Permission::require_authorized;
  Pairing pairing = Pairing::unspecified;
};
struct Characteristic {
  Route route;
  std::string service, characteristic;
  bool notify, indicate;
};
class SDKClock {
 public:
  virtual ~SDKClock() = default;
  virtual std::int64_t sample() noexcept = 0;
};
class SDKSink : public Sink {
 public:
  virtual bool opened(Code, std::uint64_t, std::vector<Characteristic>) noexcept = 0;
  virtual void lost(Code) noexcept = 0;
  // A sink must opt in before notification entry can succeed. Existing point
  // hosts refuse these callbacks, rather than discarding a stream silently.
  virtual bool notification_state(NotificationResult) noexcept { return false; }
  virtual bool notification_value(NotificationValue &&) noexcept { return false; }
};
struct SDKEnvironment;
struct SDKState;
class SDK {
  std::unique_ptr<SDKState> impl_;
 public:
  SDK(SDKClock &, SDKSink &);
  SDK(SDKClock &, SDKSink &, const SDKEnvironment &);
  SDK(const SDK &) = delete;
  SDK &operator=(const SDK &) = delete;
  ~SDK();
  Code open(const SDKConfig &, std::int64_t now, std::int64_t deadline);
  Code request(std::uint64_t request, std::uint64_t route, Mode, const std::vector<std::uint8_t> &,
               std::int64_t now, std::int64_t deadline);
  Code subscribe(std::uint64_t request, std::uint64_t route, NotificationMode, unsigned credit,
                 std::int64_t now, std::int64_t deadline);
  Code unsubscribe(std::uint64_t request, std::uint64_t subscription, std::int64_t now,
                   std::int64_t deadline);
  Code acknowledge(std::uint64_t subscription, std::uint64_t sequence, std::int64_t now);
  void poll(std::int64_t now);
  void close(std::int64_t now);
  bool closed() const;
};
} // namespace wotex::ble::corebluetooth
