// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "operation.hpp"
#include <memory>
#include <string>

namespace wotex::ble::corebluetooth {
enum class Permission { require_authorized, request };
enum class Pairing { unspecified, system };
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
  void poll(std::int64_t now);
  void close(std::int64_t now);
  bool closed() const;
};
} // namespace wotex::ble::corebluetooth
