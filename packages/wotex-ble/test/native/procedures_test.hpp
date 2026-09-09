// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "procedures.hpp"
#include "pairing_test.hpp"

namespace procedures_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native GATT procedure assertion at line " + std::to_string(line));
}
#define PROCEDURE_CHECK(value) ::procedures_test::verify((value), __LINE__)
inline const Json address{{"service", "180f"}, {"characteristic", "2a19"},
                         {"object_path", nullptr}, {"handle", nullptr}, {"generation", nullptr}};

struct Fixture {
  pairing_test::Fixture session;
  NativeProcedure operation;
  std::optional<ProcedureResult> result;
  std::vector<Json> events;
  std::vector<std::string> methods;
  std::vector<unsigned char> value{0, 255, 52, 18};
  std::string mode;
  Message pending;
  unsigned completions = 0;
  bool emit_ok = true, cancel_on_emit = false;
  explicit Fixture(const std::string &bus_address, bool owned = false) : session(bus_address, owned), operation(session.owner) {
    session.peer.objects.back().second[0].second.back().value = Json::array({"read", "write", "notify"});
    session.peer.on_other = [&](DBusMessage *request) {
      const std::string member = dbus_message_get_member(request);
      PROCEDURE_CHECK(dbus_message_has_interface(request, characteristic_interface) &&
        dbus_message_has_path(request, "/org/bluez/hci0/device/service/char") &&
        session.sender == dbus_message_get_sender(request));
      methods.push_back(member);
      DBusMessageIter root, dictionary;
      PROCEDURE_CHECK(dbus_message_iter_init(request, &root));
      if (member == "WriteValue") {
        PROCEDURE_CHECK(dbus_message_has_signature(request, "aya{sv}") && events.size() == 1 &&
          events[0] == Json({{"version", 1}, {"id", "81"}, {"event", "write_submitted"}}));
        DBusMessageIter data; dbus_message_iter_recurse(&root, &data);
        std::vector<unsigned char> written;
        while (dbus_message_iter_get_arg_type(&data) != DBUS_TYPE_INVALID) {
          PROCEDURE_CHECK(dbus_message_iter_get_arg_type(&data) == DBUS_TYPE_BYTE && written.size() < 512);
          unsigned char byte; dbus_message_iter_get_basic(&data, &byte); written.push_back(byte);
          dbus_message_iter_next(&data);
        }
        value = std::move(written);
        PROCEDURE_CHECK(dbus_message_iter_next(&root));
      } else PROCEDURE_CHECK(member == "ReadValue" && dbus_message_has_signature(request, "a{sv}") && events.empty());
      dbus_message_iter_recurse(&root, &dictionary);
      Json options = Json::object();
      while (dbus_message_iter_get_arg_type(&dictionary) != DBUS_TYPE_INVALID) {
        PROCEDURE_CHECK(dbus_message_iter_get_arg_type(&dictionary) == DBUS_TYPE_DICT_ENTRY && options.size() < 2);
        DBusMessageIter entry, variant; dbus_message_iter_recurse(&dictionary, &entry);
        const char *name = nullptr; dbus_message_iter_get_basic(&entry, &name);
        PROCEDURE_CHECK(name && !options.contains(name) && dbus_message_iter_next(&entry) &&
                        dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_VARIANT);
        dbus_message_iter_recurse(&entry, &variant);
        if (std::string(name) == "type") {
          PROCEDURE_CHECK(dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING);
          const char *text = nullptr; dbus_message_iter_get_basic(&variant, &text); options[name] = text;
        } else {
          PROCEDURE_CHECK(std::string(name) == "offset" && dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_UINT16);
          dbus_uint16_t offset; dbus_message_iter_get_basic(&variant, &offset); options[name] = offset;
        }
        PROCEDURE_CHECK(!dbus_message_iter_next(&variant) && !dbus_message_iter_next(&entry));
        dbus_message_iter_next(&dictionary);
      }
      PROCEDURE_CHECK(!dbus_message_iter_next(&root));
      PROCEDURE_CHECK(options == (member == "WriteValue" ? Json{{"type", "request"}, {"offset", 0}} : Json::object()));
      pending.reset(dbus_message_ref(request));
      if (mode == "held") return;
      if (mode == "remote") {
        session.peer.send(Message(dbus_message_new_error(request, "org.bluez.Error.NotPermitted", "private fixture diagnostic"))); return;
      }
      Message response(dbus_message_new_method_return(request));
      if (mode == "malformed") {
        dbus_bool_t unexpected = true;
        PROCEDURE_CHECK(dbus_message_append_args(response.get(), DBUS_TYPE_BOOLEAN, &unexpected, DBUS_TYPE_INVALID));
      } else if (member == "ReadValue") {
        if (mode == "oversize") value.assign(513, 0);
        DBusMessageIter reply, array; dbus_message_iter_init_append(response.get(), &reply);
        PROCEDURE_CHECK(dbus_message_iter_open_container(&reply, DBUS_TYPE_ARRAY, "y", &array));
        for (const auto byte : value) PROCEDURE_CHECK(dbus_message_iter_append_basic(&array, DBUS_TYPE_BYTE, &byte));
        PROCEDURE_CHECK(dbus_message_iter_close_container(&reply, &array));
      }
      session.peer.send(std::move(response));
    };
  }
  void start(const std::string &name, Json parameters, int milliseconds = 2000) {
    PROCEDURE_CHECK(operation.start(name, parameters, 81, Clock::now() + std::chrono::milliseconds(milliseconds),
      [&](const Json &event) {
        events.push_back(event);
        if (cancel_on_emit) operation.cancel(Clock::now() + std::chrono::milliseconds(100));
        return emit_ok;
      },
      [&](ProcedureResult value) { result.emplace(std::move(value)); ++completions; }));
  }
  void until(const std::function<bool()> &done) {
    const auto deadline = Clock::now() + std::chrono::seconds(3);
    while (!done() && Clock::now() < deadline) {
      session.peer.poll(); std::vector<pollfd> none; operation.poll(none, 1);
    }
    PROCEDURE_CHECK(done());
  }
  void clean(bool alive) {
    if (!alive) until([&] { return session.sender_releases == 1; });
    PROCEDURE_CHECK(result && completions == 1 && !operation.active() && session.owner.active() == alive &&
      !session.owner.closing() && session.owner.bus().pending_count() == 0);
    if (!alive) PROCEDURE_CHECK(session.owner.bus().watch_count() == 0 && session.owner.bus().timeout_count() == 0 &&
      session.owner.bus().listener_count() == 0);
  }
};

inline Json write_parameters(const std::vector<unsigned char> &value) {
  const auto view = value.empty() ? std::string_view{} : std::string_view(reinterpret_cast<const char *>(value.data()), value.size());
  return {{"address", address}, {"value", AttributeBytes::from_bytes(view).envelope()}};
}
inline void rejected(Fixture &fixture, const char *code, unsigned snapshots = 1) {
  fixture.until([&] { return bool(fixture.result); }); fixture.clean(true);
  PROCEDURE_CHECK(fixture.result->failure && fixture.result->failure->code() == code &&
    !fixture.result->write_submitted && fixture.result->value.is_null() && fixture.events.empty() &&
    fixture.methods.empty() && fixture.session.peer.calls == snapshots && fixture.session.peer.methods.empty());
}
inline void admission(const std::string &bus_address) {
  // Pure rejection precedes metadata refresh and every GATT call.
  for (const auto &value : {Json(), Json::array(), Json::object(), Json{{"address", address}, {"extra", true}}}) {
    Fixture fixture(bus_address); fixture.start("read", value); rejected(fixture, "invalid_options");
  }
  for (const auto &selector : {
      Json(), Json::array(), Json::object(),
      Json{{"service", true}, {"characteristic", "2a19"}, {"object_path", nullptr}, {"handle", nullptr}, {"generation", nullptr}},
      Json{{"service", "180f"}, {"characteristic", "invalid"}, {"object_path", nullptr}, {"handle", nullptr}, {"generation", nullptr}}}) {
    Fixture fixture(bus_address); fixture.start("read", {{"address", selector}}); rejected(fixture, "invalid_address");
  }
  for (const std::string key : {"object_path", "handle", "generation"}) {
    const std::vector<Json> values = key == "object_path" ? std::vector<Json>{true, 5, "", "relative", "/bad-path", std::string(4097, '/'), std::string("/a\0b", 4)} :
      key == "handle" ? std::vector<Json>{true, 0, -1, 65536, 1.5, "1"} : std::vector<Json>{true, -1, 1.5, "1"};
    for (const auto &value : values) {
      auto selector = address; selector[key] = value;
      Fixture fixture(bus_address); fixture.start("read", {{"address", selector}}); rejected(fixture, "invalid_address");
    }
  }
  for (const auto &value : {Json(), Json::array(), Json{{"type", "bytes"}, {"base64", "AR=="}},
      Json{{"type", "bytes"}, {"base64", std::string(684, 'A')}},
      Json{{"type", "bytes"}, {"base64", "AQ=="}, {"extra", true}}}) {
    Fixture fixture(bus_address); fixture.start("write", {{"address", address}, {"value", value}}); rejected(fixture, "invalid_value");
  }
  {
    Fixture fixture(bus_address); fixture.start("write_command", write_parameters({1})); rejected(fixture, "invalid_options");
  }
  {
    Fixture fixture(bus_address); fixture.start("read", {{"address", address}}, 0); rejected(fixture, "timeout");
  }
  for (const std::string name : {"read", "write"}) {
    Fixture fixture(bus_address);
    fixture.session.peer.objects.back().second[0].second.back().value = Json::array({"write-without-response", "notify"});
    fixture.start(name, name == "read" ? Json{{"address", address}} : write_parameters({1}));
    rejected(fixture, "not_permitted", 2);
  }
  for (const auto &mismatch : {Json{{"service", "180a"}}, Json{{"characteristic", "2a1a"}},
      Json{{"handle", 18}}, Json{{"object_path", "/org/bluez/hci1/device/service/char"}}}) {
    auto selector = address; selector.update(mismatch);
    Fixture fixture(bus_address); fixture.start("read", {{"address", selector}}); rejected(fixture, "address_mismatch", 2);
  }
  for (const std::uint64_t generation : {std::uint64_t{0}, std::numeric_limits<std::uint64_t>::max()}) {
    auto selector = address; selector["generation"] = generation;
    Fixture fixture(bus_address); fixture.start("read", {{"address", selector}}); rejected(fixture, "stale_discovery", 2);
  }
  for (const bool exact : {false, true}) {
    Fixture fixture(bus_address);
    auto duplicate = fixture.session.peer.objects.back(); duplicate.first += "2";
    duplicate.second[0].second[2].value = 18; fixture.session.peer.objects.push_back(duplicate);
    auto selector = address;
    if (exact) { selector["handle"] = 17; selector["object_path"] = "/org/bluez/hci0/device/service/char"; }
    fixture.start("read", {{"address", selector}});
    if (!exact) rejected(fixture, "ambiguous_characteristic", 2);
    else { fixture.until([&] { return bool(fixture.result); }); fixture.clean(true); PROCEDURE_CHECK(!fixture.result->failure); }
  }
  {
    Fixture fixture(bus_address);
    auto selector = address; selector["generation"] = fixture.session.owner.generation();
    fixture.session.peer.objects.back().second[0].second[2].value = 18;
    fixture.start("read", {{"address", selector}}); rejected(fixture, "stale_discovery", 2);
  }
}
inline void lifecycle(const std::string &bus_address) {
  // WBL-V11: cancellation retires the original sender, with no write retry.
  for (const std::string name : {"read", "write"}) {
    for (const bool owned : {false, true}) {
      Fixture fixture(bus_address, owned); fixture.mode = "held";
      fixture.start(name, name == "read" ? Json{{"address", address}} : write_parameters({1, 2}));
      fixture.until([&] { return bool(fixture.pending); });
      const auto start = Clock::now();
      fixture.operation.cancel(start + std::chrono::milliseconds(100));
      fixture.operation.cancel(start + std::chrono::seconds(10));
      fixture.until([&] { return bool(fixture.result); }); fixture.clean(false);
      PROCEDURE_CHECK(Clock::now() - start < std::chrono::milliseconds(250) && fixture.result->failure &&
        fixture.result->failure->code() == "timeout" && fixture.result->write_submitted == (name == "write") &&
        fixture.methods.size() == 1 && fixture.session.peer.methods.size() == (owned ? 2 : 0));
      fixture.session.peer.empty_reply(fixture.pending.get()); fixture.session.peer.poll();
      std::vector<pollfd> none; fixture.operation.poll(none, 0);
      PROCEDURE_CHECK(fixture.completions == 1 && fixture.methods.size() == 1);
    }
    {
      Fixture fixture(bus_address); fixture.mode = "held";
      fixture.start(name, name == "read" ? Json{{"address", address}} : write_parameters({1}));
      fixture.until([&] { return bool(fixture.pending); }); fixture.session.peer.release();
      fixture.until([&] { return bool(fixture.result); }); fixture.clean(false);
      PROCEDURE_CHECK(fixture.result->failure && fixture.result->failure->code() == "owner_changed" && fixture.methods.size() == 1);
    }
    {
      Fixture fixture(bus_address); Message held;
      fixture.session.peer.on_query = [&](DBusMessage *request) { held.reset(dbus_message_ref(request)); };
      fixture.start(name, name == "read" ? Json{{"address", address}} : write_parameters({1}));
      fixture.until([&] { return bool(held); });
      fixture.operation.cancel(Clock::now() + std::chrono::milliseconds(100));
      fixture.until([&] { return bool(fixture.result); }); fixture.clean(false);
      PROCEDURE_CHECK(!fixture.result->write_submitted && fixture.methods.empty() && fixture.events.empty());
      fixture.session.peer.reply(held.get()); fixture.session.peer.poll();
    }
  }
  for (const bool cancel : {false, true}) {
    Fixture fixture(bus_address); fixture.emit_ok = cancel; fixture.cancel_on_emit = cancel;
    fixture.start("write", write_parameters({1}));
    fixture.until([&] { return bool(fixture.result); }); fixture.clean(!cancel);
    PROCEDURE_CHECK(fixture.result->failure && fixture.result->failure->code() == (cancel ? "timeout" : "resource_limit") &&
      !fixture.result->write_submitted && fixture.methods.empty() && fixture.events.size() == 1);
  }
  {
    Fixture fixture(bus_address, true); fixture.mode = "held"; fixture.session.block_disconnect = true;
    fixture.start("write", write_parameters({1})); fixture.until([&] { return bool(fixture.pending); });
    const auto start = Clock::now(); fixture.operation.cancel(start + std::chrono::milliseconds(100));
    fixture.until([&] { return bool(fixture.result); }); fixture.clean(false);
    PROCEDURE_CHECK(Clock::now() - start < std::chrono::milliseconds(250) && fixture.result->write_submitted &&
      fixture.session.peer.methods.size() == 2);
  }
  {
    Fixture fixture(bus_address);
    for (std::uint64_t counter = 1; counter <= 1000; ++counter) {
      NativeProcedure operation(fixture.session.owner); unsigned completed = 0;
      PROCEDURE_CHECK(operation.start("read", {{"address", address}}, counter, Clock::now() + std::chrono::seconds(2),
        [&](const Json &) { PROCEDURE_CHECK(false); return false; }, [&](ProcedureResult result) {
          PROCEDURE_CHECK(!result.failure && !result.write_submitted && result.value == write_parameters(fixture.value).at("value"));
          ++completed;
        }));
      const auto deadline = Clock::now() + std::chrono::seconds(2);
      while (!completed && Clock::now() < deadline) {
        fixture.session.peer.poll(); std::vector<pollfd> none; operation.poll(none, 1);
      }
      PROCEDURE_CHECK(completed == 1 && !operation.active() && fixture.session.owner.active() &&
        fixture.session.owner.bus().pending_count() == 0 && fixture.session.owner.bus().listener_count() == 4);
    }
    PROCEDURE_CHECK(fixture.methods.size() == 1000 && fixture.session.peer.calls == 1001 &&
                    fixture.session.peer.methods.empty());
  }
}
inline Json projection(const Json &input, const std::string &bus_address) {
  PROCEDURE_CHECK(fields(input, {"operation", "parameters", "peer_value", "response"}) && input.at("operation").is_string() &&
    input.at("peer_value").is_array() && input.at("peer_value").size() <= 512 && input.at("response").is_string());
  Fixture fixture(bus_address); fixture.value.clear();
  for (const auto &value : input.at("peer_value")) {
    PROCEDURE_CHECK(integer(value, 0, 255)); fixture.value.push_back(value.get<unsigned char>());
  }
  fixture.mode = input.at("response").get<std::string>();
  PROCEDURE_CHECK(fixture.mode == "ok" || fixture.mode == "remote" || fixture.mode == "malformed" || fixture.mode == "held");
  fixture.start(input.at("operation").get<std::string>(), input.at("parameters"), fixture.mode == "held" ? 100 : 2000);
  fixture.until([&] { return bool(fixture.result); });
  const bool alive = fixture.mode != "held" && fixture.mode != "malformed";
  fixture.clean(alive);
  return {{"methods", fixture.methods}, {"events", fixture.events}, {"peer_value", fixture.value},
          {"result", fixture.result->failure ? fixture.result->failure->envelope() : Json{{"value", fixture.result->value}}},
          {"write_submitted", fixture.result->write_submitted}, {"owner_active", fixture.session.owner.active()},
          {"native_completions", fixture.completions}, {"pending_calls", fixture.session.owner.bus().pending_count()},
          {"sender_releases", fixture.session.sender_releases}, {"disconnect_calls", fixture.session.peer.methods.size()}};
}
inline void invariants(const std::string &bus_address) {
  admission(bus_address); lifecycle(bus_address);
  // WBL-P04/S03/V05: exact read/write signatures, byte bounds and request-only writes.
  for (const std::string name : {"read", "write"}) {
    for (const std::size_t size : {0U, 1U, 2U, 255U, 256U, 512U}) {
      Fixture fixture(bus_address);
      std::vector<unsigned char> value;
      for (std::size_t index = 0; index < size; ++index) value.push_back(static_cast<unsigned char>(index));
      fixture.value = value;
      fixture.start(name, name == "read" ? Json{{"address", address}} : write_parameters(value));
      fixture.until([&] { return bool(fixture.result); }); fixture.clean(true);
      PROCEDURE_CHECK(!fixture.result->failure && fixture.value == value && fixture.methods.size() == 1 &&
        fixture.result->write_submitted == (name == "write"));
      PROCEDURE_CHECK(fixture.result->value == (name == "read" ? write_parameters(value).at("value") : Json()));
      PROCEDURE_CHECK(fixture.session.peer.calls == 2 && fixture.session.peer.methods.empty());
    }
    for (const std::string mode : {"remote", "malformed", "held"}) {
      Fixture fixture(bus_address); fixture.mode = mode;
      fixture.start(name, name == "read" ? Json{{"address", address}} : write_parameters({1, 2, 3}), mode == "held" ? 100 : 2000);
      fixture.until([&] { return bool(fixture.result); }); fixture.clean(mode == "remote");
      PROCEDURE_CHECK(fixture.result->failure && fixture.methods.size() == 1 && fixture.result->value.is_null() &&
        fixture.result->write_submitted == (name == "write"));
      const auto &failure = *fixture.result->failure;
      PROCEDURE_CHECK(failure.code() == (mode == "remote" ? "not_permitted" : mode == "malformed" ? "invalid_response" : "timeout"));
      PROCEDURE_CHECK(failure.envelope().dump().find("private") == std::string::npos);
    }
  }
  {
    Fixture fixture(bus_address); fixture.mode = "oversize"; fixture.start("read", {{"address", address}});
    fixture.until([&] { return bool(fixture.result); }); fixture.clean(false);
    PROCEDURE_CHECK(fixture.result->failure && fixture.result->failure->code() == "invalid_response" && fixture.result->value.is_null());
  }
}
} // namespace procedures_test
