// SPDX-License-Identifier: Apache-2.0
#pragma once
// NOLINTBEGIN(bugprone-unchecked-optional-access): the CHECK helpers throw when an optional
// is empty; the check does not follow them.
#include "notifications.hpp"
#include "procedures_test.hpp"
#include "pending_test.hpp"
#include "notify_value_test.hpp"

namespace notifications_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("notification lifecycle assertion at line " + std::to_string(line));
}
#define NOTIFY_CHECK(value) ::notifications_test::verify((value), __LINE__)
struct Fixture {
  pairing_test::Fixture session;
  std::vector<Json> reports;
  std::map<std::uint64_t, SubscribeResult> results;
  std::map<std::uint64_t, std::optional<NativeFailure>> retirements, cancellations;
  std::vector<std::string> order;
  std::vector<std::pair<std::string, std::string>> methods;
  std::map<std::string, Message> starts, stops;
  std::set<std::string> remote;
  std::string hold, malformed, error;
  std::vector<Json> early;
  bool capacity = true, cancel_on_ack = false;
  NativeNotifications notifications;
  explicit Fixture(const std::string &address) : session(address), notifications(session.owner,
    [&](const Json &value) {
      const auto identifier = std::stoull(value.at("subscription_id").get<std::string>());
      NOTIFY_CHECK(results.count(identifier) && !results.at(identifier).failure);
      reports.push_back(value); order.push_back("value"); return capacity;
    }, [&](std::uint64_t identifier, std::optional<NativeFailure> failure) {
      NOTIFY_CHECK(!retirements.count(identifier)); retirements.emplace(identifier, std::move(failure)); order.push_back("retired");
    }) {
    const auto original = session.peer.on_signal;
    session.peer.on_signal = [&, original](DBusMessage *message) {
      original(message);
      if (session.sender_releases) remote.clear();
    };
    session.peer.on_other = [&](DBusMessage *request) {
      const std::string member = dbus_message_get_member(request), path = dbus_message_get_path(request);
      NOTIFY_CHECK(dbus_message_has_interface(request, characteristic_interface) && dbus_message_has_signature(request, "") &&
                   session.sender == dbus_message_get_sender(request));
      methods.emplace_back(member, path);
      if (member == "StartNotify") {
        NOTIFY_CHECK(!remote.count(path)); remote.insert(path); starts[path].reset(dbus_message_ref(request));
        for (const auto &bytes : early) session.peer.changed({{"Value", "ay", bytes}}, characteristic_interface, path);
      } else {
        NOTIFY_CHECK(member == "StopNotify"); remote.erase(path); stops[path].reset(dbus_message_ref(request));
      }
      if (hold == member) return;
      if (error == member) {
        if (member == "StartNotify") remote.erase(path);
        session.peer.send(Message(dbus_message_new_error(request, "org.bluez.Error.NotPermitted", "private diagnostic")));
      } else if (malformed == member) {
        Message reply(dbus_message_new_method_return(request)); dbus_bool_t value = false;
        NOTIFY_CHECK(dbus_message_append_args(reply.get(), DBUS_TYPE_BOOLEAN, &value, DBUS_TYPE_INVALID)); session.peer.send(std::move(reply));
      } else session.peer.empty_reply(request);
    };
  }
  Json parameters(const Json &address = procedures_test::address, const std::string &mode = "auto") const {
    return {{"address", address}, {"mode", mode}, {"queue_limit", 32}};
  }
  void start(std::uint64_t identifier = 201, const Json &request = {}, int milliseconds = 2000) {
    NOTIFY_CHECK(notifications.subscribe(request.is_null() ? parameters() : request, identifier,
      Clock::now() + std::chrono::milliseconds(milliseconds), [&, identifier](SubscribeResult result) {
        NOTIFY_CHECK(!results.count(identifier)); const bool succeeded = !result.failure;
        results.emplace(identifier, std::move(result)); order.push_back("ack");
        if (succeeded && cancel_on_ack) cancel(identifier);
      }));
  }
  void cancel(std::uint64_t identifier = 201, int milliseconds = 200) {
    NOTIFY_CHECK(notifications.cancel(identifier, Clock::now() + std::chrono::milliseconds(milliseconds),
      [&, identifier](std::optional<NativeFailure> failure) {
        NOTIFY_CHECK(!cancellations.count(identifier)); cancellations.emplace(identifier, std::move(failure)); order.push_back("cancelled");
      }));
  }
  void until(const std::function<bool()> &done) {
    const auto deadline = Clock::now() + std::chrono::seconds(3);
    while (!done() && Clock::now() < deadline) {
      session.peer.poll(); std::vector<pollfd> none; notifications.poll(none, 1);
    }
    NOTIFY_CHECK(done());
  }
  void clean(bool alive = true) {
    if (!alive) until([&] { return session.sender_releases == 1; });
    NOTIFY_CHECK(!notifications.active_count() && !notifications.path_count() && remote.empty() &&
      session.owner.active() == alive && !session.owner.closing() && session.owner.bus().pending_count() == 0 &&
      session.owner.bus().listener_count() == (alive ? 4 : 0));
    if (!alive) NOTIFY_CHECK(session.owner.bus().watch_count() == 0 && session.owner.bus().timeout_count() == 0);
    NOTIFY_CHECK(session.peer.methods.empty()); // borrowed peer is never explicitly disconnected
  }
  void changed(Json bytes, const std::string &path = "/org/bluez/hci0/device/service/char") {
    session.peer.changed({{"Value", "ay", std::move(bytes)}}, characteristic_interface, path);
  }
};
inline Json handle(unsigned handle) {
  auto address = procedures_test::address; address["handle"] = handle; return address;
}
inline void characteristics(Fixture &fixture, unsigned count) {
  for (unsigned index = 1; index < count; ++index) {
    auto characteristic = fixture.session.peer.objects[3]; characteristic.first += std::to_string(index);
    characteristic.second[0].second[2].value = 17 + index; fixture.session.peer.objects.push_back(characteristic);
  }
}
inline void boundaries(const std::string &address) {
  for (const Json &parameters : {Json(), Json::array(), Json::object(), Json{{"address", procedures_test::address}, {"mode", "auto"}},
      Json{{"address", procedures_test::address}, {"mode", "auto"}, {"queue_limit", 0}},
      Json{{"address", procedures_test::address}, {"mode", "auto"}, {"queue_limit", true}},
      Json{{"address", procedures_test::address}, {"mode", "auto"}, {"queue_limit", 10001}},
      Json{{"address", procedures_test::address}, {"mode", "invalid"}, {"queue_limit", 32}}}) {
    Fixture fixture(address); unsigned completions = 0;
    NOTIFY_CHECK(fixture.notifications.subscribe(parameters, 1, Clock::now() + std::chrono::seconds(2), [&](SubscribeResult result) {
      NOTIFY_CHECK(result.failure && result.failure->code() == "invalid_options"); ++completions;
    }));
    fixture.clean(); NOTIFY_CHECK(completions == 1 && fixture.methods.empty() && fixture.session.peer.calls == 1);
  }
  {
    Fixture fixture(address); auto parameters = fixture.parameters(); parameters["address"]["handle"] = true; fixture.start(1, parameters);
    NOTIFY_CHECK(fixture.results.at(1).failure && fixture.results.at(1).failure->code() == "invalid_address");
    fixture.clean(); NOTIFY_CHECK(fixture.methods.empty() && fixture.session.peer.calls == 1);
  }
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return fixture.results.count(201); });
    fixture.start(202); fixture.until([&] { return fixture.results.count(202); });
    NOTIFY_CHECK(fixture.results.at(202).failure && fixture.results.at(202).failure->code() == "already_subscribed" &&
      fixture.notifications.path_count() == 1 && fixture.notifications.active_count() == 1 && fixture.methods.size() == 1);
    fixture.changed(Json::array({1})); fixture.until([&] { return fixture.reports.size() == 1; });
    NOTIFY_CHECK(fixture.reports[0].at("subscription_id") == "201");
    fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean();
  }
  for (const std::string kind : {"notifying_false", "invalidated", "bad_type", "oversize", "metadata", "peer", "service"}) {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return fixture.results.count(201); });
    auto &peer = fixture.session.peer;
    if (kind == "notifying_false") peer.changed({{"Notifying", "b", false}, {"Value", "ay", Json::array({1})}});
    else if (kind == "bad_type") peer.changed({{"Notifying", "s", "true"}});
    else if (kind == "oversize") fixture.changed(std::vector<unsigned char>(513, 1));
    else if (kind == "metadata") peer.changed({{"Handle", "q", 18}});
    else if (kind == "peer") peer.changed({{"Address", "s", "AA:BB:CC:DD:EE:00"}}, device_interface, "/org/bluez/hci0/device");
    else if (kind == "service") peer.changed({{"UUID", "s", "180a"}}, service_interface, "/org/bluez/hci0/device/service");
    else {
      auto message = object_test::changed_message({}, {"Value"}, characteristic_interface);
      NOTIFY_CHECK(dbus_message_set_path(message.get(), "/org/bluez/hci0/device/service/char")); peer.send(std::move(message));
    }
    fixture.until([&] { return fixture.retirements.count(201); }); fixture.clean();
    const auto code = kind == "notifying_false" ? "subscription_lost" : kind == "metadata" || kind == "service" ? "stale_discovery" :
      kind == "peer" ? "peer_changed" : "invalid_response";
    NOTIFY_CHECK(fixture.retirements.at(201) && fixture.retirements.at(201)->code() == code && fixture.reports.empty());
  }
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return fixture.results.count(201); });
    discovery_test::Peer foreign(address, false);
    foreign.changed({{"Value", "ay", Json::array({9})}}, characteristic_interface, "/org/bluez/hci0/device/service/char", fixture.session.sender);
    foreign.barrier();
    fixture.changed(Json::array({8}), "/org/bluez/hci0/other/service/char");
    fixture.session.peer.changed({{"Value", "s", "unrelated"}}, device_interface, "/org/bluez/hci0/device/service/char");
    fixture.changed(Json::array({1})); fixture.until([&] { return fixture.reports.size() == 1; });
    NOTIFY_CHECK(fixture.reports[0].at("value") == Json({{"type", "bytes"}, {"base64", "AQ=="}}));
    fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean();
  }
  {
    Fixture fixture(address); characteristics(fixture, 2); fixture.start(1, fixture.parameters(handle(17)));
    fixture.until([&] { return fixture.results.count(1); }); fixture.start(2, fixture.parameters(handle(18)));
    fixture.until([&] { return fixture.results.count(2); }); fixture.capacity = false;
    for (unsigned index = 0; index < 32; ++index) fixture.changed(Json::array({1}));
    fixture.until([&] { return fixture.retirements.count(1); });
    NOTIFY_CHECK(fixture.retirements.at(1) && fixture.retirements.at(1)->code() == "queue_overflow" && fixture.reports.size() == 1 &&
      fixture.notifications.active_count() == 1 && fixture.notifications.path_count() == 1 && fixture.session.owner.active());
    fixture.capacity = true; fixture.changed(Json::array({2}), "/org/bluez/hci0/device/service/char1");
    fixture.until([&] { return fixture.reports.size() == 2; }); NOTIFY_CHECK(fixture.reports[1].at("subscription_id") == "2");
    fixture.cancel(2); fixture.until([&] { return fixture.cancellations.count(2); }); fixture.clean();
  }
}
inline void capacity(const std::string &address) {
  // One manager listener supports all 64 subscriptions alongside discovery.
  {
    Fixture fixture(address); characteristics(fixture, 64);
    for (unsigned index = 0; index < 64; ++index) {
      fixture.start(index + 1, fixture.parameters(handle(index + 17)));
      fixture.until([&] { return fixture.results.count(index + 1); }); NOTIFY_CHECK(!fixture.results.at(index + 1).failure);
    }
    const auto calls = fixture.session.peer.calls; fixture.start(65);
    NOTIFY_CHECK(fixture.results.at(65).failure && fixture.results.at(65).failure->code() == "busy" && fixture.session.peer.calls == calls &&
      fixture.notifications.active_count() == 64 && fixture.notifications.path_count() == 64 && fixture.session.owner.bus().listener_count() == 5);
    for (unsigned identifier = 1; identifier <= 64; ++identifier) fixture.cancel(identifier, 500);
    fixture.until([&] { return fixture.cancellations.size() == 64; }); fixture.clean();
    for (const auto &[unused, failure] : fixture.cancellations) { (void)unused; NOTIFY_CHECK(!failure); }
  }
  // WBL-C03/V11: StopNotify overtakes an independently blocked ReadValue.
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return fixture.results.count(201); });
    Message read_request; const auto receiver = fixture.session.peer.on_other;
    fixture.session.peer.on_other = [&, receiver](DBusMessage *request) {
      if (dbus_message_is_method_call(request, characteristic_interface, "ReadValue")) read_request.reset(dbus_message_ref(request));
      else receiver(request);
    };
    NativeProcedure read(fixture.session.owner); std::optional<ProcedureResult> result;
    NOTIFY_CHECK(read.start("read", {{"address", procedures_test::address}}, 202, Clock::now() + std::chrono::seconds(2),
      [&](const Json &) { NOTIFY_CHECK(false); return false; }, [&](ProcedureResult value) { result.emplace(std::move(value)); }));
    fixture.until([&] { return bool(read_request); }); fixture.cancel();
    fixture.until([&] { return fixture.cancellations.count(201); });
    NOTIFY_CHECK(!fixture.cancellations.at(201) && !result && read.active() && fixture.session.owner.active() &&
      fixture.session.owner.bus().pending_count() == 1 && fixture.remote.empty());
    Message response(dbus_message_new_method_return(read_request.get())); DBusMessageIter root, array;
    dbus_message_iter_init_append(response.get(), &root);
    NOTIFY_CHECK(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "y", &array) && dbus_message_iter_close_container(&root, &array));
    fixture.session.peer.send(std::move(response)); fixture.until([&] { return bool(result); });
    NOTIFY_CHECK(!result->failure); fixture.clean();
  }
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return fixture.results.count(201); });
    fixture.session.peer.on_query = [](DBusMessage *) {};
    for (unsigned index = 0; index < 64; ++index) {
      auto request = pending_test::request(fixture.session.peer.sender());
      NOTIFY_CHECK(fixture.session.owner.bus().call(request.get(), "a{oa{sa{sv}}}", Clock::now() + std::chrono::seconds(2),
        [](BusReply) { NOTIFY_CHECK(false); }));
    }
    const auto began = Clock::now(); fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean(false);
    NOTIFY_CHECK(Clock::now() - began < std::chrono::milliseconds(250) && fixture.cancellations.at(201) &&
      fixture.cancellations.at(201)->code() == "resource_limit");
  }
  {
    Fixture fixture(address);
    for (unsigned identifier = 1; identifier <= 1000; ++identifier) {
      fixture.start(identifier); fixture.until([&] { return fixture.results.count(identifier); });
      NOTIFY_CHECK(!fixture.results.at(identifier).failure); fixture.cancel(identifier);
      fixture.until([&] { return fixture.cancellations.count(identifier); }); fixture.clean();
      NOTIFY_CHECK(!fixture.notifications.cancel(identifier, Clock::now() + std::chrono::seconds(1),
                                                 [](const auto &) { NOTIFY_CHECK(false); }));
    }
    NOTIFY_CHECK(fixture.methods.size() == 2000 && fixture.session.peer.calls == 1001);
  }
}
inline Json projection(const Json &input, const std::string &address) {
  NOTIFY_CHECK(fields(input, {"flags", "mode", "early_values", "values", "output_capacity"}) &&
    input.at("flags").is_array() && input.at("mode").is_string() && input.at("early_values").is_array() &&
    input.at("values").is_array() && input.at("output_capacity").is_boolean() &&
    input.at("early_values").size() <= 2 && input.at("values").size() <= 64);
  Fixture fixture(address); fixture.session.peer.objects.back().second[0].second.back().value = input.at("flags");
  fixture.early = input.at("early_values").get<std::vector<Json>>(); fixture.capacity = input.at("output_capacity");
  fixture.start(201, fixture.parameters(procedures_test::address, input.at("mode").get<std::string>()));
  fixture.until([&] { return fixture.results.count(201); });
  for (const auto &value : input.at("values")) {
    if (!fixture.notifications.active_count()) break;
    const auto before = fixture.reports.size(); fixture.changed(value);
    fixture.until([&] { return fixture.reports.size() > before || fixture.retirements.count(201); });
    if (!fixture.capacity) fixture.until([&] { return fixture.retirements.count(201); });
  }
  if (fixture.notifications.active_count()) { fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); }
  fixture.clean();
  Json methods = Json::array(); for (const auto &[member, unused] : fixture.methods) { (void)unused; methods.push_back(member); }
  const auto &result = fixture.results.at(201);
  Json attempts = Json::array();
  for (const auto &report : fixture.reports) {
    NOTIFY_CHECK(!result.failure && report.at("metadata").at("characteristic") == result.value.at("characteristic") &&
      report.at("metadata").at("requested_mode") == result.value.at("requested_mode") &&
      report.at("metadata").at("effective_mode") == result.value.at("effective_mode"));
    attempts.push_back({{"value", report.at("value")}, {"metadata", report.at("metadata")}});
  }
  const auto retirement = fixture.retirements.find(201);
  return {{"methods", methods}, {"result", result.failure ? result.failure->envelope() : result.value},
    {"report_attempts", attempts}, {"admitted_reports", fixture.capacity ? attempts.size() : 0},
    {"retirements", fixture.retirements.size()}, {"retirement_error", retirement != fixture.retirements.end() && retirement->second ? retirement->second->envelope() : Json()},
    {"cancelled", fixture.cancellations.count(201) == 1}, {"active_subscriptions", fixture.notifications.active_count()},
    {"active_paths", fixture.notifications.path_count()}, {"pending_calls", fixture.session.owner.bus().pending_count()},
    {"signal_listeners", fixture.session.owner.bus().listener_count()}, {"remote_subscriptions", fixture.remote.size()},
    {"owner_active", fixture.session.owner.active()}, {"sender_releases", fixture.session.sender_releases}};
}
// WBL-N04 lifecycle cases from contract-v1.json. The private daemon is the
// scripted backend: `bound` names the fixture characteristic, the case's
// `sender` is the org.bluez owner and every other signal sender is a separate
// connection. Events run in list order and each signal is followed by a
// daemon round trip on its sender and on the client, so the observation is
// taken after the native owner has admitted or dropped it. ExUnit compares.
inline Json contract(const Json &input, const std::string &address) {
  const bool lifecycle = fields(input, {"sender", "client_sender", "path", "mode", "flags", "events"});
  NOTIFY_CHECK((lifecycle || fields(input, {"mode", "flags", "events"})) && input.at("flags").is_array() &&
    input.at("mode").is_string() && input.at("events").is_array() && !input.at("events").empty() && input.at("events").size() <= 32);
  if (lifecycle) NOTIFY_CHECK(input.at("sender").is_string() && input.at("client_sender").is_string() &&
    input.at("path").is_string() && input.at("sender") != input.at("client_sender"));
  const std::string bound = "/org/bluez/hci0/device/service/char";
  Fixture fixture(address); fixture.session.peer.objects.back().second[0].second.back().value = input.at("flags");
  fixture.hold = "StartNotify";
  std::map<std::string, std::unique_ptr<discovery_test::Peer>> foreign;
  std::optional<std::string> subscription;
  std::optional<std::size_t> cancelled_at;
  std::uint64_t previous = 0;
  const auto sync = [&](discovery_test::Peer &emitter) {
    emitter.barrier(); bool synced = false;
    Message request(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "GetId"));
    NOTIFY_CHECK(request && fixture.session.owner.bus().call(request.get(), "s", Clock::now() + std::chrono::seconds(1),
      [&](BusReply reply) { NOTIFY_CHECK(!reply.error); synced = true; }));
    fixture.until([&] { return synced; });
  };
  for (const auto &event : input.at("events")) {
    NOTIFY_CHECK(event.is_object() && event.contains("at_ms") && integer(event.at("at_ms"), previous, 60000) &&
      event.contains("event") && event.at("event").is_string());
    previous = event.at("at_ms").get<std::uint64_t>();
    const auto kind = event.at("event").get<std::string>();
    if (kind == "subscribe") {
      NOTIFY_CHECK(fields(event, {"at_ms", "event", "id"}) && event.at("id").is_string() && !subscription);
      subscription = event.at("id").get<std::string>();
      fixture.start(201, fixture.parameters(procedures_test::address, input.at("mode").get<std::string>()));
      fixture.until([&] { return fixture.starts.count(bound) || fixture.results.count(201); });
    } else if (kind == "start_notify_ok" || kind == "stop_notify_ok") {
      NOTIFY_CHECK(fields(event, {"at_ms", "event"}));
      auto &held = kind == "start_notify_ok" ? fixture.starts : fixture.stops;
      NOTIFY_CHECK(held.count(bound)); fixture.session.peer.empty_reply(held.at(bound).get());
      if (kind == "start_notify_ok") fixture.until([&] { return fixture.results.count(201); });
      else fixture.until([&] { return fixture.cancellations.count(201); });
    } else if (kind == "cancel") {
      NOTIFY_CHECK(lifecycle && fields(event, {"at_ms", "event", "id"}) && subscription == event.at("id").get<std::string>() &&
        !cancelled_at);
      cancelled_at = fixture.reports.size(); fixture.hold = "StopNotify"; fixture.cancel(201);
      fixture.until([&] { return fixture.stops.count(bound) || fixture.cancellations.count(201); });
    } else {
      NOTIFY_CHECK(lifecycle && kind == "value_changed" && fields(event, {"at_ms", "event", "sender", "path", "bytes_hex"}) &&
        event.at("sender").is_string() && event.at("path").is_string() && event.at("bytes_hex").is_string());
      const auto hex = event.at("bytes_hex").get<std::string>();
      NOTIFY_CHECK(hex.size() % 2 == 0 && hex.size() <= 1024 && hex.find_first_not_of("0123456789abcdef") == std::string::npos);
      Json bytes = Json::array();
      for (std::size_t index = 0; index < hex.size(); index += 2) bytes.push_back(std::stoul(hex.substr(index, 2), nullptr, 16));
      const auto sender = event.at("sender").get<std::string>(), path = event.at("path").get<std::string>();
      NOTIFY_CHECK(sender != input.at("client_sender").get<std::string>());
      const auto target = path == "bound" ? bound : path;
      if (sender == input.at("sender").get<std::string>()) {
        fixture.session.peer.changed({{"Value", "ay", bytes}}, characteristic_interface, target); sync(fixture.session.peer);
      } else {
        auto &peer = foreign[sender];
        if (!peer) peer = std::make_unique<discovery_test::Peer>(address, false);
        peer->changed({{"Value", "ay", bytes}}, characteristic_interface, target, fixture.session.sender); sync(*peer);
      }
    }
  }
  NOTIFY_CHECK(subscription.has_value());
  const auto active = fixture.notifications.active_count();
  const auto symbol = [&](DBusMessage *message) {
    const std::string sender = dbus_message_get_sender(message);
    return lifecycle && sender == fixture.session.sender ? input.at("client_sender").get<std::string>() :
      lifecycle && sender == fixture.session.peer.sender() ? input.at("sender").get<std::string>() : std::string("unknown");
  };
  Json pairs = Json::array();
  for (const auto &[path, start] : fixture.starts)
    pairs.push_back({symbol(start.get()), fixture.stops.count(path) ? Json(symbol(fixture.stops.at(path).get())) : Json()});
  if (active) { fixture.hold.clear(); fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); }
  fixture.clean();
  Json deliveries = Json::array();
  for (const auto &report : fixture.reports)
    deliveries.push_back({{"value", report.at("value")}, {"source", report.at("metadata").at("source")}});
  const auto count = [&](const std::string &member) {
    return std::count_if(fixture.methods.begin(), fixture.methods.end(), [&](const auto &method) { return method.first == member; });
  };
  const auto &result = fixture.results.at(201);
  return {{"result", result.failure ? result.failure->envelope() : Json()}, {"deliveries", deliveries},
    {"calls", {{"start_notify", count("StartNotify")}, {"stop_notify", count("StopNotify")}}}, {"sender_pairs", pairs},
    {"active_subscriptions", active}, {"deliveries_after_cancel", cancelled_at ? fixture.reports.size() - *cancelled_at : 0}};
}
inline void invariants(const std::string &address) {
  boundaries(address); capacity(address);
  // WBL-V07/V08: exact mode selection, ACK-before-early-value, no equality deduplication.
  for (const auto &flags : {Json::array({"notify"}), Json::array({"indicate"}), Json::array({"notify", "indicate"})}) {
    for (const std::string mode : {"auto", "notify", "indicate"}) {
      Fixture fixture(address); fixture.session.peer.objects.back().second[0].second.back().value = flags;
      fixture.early.push_back(Json::array({0, 255})); fixture.start(201, fixture.parameters(procedures_test::address, mode));
      fixture.until([&] { return fixture.results.count(201); });
      const auto selected = notify_value_test::projection({{"flags", flags}, {"mode", mode}});
      if (selected.contains("error")) {
        fixture.clean(); NOTIFY_CHECK(fixture.results.at(201).failure && fixture.results.at(201).failure->code() == selected.at("error") &&
          fixture.methods.empty() && fixture.reports.empty());
      } else {
        NOTIFY_CHECK(!fixture.results.at(201).failure && fixture.results.at(201).value.at("requested_mode") == mode &&
          fixture.results.at(201).value.at("effective_mode") == selected.at("effective_mode"));
        fixture.until([&] { return fixture.reports.size() == 1; });
        NOTIFY_CHECK(fixture.order == std::vector<std::string>({"ack", "value"}));
        fixture.changed(Json::array({0, 255})); fixture.until([&] { return fixture.reports.size() == 2; });
        NOTIFY_CHECK(fixture.reports[0] == fixture.reports[1] && fixture.reports[0].at("metadata").at("source") == "bluez_value_change");
        fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean();
        NOTIFY_CHECK(!fixture.cancellations.at(201) && fixture.retirements.count(201) && !fixture.retirements.at(201) && fixture.methods.size() == 2);
        fixture.changed(Json::array({1})); fixture.session.peer.poll(); std::vector<pollfd> none; fixture.notifications.poll(none, 0);
        NOTIFY_CHECK(fixture.reports.size() == 2);
      }
    }
  }
  {
    Fixture fixture(address); fixture.early = {Json::array({1}), Json::array({2})}; fixture.hold = "StartNotify"; fixture.start();
    fixture.until([&] { return fixture.results.count(201); }); fixture.clean();
    NOTIFY_CHECK(fixture.results.at(201).failure && fixture.results.at(201).failure->code() == "response_limit" &&
      fixture.reports.empty() && fixture.retirements.empty() && fixture.methods.size() == 2);
  }
  {
    Fixture fixture(address); fixture.cancel_on_ack = true; fixture.early = {Json::array({1})}; fixture.start();
    fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean();
    NOTIFY_CHECK(fixture.reports.empty() && fixture.retirements.size() == 1);
  }
  // WBL-V09/V11: original-route cancellation and source loss have one terminal.
  for (const std::string held : {"StartNotify", "StopNotify"}) {
    Fixture fixture(address); fixture.hold = held; fixture.start();
    if (held == "StartNotify") fixture.until([&] { return fixture.starts.size() == 1; });
    else fixture.until([&] { return fixture.results.count(201); });
    const auto began = Clock::now(); fixture.cancel(201, 100);
    fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean(held == "StartNotify");
    NOTIFY_CHECK(Clock::now() - began < std::chrono::milliseconds(250) && fixture.methods.size() == 2 && fixture.reports.empty());
    if (held == "StartNotify") {
      fixture.session.peer.empty_reply(fixture.starts.begin()->second.get());
      NOTIFY_CHECK(fixture.results.at(201).failure && fixture.retirements.empty());
    } else NOTIFY_CHECK(fixture.cancellations.at(201) && fixture.retirements.size() == 1);
  }
  for (const std::string method : {"StartNotify", "StopNotify"}) {
    for (const bool malformed : {false, true}) {
      Fixture fixture(address); (malformed ? fixture.malformed : fixture.error) = method; fixture.start();
      fixture.until([&] { return fixture.results.count(201); });
      if (method == "StopNotify") { fixture.cancel(); fixture.until([&] { return fixture.cancellations.count(201); }); }
      fixture.clean(method == "StartNotify");
      const auto &error = method == "StartNotify" ? fixture.results.at(201).failure : fixture.cancellations.at(201);
      NOTIFY_CHECK(error && error->code() == (malformed ? "invalid_response" : "not_permitted"));
      NOTIFY_CHECK(error->envelope().dump().find("private") == std::string::npos);
    }
  }
  {
    Fixture fixture(address); Message pending;
    fixture.session.peer.on_query = [&](DBusMessage *request) { pending.reset(dbus_message_ref(request)); };
    fixture.start(); fixture.until([&] { return bool(pending); }); fixture.cancel();
    fixture.until([&] { return fixture.cancellations.count(201); }); fixture.clean();
    NOTIFY_CHECK(fixture.results.at(201).failure && fixture.methods.empty());
    fixture.session.peer.reply(pending.get()); fixture.session.peer.on_query = {}; fixture.start(202);
    fixture.until([&] { return fixture.results.count(202); }); NOTIFY_CHECK(!fixture.results.at(202).failure);
    fixture.cancel(202); fixture.until([&] { return fixture.cancellations.count(202); }); fixture.clean();
  }
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return fixture.results.count(201); }); fixture.session.peer.release();
    fixture.until([&] { return fixture.retirements.count(201); }); fixture.clean(false);
    NOTIFY_CHECK(fixture.retirements.at(201) && fixture.retirements.at(201)->code() == "owner_changed");
  }
}
} // namespace notifications_test
// NOLINTEND(bugprone-unchecked-optional-access)
