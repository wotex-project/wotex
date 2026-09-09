// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "procedures_test.hpp"

namespace health_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native health assertion at line " + std::to_string(line));
}
#define HEALTH_CHECK(value) ::health_test::verify((value), __LINE__)
struct Fixture : procedures_test::Fixture {
  std::vector<object_test::Property> properties;
  explicit Fixture(const std::string &address, bool owned = false) : procedures_test::Fixture(address, owned),
    properties(session.peer.objects[1].second[0].second) {
    session.peer.on_other = [&](DBusMessage *request) {
      HEALTH_CHECK(dbus_message_is_method_call(request, "org.freedesktop.DBus.Properties", "GetAll") &&
        dbus_message_has_path(request, "/org/bluez/hci0/device") && dbus_message_has_signature(request, "s") &&
        session.sender == dbus_message_get_sender(request) &&
        dbus_message_has_destination(request, session.owner.owner().c_str()));
      const char *interface = nullptr;
      HEALTH_CHECK(dbus_message_get_args(request, nullptr, DBUS_TYPE_STRING, &interface, DBUS_TYPE_INVALID) &&
        std::string(interface) == device_interface);
      methods.emplace_back("GetAll"); pending.reset(dbus_message_ref(request));
      if (mode == "held") return;
      respond();
    };
  }
  void respond() {
    if (mode == "remote") {
      session.peer.send(Message(dbus_message_new_error(pending.get(), "org.bluez.Error.NotPermitted", "private diagnostic"))); return;
    }
    Message response(dbus_message_new_method_return(pending.get())); DBusMessageIter root, dictionary;
    dbus_message_iter_init_append(response.get(), &root);
    if (mode == "malformed") object_test::string(root, "invalid result");
    else {
      HEALTH_CHECK(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "{sv}", &dictionary));
      for (const auto &property : properties) object_test::property(dictionary, property);
      HEALTH_CHECK(dbus_message_iter_close_container(&root, &dictionary));
    }
    session.peer.send(std::move(response));
  }
  void query(int milliseconds = 2000, const Json &parameters = Json::object()) {
    start("health", parameters, milliseconds); until([&] { return bool(result); });
    HEALTH_CHECK(events.empty() && !result->write_submitted);
  }
};
inline Json projection(const Json &input, const std::string &address) {
  HEALTH_CHECK(fields(input, {"properties", "mode"}) && input.at("properties").is_array() &&
    (input.at("mode") == "reply" || input.at("mode") == "held" || input.at("mode") == "remote"));
  Fixture fixture(address); fixture.properties.clear();
  for (const auto &property : input.at("properties")) {
    HEALTH_CHECK(fields(property, {"name", "signature", "value"}) && property.at("name").is_string() && property.at("signature").is_string());
    fixture.properties.push_back({property.at("name").get<std::string>(), property.at("signature").get<std::string>(), property.at("value")});
  }
  fixture.mode = input.at("mode").get<std::string>(); fixture.query(fixture.mode == "held" ? 100 : 2000);
  const bool alive = !fixture.result->failure || fixture.result->failure->code() == "not_permitted";
  fixture.clean(alive);
  return {{"failure", fixture.result->failure ? fixture.result->failure->envelope() : Json()},
    {"value", fixture.result->value}, {"get_all_calls", fixture.methods.size()},
    {"owned_sender_releases", fixture.session.sender_releases}, {"disconnect_calls", fixture.session.peer.methods.size()}};
}

inline void invariants(const std::string &address) {
  {
    Fixture fixture(address); fixture.properties.push_back({"Future", "s", std::string(10000, 'x')});
    fixture.query(); fixture.clean(true);
    HEALTH_CHECK(!fixture.result->failure && fixture.result->value == Json({{"connected", true}, {"services_resolved", true}}) &&
      fixture.methods.size() == 1 && fixture.session.peer.methods.empty());
  }
  for (unsigned missing = 0; missing < 5; ++missing) {
    Fixture fixture(address); fixture.properties.erase(fixture.properties.begin() + missing); fixture.query(); fixture.clean(false);
    HEALTH_CHECK(fixture.result->failure && fixture.result->failure->code() == "invalid_response");
  }
  for (unsigned wrong = 0; wrong < 5; ++wrong) {
    Fixture fixture(address); fixture.properties[wrong].signature = "u"; fixture.properties[wrong].value = 1;
    fixture.query(); fixture.clean(false); HEALTH_CHECK(fixture.result->failure->code() == "invalid_response");
  }
  for (const auto &[index, value, code] : std::vector<std::tuple<unsigned, Json, std::string>>{
      {0, "/org/bluez/hci1", "peer_changed"}, {1, "02:00:00:00:00:FF", "peer_changed"}, {2, "public", "peer_changed"},
      {1, "invalid", "invalid_response"}, {2, "unknown", "invalid_response"},
      {3, false, "disconnected"}, {4, false, "disconnected"}}) {
    Fixture fixture(address); fixture.properties[index].value = value; fixture.query(); fixture.clean(false);
    HEALTH_CHECK(fixture.result->failure && fixture.result->failure->code() == code);
  }
  for (const auto &mode : {"held", "malformed", "remote"}) {
    Fixture fixture(address); fixture.mode = mode; fixture.query(50); fixture.clean(fixture.mode == "remote");
    HEALTH_CHECK(fixture.result->failure->code() == (fixture.mode == "held" ? "timeout" : fixture.mode == "remote" ? "not_permitted" : "invalid_response"));
    if (fixture.mode == "held") { fixture.mode = ""; fixture.respond(); fixture.session.peer.poll(); HEALTH_CHECK(fixture.completions == 1); }
  }
  {
    Fixture fixture(address); fixture.properties.push_back(fixture.properties.front()); fixture.query(); fixture.clean(false);
    HEALTH_CHECK(fixture.result->failure->code() == "invalid_response");
  }
  {
    Fixture fixture(address);
    for (unsigned i = 0; i < 252; ++i) fixture.properties.push_back({"Future" + std::to_string(i), "s", ""});
    fixture.query(); fixture.clean(false); HEALTH_CHECK(fixture.result->failure->code() == "object_limit");
  }
  {
    Fixture fixture(address); fixture.query(2000, Json{{"unexpected", true}}); fixture.clean(true);
    HEALTH_CHECK(fixture.result->failure->code() == "invalid_options" && fixture.methods.empty());
  }
  {
    Fixture fixture(address); fixture.mode = "held"; fixture.start("health", Json::object());
    fixture.until([&] { return bool(fixture.pending); });
    const auto began = Clock::now(); fixture.operation.cancel(began + std::chrono::milliseconds(100));
    fixture.until([&] { return bool(fixture.result); }); fixture.clean(false);
    HEALTH_CHECK(Clock::now() - began < std::chrono::seconds(1) && fixture.result->failure->code() == "timeout");
  }
}
} // namespace health_test
