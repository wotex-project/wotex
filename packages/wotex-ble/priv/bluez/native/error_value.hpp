// SPDX-License-Identifier: Apache-2.0
// Closed error values shared by SDK replies and report terminal controls.
#pragma once
#include "frame.hpp"

namespace wotex::ble {
inline bool native_error_name(std::string_view text) {
  if (text.size() > 128) return false;
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
inline bool native_error_code(std::string_view code) {
  for (const char *known : {"invalid_options", "invalid_peer", "disconnected", "owner_changed",
         "not_permitted", "not_authorized", "not_supported", "busy", "invalid_value_length",
         "invalid_offset", "improperly_configured", "remote_error", "object_limit", "peer_not_found",
         "ambiguous_peer", "invalid_response", "invalid_characteristic", "peer_changed", "generation_exhausted",
         "snapshot_unstable", "timeout", "services_unresolved", "stale_discovery", "invalid_cursor",
         "transport_error", "pairing_rejected", "invalid_address", "invalid_value", "address_mismatch",
         "ambiguous_characteristic", "unsupported_procedure_selection", "already_subscribed", "invalid_subscription",
         "response_limit", "queue_overflow", "subscription_lost", "cleanup_timeout", "resource_limit", "transport_unavailable",
         "incompatible_backend"}) if (code == known) return true;
  return false;
}
inline bool native_error(const Json &value) {
  if ((!fields(value, {"code"}) && !fields(value, {"code", "name"})) ||
      !value["code"].is_string() || !native_error_code(value["code"].get_ref<const std::string &>())) return false;
  return !value.contains("name") || (value["name"].is_string() && native_error_name(value["name"].get_ref<const std::string &>()));
}
} // namespace wotex::ble
