// SPDX-License-Identifier: Apache-2.0
// Closed native error codes and bounded BlueZ names. Arbitrary D-Bus diagnostic
// bodies and exception messages never become protocol output.
#pragma once
#include "bus.hpp"
#include "frame.hpp"

namespace wotex::ble {
class NativeFailure {
  std::string code_, name_;
  NativeFailure(std::string code, std::string name = {}) : code_(std::move(code)), name_(std::move(name)) {}
  static bool name(const char *value) {
    if (!value || strnlen(value, 129) > 128) return false;
    const std::string_view text(value);
    constexpr std::string_view prefix = "org.bluez.Error.";
    if (text.substr(0, prefix.size()) != prefix || text.size() == prefix.size()) return false;
    bool first = true;
    for (std::size_t index = prefix.size(); index < text.size(); ++index) {
      const char c = text[index];
      if (c == '.') { if (first) return false; first = true; continue; }
      const bool letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
      if (!letter && (first || c < '0' || c > '9')) return false;
      first = false;
    }
    return !first;
  }
public:
  static NativeFailure local(std::string_view code) {
    for (const char *known : {"invalid_options", "invalid_peer", "disconnected", "owner_changed",
         "not_permitted", "not_authorized", "not_supported", "busy", "invalid_value_length",
         "invalid_offset", "improperly_configured", "remote_error", "object_limit", "peer_not_found",
         "ambiguous_peer", "invalid_response", "invalid_characteristic", "peer_changed", "generation_exhausted",
         "snapshot_unstable", "timeout", "services_unresolved", "stale_discovery", "invalid_cursor",
         "transport_error", "pairing_rejected", "invalid_address", "invalid_value", "address_mismatch",
         "ambiguous_characteristic", "unsupported_procedure_selection", "already_subscribed", "invalid_subscription",
         "response_limit", "queue_overflow", "subscription_lost", "cleanup_timeout", "resource_limit", "transport_unavailable",
         "incompatible_backend"}) if (code == known) return NativeFailure(known);
    return NativeFailure("transport_error");
  }
  static NativeFailure from(const BusReply &reply) {
    if (!reply.error) return local("invalid_response");
    auto result = local(reply.error);
    if (result.code_ != "remote_error" || !reply.message ||
        dbus_message_get_type(reply.message.get()) != DBUS_MESSAGE_TYPE_ERROR) return result;
    const char *error = dbus_message_get_error_name(reply.message.get());
    if (!name(error)) return result;
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
