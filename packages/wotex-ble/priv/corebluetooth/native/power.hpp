// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "operation.hpp"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <dispatch/dispatch.h>
#include <functional>
#include <exception>
#include <utility>

namespace wotex::ble::corebluetooth {
// Internal C API seam. All calls and callbacks run on the SDK serial queue.
struct PowerAPI {
  std::function<io_connect_t(void *, IONotificationPortRef *, IOServiceInterestCallback,
                             io_object_t *)>
      subscribe;
  std::function<void(IONotificationPortRef, dispatch_queue_t)> dispatch;
  std::function<IOReturn(io_connect_t, intptr_t)> allow;
  std::function<IOReturn(io_object_t *)> unsubscribe;
  std::function<void(IONotificationPortRef)> destroy;
  std::function<IOReturn(io_connect_t)> close;

  static PowerAPI system() {
    return {IORegisterForSystemPower,   IONotificationPortSetDispatchQueue, IOAllowPowerChange,
            IODeregisterForSystemPower, IONotificationPortDestroy,          IOServiceClose};
  }
};

class PowerSink {
 public:
  virtual ~PowerSink() = default;
  virtual void power_lost(Code) noexcept = 0;
};
class SystemPower final {
  PowerAPI api_;
  PowerSink &sink_;
  io_connect_t connection_ = IO_OBJECT_NULL;
  io_object_t notifier_ = IO_OBJECT_NULL;
  IONotificationPortRef port_ = nullptr;
  bool active_ = false, started_ = false, confirmed_ = true;

  static void callback(void *context, io_service_t, natural_t message, void *argument) noexcept {
    static_cast<SystemPower *>(context)->event(message, reinterpret_cast<intptr_t>(argument));
  }
  void event(natural_t message, intptr_t token) noexcept {
    if (!active_) return;
    bool allowed = true;
    if (message == kIOMessageCanSystemSleep || message == kIOMessageSystemWillSleep) {
      try {
        allowed = api_.allow(connection_, token) == kIOReturnSuccess;
      } catch (...) {
        allowed = false;
      }
    }
    if (!allowed) sink_.power_lost(Code::transport_error);
    else if (message == kIOMessageSystemWillSleep || message == kIOMessageSystemWillPowerOn ||
             message == kIOMessageSystemHasPoweredOn)
      sink_.power_lost(Code::disconnected);
  }
 public:
  SystemPower(PowerAPI api, PowerSink &sink) : api_(std::move(api)), sink_(sink) {}
  SystemPower(const SystemPower &) = delete;
  SystemPower &operator=(const SystemPower &) = delete;
  ~SystemPower() {
    if (active_ || port_ || connection_ || notifier_) std::terminate();
  }

  bool start(dispatch_queue_t queue) {
    if (started_ || !queue || !api_.subscribe || !api_.dispatch || !api_.allow ||
        !api_.unsubscribe || !api_.destroy || !api_.close)
      return false;
    started_ = true;
    try {
      connection_ = api_.subscribe(this, &port_, callback, &notifier_);
      if (!connection_ || !port_ || !notifier_) {
        stop();
        return false;
      }
      active_ = true;
      api_.dispatch(port_, queue);
      return active_;
    } catch (...) {
      confirmed_ = false;
      stop();
      return false;
    }
  }
  bool stop() noexcept {
    // Fence first. Queued callbacks can still name this object until SDK queue
    // retirement, but can no longer call the SDK state. Never retry cleanup.
    active_ = false;
    const auto notifier = std::exchange(notifier_, IO_OBJECT_NULL);
    const auto port = std::exchange(port_, nullptr);
    const auto connection = std::exchange(connection_, IO_OBJECT_NULL);
    if (notifier) {
      try {
        auto selected = notifier;
        if (api_.unsubscribe(&selected) != kIOReturnSuccess) confirmed_ = false;
      } catch (...) {
        confirmed_ = false;
      }
    }
    if (port) {
      try {
        api_.destroy(port);
      } catch (...) {
        confirmed_ = false;
      }
    }
    if (connection) {
      try {
        if (api_.close(connection) != kIOReturnSuccess) confirmed_ = false;
      } catch (...) {
        confirmed_ = false;
      }
    }
    return confirmed_;
  }
};
} // namespace wotex::ble::corebluetooth
