// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "agent.hpp"

namespace agent_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native Agent prompt assertion at line " + std::to_string(line));
}
#define AGENT_CHECK(value) ::agent_test::verify((value), __LINE__)
constexpr const char *device = "/org/bluez/hci0/device";
inline Message message(const char *member, const char *signature, const char *peer = device,
                        dbus_uint32_t passkey = 123456, const char *text = "1234", dbus_uint16_t entered = 3) {
  Message request(dbus_message_new_method_call(":1.8", "/org/wotex/ble/agent_1", "org.bluez.Agent1", member));
  AGENT_CHECK(request && dbus_message_set_sender(request.get(), ":1.9"));
  dbus_message_set_serial(request.get(), 31);
  const std::string sig(signature);
  bool built = sig.empty();
  if (sig == "o") built = dbus_message_append_args(request.get(), DBUS_TYPE_OBJECT_PATH, &peer, DBUS_TYPE_INVALID);
  if (sig == "ou") built = dbus_message_append_args(request.get(), DBUS_TYPE_OBJECT_PATH, &peer,
      DBUS_TYPE_UINT32, &passkey, DBUS_TYPE_INVALID);
  if (sig == "ouq") built = dbus_message_append_args(request.get(), DBUS_TYPE_OBJECT_PATH, &peer,
      DBUS_TYPE_UINT32, &passkey, DBUS_TYPE_UINT16, &entered, DBUS_TYPE_INVALID);
  if (sig == "os") built = dbus_message_append_args(request.get(), DBUS_TYPE_OBJECT_PATH, &peer,
      DBUS_TYPE_STRING, &text, DBUS_TYPE_INVALID);
  if (sig == "u") built = dbus_message_append_args(request.get(), DBUS_TYPE_UINT32, &passkey, DBUS_TYPE_INVALID);
  AGENT_CHECK(built); return request;
}
template <class Function> inline void rejected(Function function) {
  bool failed = false;
  try { function(); }
  catch (const PairingRejected &error) {
    AGENT_CHECK(std::string(error.what()) == "pairing_rejected"); failed = true;
  }
  AGENT_CHECK(failed);
}
inline Json projection(const Json &input) {
  // The fixture builder accepts only representable D-Bus inputs. Expected
  // results never enter this process; the production decoder owns acceptance.
  AGENT_CHECK(fields(input, {"member", "signature", "body", "device_path", "decision"}));
  AGENT_CHECK(input.at("member").is_string() && input.at("signature").is_string() &&
              input.at("body").is_array() && input.at("device_path").is_string());
  const auto member = input.at("member").get<std::string>();
  const auto signature = input.at("signature").get<std::string>();
  const auto &body = input.at("body");
  AGENT_CHECK(member.size() <= 255 && member.find('\0') == std::string::npos && dbus_validate_member(member.c_str(), nullptr));
  AGENT_CHECK(signature.size() <= 8 && signature.size() == body.size());
  Message request(dbus_message_new_method_call(":1.8", "/org/wotex/ble/agent_1", "org.bluez.Agent1", member.c_str()));
  AGENT_CHECK(request && dbus_message_set_sender(request.get(), ":1.9"));
  dbus_message_set_serial(request.get(), 31);
  DBusMessageIter arguments; dbus_message_iter_init_append(request.get(), &arguments);
  for (std::size_t index = 0; index < signature.size(); ++index) {
    const auto &item = body.at(index);
    if (signature[index] == 'o' || signature[index] == 's') {
      AGENT_CHECK(item.is_string()); const auto &value = item.get_ref<const std::string &>();
      AGENT_CHECK(value.size() <= 4096 && value.find('\0') == std::string::npos);
      AGENT_CHECK(signature[index] != 'o' || dbus_validate_path(value.c_str(), nullptr));
      const char *text = value.c_str();
      AGENT_CHECK(dbus_message_iter_append_basic(&arguments, signature[index], &text));
    } else if (signature[index] == 'u') {
      AGENT_CHECK(integer(item, 0, 0xffffffffU)); auto value = item.get<dbus_uint32_t>();
      AGENT_CHECK(dbus_message_iter_append_basic(&arguments, DBUS_TYPE_UINT32, &value));
    } else if (signature[index] == 'q') {
      AGENT_CHECK(integer(item, 0, 65535)); auto value = item.get<dbus_uint16_t>();
      AGENT_CHECK(dbus_message_iter_append_basic(&arguments, DBUS_TYPE_UINT16, &value));
    } else AGENT_CHECK(false);
  }
  try {
    auto prompt = AgentPrompt::from(request.get(), input.at("device_path").get<std::string>());
    Json result = {{"accepted", true}, {"kind", prompt.kind()}, {"value", prompt.value()}};
    request.reset();
    auto decision = prompt.decide(input.at("decision"));
    auto *reply = decision.response.get();
    Json response = {{"signature", dbus_message_get_signature(reply)}, {"body", Json::array()},
                     {"error", nullptr}, {"reply_serial", dbus_message_get_reply_serial(reply)},
                     {"destination", dbus_message_get_destination(reply)}};
    if (dbus_message_has_signature(reply, "s")) {
      const char *value = nullptr;
      AGENT_CHECK(dbus_message_get_args(decision.response.get(), nullptr, DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID));
      response["body"].push_back(value);
    } else if (dbus_message_has_signature(reply, "u")) {
      dbus_uint32_t value = 0;
      AGENT_CHECK(dbus_message_get_args(decision.response.get(), nullptr, DBUS_TYPE_UINT32, &value, DBUS_TYPE_INVALID));
      response["body"].push_back(value);
    }
    if (const char *error = dbus_message_get_error_name(reply)) response["error"] = error;
    result["decision_accepted"] = decision.accepted; result["reply"] = std::move(response);
    return result;
  } catch (const PairingRejected &) { return {{"accepted", false}}; }
}
inline void invariants() {
  struct Case { const char *member, *signature, *kind; Json value, decision; const char *reply; };
  const std::vector<Case> cases = {
    {"RequestPinCode", "o", "request_pin", nullptr, {{"action", "pin"}, {"value", "1234"}}, "s"},
    {"RequestPasskey", "o", "request_passkey", nullptr, {{"action", "passkey"}, {"value", 123456}}, "u"},
    {"RequestAuthorization", "o", "authorize_pairing", nullptr, {{"action", "accept"}}, ""},
    {"RequestConfirmation", "ou", "confirm_passkey", 123456, {{"action", "accept"}}, ""},
    {"DisplayPinCode", "os", "display_pin", "1234", {{"action", "accept"}}, ""},
    {"DisplayPasskey", "ouq", "display_passkey", {{"passkey", 123456}, {"entered", 3}}, {{"action", "accept"}}, ""},
    {"AuthorizeService", "os", "authorize_service", "00001234-0000-1000-8000-00805f9b34fb", {{"action", "accept"}}, ""}
  };
  // WBL-S02/V06: all seven exact prompt schemas require explicit matching decisions.
  for (const auto &item : cases) {
    auto request = message(item.member, item.signature);
    auto prompt = AgentPrompt::from(request.get(), device);
    AGENT_CHECK(prompt.kind() == item.kind && prompt.value() == item.value);
    request.reset(); // the prompt owns the retained request until its one answer
    auto result = prompt.decide(item.decision);
    AGENT_CHECK(result.accepted && dbus_message_has_signature(result.response.get(), item.reply) &&
      dbus_message_get_reply_serial(result.response.get()) == 31 &&
      dbus_message_has_destination(result.response.get(), ":1.9"));
    rejected([&] { prompt.decide(item.decision); });
    if (std::string(item.reply) == "s") {
      const char *value = nullptr;
      AGENT_CHECK(dbus_message_get_args(result.response.get(), nullptr, DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID) &&
                  std::string(value) == "1234");
    } else if (std::string(item.reply) == "u") {
      dbus_uint32_t value = 0;
      AGENT_CHECK(dbus_message_get_args(result.response.get(), nullptr, DBUS_TYPE_UINT32, &value, DBUS_TYPE_INVALID) && value == 123456);
    }

    request = message(item.member, item.signature);
    auto negative = AgentPrompt::from(request.get(), device).decide({{"action", "reject"}});
    AGENT_CHECK(!negative.accepted && dbus_message_has_signature(negative.response.get(), "") &&
      std::string(dbus_message_get_error_name(negative.response.get())) == "org.bluez.Error.Rejected");
    for (const Json &invalid : {Json(), Json::array(), Json::object(), Json(true), Json("accept"),
          Json{{"action", true}}, Json{{"action", "accept"}, {"extra", nullptr}},
          Json{{"action", "reject"}, {"value", nullptr}}, Json{{"action", "other"}}}) {
      auto invalid_prompt = AgentPrompt::from(request.get(), device);
      rejected([&] { invalid_prompt.decide(invalid); });
      AGENT_CHECK(!invalid_prompt.decide({{"action", "reject"}}).accepted);
    }
    auto other = message(item.member, item.signature, "/org/bluez/hci0/device_other");
    rejected([&] { AgentPrompt::from(other.get(), device); });
    auto wrong_type = message(item.member, "u");
    rejected([&] { AgentPrompt::from(wrong_type.get(), device); });
  }
  for (const auto *member : {"Cancel", "Release", "Unsupported"}) {
    auto request = message(member, "");
    rejected([&] { AgentPrompt::from(request.get(), device); });
  }
  for (const auto passkey : {0U, 999999U, 1000000U, 0xffffffffU}) {
    auto request = message("RequestConfirmation", "ou", device, passkey);
    if (passkey <= 999999) AGENT_CHECK(AgentPrompt::from(request.get(), device).value() == passkey);
    else rejected([&] { AgentPrompt::from(request.get(), device); });
  }
  for (dbus_uint16_t entered : {0, 6, 7, 65535}) {
    auto request = message("DisplayPasskey", "ouq", device, 0, "", entered);
    if (entered <= 6) AGENT_CHECK(AgentPrompt::from(request.get(), device).value().at("entered") == entered);
    else rejected([&] { AgentPrompt::from(request.get(), device); });
  }
  for (const auto *pin : {"", "12345678901234567", "\n", "\xC3\xA4"}) {
    auto request = message("DisplayPinCode", "os", device, 0, pin);
    rejected([&] { AgentPrompt::from(request.get(), device); });
  }
  for (const auto *uuid : {"", "not-a-uuid", "123456789012345678901234567890123456789"}) {
    auto request = message("AuthorizeService", "os", device, 0, uuid);
    rejected([&] { AgentPrompt::from(request.get(), device); });
  }
  {
    auto request = message("RequestPinCode", "o");
    for (const Json &value : {Json(""), Json("12345678901234567"), Json("\n"), Json("\xC3\xA4"),
                            Json(std::string("A\0B", 3)), Json(1234)}) {
      auto prompt = AgentPrompt::from(request.get(), device);
      rejected([&] { prompt.decide({{"action", "pin"}, {"value", value}}); });
    }
    auto prompt = AgentPrompt::from(request.get(), device);
    rejected([&] { prompt.decide({{"action", "accept"}}); });
    rejected([&] { prompt.decide({{"action", "passkey"}, {"value", 1234}}); });
    AGENT_CHECK(prompt.decide({{"action", "pin"}, {"value", "1234567890123456"}}).accepted);
  }
  {
    auto request = message("RequestPasskey", "o");
    for (const Json &value : {Json(-1), Json(1000000), Json(1.0), Json(true), Json("123456")}) {
      auto prompt = AgentPrompt::from(request.get(), device);
      rejected([&] { prompt.decide({{"action", "passkey"}, {"value", value}}); });
    }
    for (const auto value : {0U, 999999U}) {
      auto prompt = AgentPrompt::from(request.get(), device);
      AGENT_CHECK(prompt.decide({{"action", "passkey"}, {"value", value}}).accepted);
    }
    auto prompt = AgentPrompt::from(request.get(), device);
    rejected([&] { prompt.decide({{"action", "accept"}}); });
  }
  {
    auto request = message("RequestPinCode", "o");
    dbus_message_set_no_reply(request.get(), true);
    rejected([&] { AgentPrompt::from(request.get(), device); });
    dbus_message_set_no_reply(request.get(), false);
    dbus_message_set_serial(request.get(), 0);
    rejected([&] { AgentPrompt::from(request.get(), device); });
    rejected([&] { AgentPrompt::from(nullptr, device); });
  }
}
} // namespace agent_test
