// SPDX-License-Identifier: Apache-2.0
// Exact Agent1 prompts and explicit policy decisions. These values authorize
// no pairing by themselves and retain no callback or process ownership.
#pragma once
#include "objects.hpp"

namespace wotex::ble {
class PairingRejected : public std::runtime_error {
public:
  PairingRejected() : std::runtime_error("pairing_rejected") {}
};

inline bool pin_text(const std::string &value) {
  return !value.empty() && value.size() <= 16 &&
    std::all_of(value.begin(), value.end(), [](unsigned char c) { return c >= 32 && c <= 126; });
}

struct AgentDecision { Message response; bool accepted; };

class AgentPrompt {
  Message request_;
  std::string kind_;
  Json value_;
  bool answered_ = false;
  AgentPrompt(DBusMessage *request, std::string kind, Json value)
    : request_(dbus_message_ref(request)), kind_(std::move(kind)), value_(std::move(value)) {}
  static void signature(DBusMessage *message, const char *expected) {
    if (!dbus_message_has_signature(message, expected)) throw PairingRejected();
  }
  static std::string text(const char *value, std::size_t bound) {
    if (!value || !*value || strnlen(value, bound + 1) > bound) throw PairingRejected();
    return value;
  }
public:
  static AgentPrompt from(DBusMessage *message, const std::string &device_path) {
    if (!message || dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_METHOD_CALL ||
        !dbus_message_has_interface(message, "org.bluez.Agent1") || dbus_message_get_no_reply(message) ||
        !dbus_message_get_sender(message) || !dbus_message_get_serial(message) ||
        dbus_message_contains_unix_fds(message)) throw PairingRejected();
    const char *member = dbus_message_get_member(message);
    if (!member) throw PairingRejected();
    const std::string name(member);
    const char *device = nullptr, *string = nullptr;
    dbus_uint32_t passkey = 0;
    dbus_uint16_t entered = 0;
    std::string kind;
    Json value;
    if (name == "RequestPinCode" || name == "RequestPasskey" || name == "RequestAuthorization") {
      signature(message, "o");
      if (!dbus_message_get_args(message, nullptr, DBUS_TYPE_OBJECT_PATH, &device, DBUS_TYPE_INVALID))
        throw PairingRejected();
      kind = name == "RequestPinCode" ? "request_pin" : name == "RequestPasskey" ? "request_passkey" : "authorize_pairing";
    } else if (name == "RequestConfirmation") {
      signature(message, "ou");
      if (!dbus_message_get_args(message, nullptr, DBUS_TYPE_OBJECT_PATH, &device,
          DBUS_TYPE_UINT32, &passkey, DBUS_TYPE_INVALID) || passkey > 999999) throw PairingRejected();
      kind = "confirm_passkey"; value = passkey;
    } else if (name == "DisplayPasskey") {
      signature(message, "ouq");
      if (!dbus_message_get_args(message, nullptr, DBUS_TYPE_OBJECT_PATH, &device,
          DBUS_TYPE_UINT32, &passkey, DBUS_TYPE_UINT16, &entered, DBUS_TYPE_INVALID) ||
          passkey > 999999 || entered > 6) throw PairingRejected();
      kind = "display_passkey"; value = {{"passkey", passkey}, {"entered", entered}};
    } else if (name == "DisplayPinCode" || name == "AuthorizeService") {
      signature(message, "os");
      if (!dbus_message_get_args(message, nullptr, DBUS_TYPE_OBJECT_PATH, &device,
          DBUS_TYPE_STRING, &string, DBUS_TYPE_INVALID)) throw PairingRejected();
      if (name == "DisplayPinCode") {
        auto pin = text(string, 16);
        if (!pin_text(pin)) throw PairingRejected();
        kind = "display_pin"; value = std::move(pin);
      } else {
        try { value = uuid_text(text(string, 36)); }
        catch (const InvalidObjects &) { throw PairingRejected(); }
        kind = "authorize_service";
      }
    } else throw PairingRejected();
    if (!device || device_path.empty() || device_path.size() > 4096 ||
        device_path.find('\0') != std::string::npos || device_path != device) throw PairingRejected();
    return {message, std::move(kind), std::move(value)};
  }

  AgentDecision decide(const Json &decision) {
    if (answered_ || !request_) throw PairingRejected();
    auto *request = request_.get();
    if (fields(decision, {"action"}) && decision.at("action") == "reject") {
      Message response(dbus_message_new_error(request, "org.bluez.Error.Rejected", nullptr));
      if (!response) throw std::runtime_error("resource_limit");
      answered_ = true; request_.reset(); return {std::move(response), false};
    }
    Message response(dbus_message_new_method_return(request));
    if (!response) throw std::runtime_error("resource_limit");
    if (fields(decision, {"action"}) && decision.at("action") == "accept" &&
        (kind_ == "confirm_passkey" || kind_ == "authorize_pairing" || kind_ == "authorize_service" ||
         kind_ == "display_pin" || kind_ == "display_passkey")) {
      answered_ = true; request_.reset(); return {std::move(response), true};
    }
    if (fields(decision, {"action", "value"})) {
      if (kind_ == "request_passkey" && decision.at("action") == "passkey" &&
          integer(decision.at("value"), 0, 999999)) {
        dbus_uint32_t value = decision.at("value").get<dbus_uint32_t>();
        if (!dbus_message_append_args(response.get(), DBUS_TYPE_UINT32, &value, DBUS_TYPE_INVALID))
          throw std::runtime_error("resource_limit");
        answered_ = true; request_.reset(); return {std::move(response), true};
      }
      if (kind_ == "request_pin" && decision.at("action") == "pin" && decision.at("value").is_string()) {
        const auto &value = decision.at("value").get_ref<const std::string &>();
        if (!pin_text(value)) throw PairingRejected();
        const char *pin = value.c_str();
        if (!dbus_message_append_args(response.get(), DBUS_TYPE_STRING, &pin, DBUS_TYPE_INVALID))
          throw std::runtime_error("resource_limit");
        answered_ = true; request_.reset(); return {std::move(response), true};
      }
    }
    throw PairingRejected();
  }
  const std::string &kind() const { return kind_; }
  const Json &value() const { return value_; }
};
} // namespace wotex::ble
