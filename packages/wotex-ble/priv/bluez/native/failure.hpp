// SPDX-License-Identifier: Apache-2.0
// Closed native error codes and bounded BlueZ names. Arbitrary D-Bus diagnostic
// bodies and exception messages never become protocol output.
#pragma once
#include "bus.hpp"
#include "error_value.hpp"

namespace wotex::ble {
class NativeFailure {
  std::string code_, name_;
  NativeFailure(std::string code, std::string name = {}) : code_(std::move(code)), name_(std::move(name)) {}

public:
  static NativeFailure local(std::string_view code) {
    if (native_error_code(code)) return NativeFailure(std::string(code));
    return NativeFailure("transport_error");
  }
  static NativeFailure from(const BusReply &reply) {
    if (!reply.error) return local("invalid_response");
    auto result = local(reply.error);
    if (result.code_ != "remote_error" || !reply.message ||
        dbus_message_get_type(reply.message.get()) != DBUS_MESSAGE_TYPE_ERROR) return result;
    const char *error = dbus_message_get_error_name(reply.message.get());
    if (!error || !native_error_name(error)) return result;
    result.name_ = error;
    const std::pair<const char *, const char *> codes[] = {
      {"org.bluez.Error.NotConnected", "disconnected"}, {"org.bluez.Error.NotPermitted", "not_permitted"},
      {"org.bluez.Error.NotAuthorized", "not_authorized"}, {"org.bluez.Error.NotSupported", "not_supported"},
      {"org.bluez.Error.InProgress", "busy"}, {"org.bluez.Error.InvalidValueLength", "invalid_value_length"},
      {"org.bluez.Error.InvalidOffset", "invalid_offset"}, {"org.bluez.Error.ImproperlyConfigured", "improperly_configured"}
    };
    for (const auto &[name, code] : codes) if (result.name_ == name) { result.code_ = code; break; }
    return result;
  }
  const std::string &code() const { return code_; }
  Json envelope() const {
    Json value = {{"code", code_}};
    if (!name_.empty()) value["name"] = name_;
    return value;
  }
};
} // namespace wotex::ble
