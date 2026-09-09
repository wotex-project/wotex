// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "pairing.hpp"
#include "agent_test.hpp"
#include "discovery_test.hpp"

namespace pairing_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native Pair ownership assertion at line " + std::to_string(line));
}
#define PAIR_CHECK(value) ::pairing_test::verify((value), __LINE__)

struct AgentCall {
  DBusPendingCall *pending = nullptr;
  Message response;
  AgentCall(discovery_test::Peer &peer, const std::string &sender, const std::string &path,
            const char *member, const char *signature, const char *device = agent_test::device,
            dbus_uint32_t passkey = 123456, const char *text = "1234", dbus_uint16_t entered = 3) {
    auto request = agent_test::message(member, signature, device, passkey, text, entered);
    PAIR_CHECK(dbus_message_set_destination(request.get(), sender.c_str()) &&
               dbus_message_set_path(request.get(), path.c_str()) && dbus_message_set_sender(request.get(), nullptr));
    dbus_message_set_serial(request.get(), 0);
    PAIR_CHECK(dbus_connection_send_with_reply(peer.connection(), request.get(), &pending, 2000) && pending);
    dbus_connection_flush(peer.connection());
  }
  AgentCall(const AgentCall &) = delete;
  ~AgentCall() { if (pending) { dbus_pending_call_cancel(pending); dbus_pending_call_unref(pending); } }
  bool completed() {
    if (!response && dbus_pending_call_get_completed(pending)) response.reset(dbus_pending_call_steal_reply(pending));
    return bool(response);
  }
  bool rejected() {
    return completed() && dbus_message_get_type(response.get()) == DBUS_MESSAGE_TYPE_ERROR &&
      dbus_message_has_signature(response.get(), "") &&
      std::string(dbus_message_get_error_name(response.get())) == "org.bluez.Error.Rejected";
  }
};

struct Fixture {
  discovery_test::Peer peer;
  LiveDiscovery owner;
  NativePairing pairing;
  std::vector<Json> events;
  std::vector<std::string> methods;
  std::optional<NativeFailure> failure;
  Message registration, pair_request, unregistration;
  std::string agent_path, sender, open_failure;
  std::string hold, error_at, malformed_at;
  unsigned registered = 0, completions = 0, sender_releases = 0;
  bool delivered = false, emit_ok = true, block_disconnect = false;
  explicit Fixture(const std::string &address, bool owned = false)
    : peer(address), owner(address, NativePeer::from(object_test::peer_fields)), pairing(owner) {
    peer.on_signal = [&](DBusMessage *signal) {
      if (!dbus_message_is_signal(signal, DBUS_INTERFACE_DBUS, "NameOwnerChanged")) return;
      PAIR_CHECK(dbus_message_has_sender(signal, DBUS_SERVICE_DBUS) && dbus_message_has_signature(signal, "sss"));
      const char *name = nullptr, *before = nullptr, *after = nullptr;
      PAIR_CHECK(dbus_message_get_args(signal, nullptr, DBUS_TYPE_STRING, &name, DBUS_TYPE_STRING, &before,
        DBUS_TYPE_STRING, &after, DBUS_TYPE_INVALID));
      if (name == sender && !*after) { registered = 0; ++sender_releases; }
    };
    DBusError match_error = DBUS_ERROR_INIT;
    dbus_bus_add_match(peer.connection(), "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'", &match_error);
    PAIR_CHECK(!dbus_error_is_set(&match_error)); dbus_error_free(&match_error);
    peer.on_other = [&](DBusMessage *request) {
      const std::string member = dbus_message_get_member(request);
      methods.push_back(member);
      if (member == "RegisterAgent") {
        PAIR_CHECK(dbus_message_has_path(request, "/org/bluez") && dbus_message_has_interface(request, "org.bluez.AgentManager1") &&
                   dbus_message_has_signature(request, "os"));
        const char *path = nullptr, *capability = nullptr;
        PAIR_CHECK(dbus_message_get_args(request, nullptr, DBUS_TYPE_OBJECT_PATH, &path,
          DBUS_TYPE_STRING, &capability, DBUS_TYPE_INVALID));
        PAIR_CHECK(std::string(capability) == "DisplayYesNo" || std::string(capability) == "NoInputNoOutput" ||
                   std::string(capability) == "KeyboardOnly");
        PAIR_CHECK(registered == 0); registered = 1;
        agent_path = path; sender = dbus_message_get_sender(request);
        registration.reset(dbus_message_ref(request));
      } else if (member == "Pair") {
        PAIR_CHECK(registered == 1 && dbus_message_has_path(request, agent_test::device) &&
                   dbus_message_has_interface(request, device_interface) && dbus_message_has_signature(request, "") &&
                   sender == dbus_message_get_sender(request));
        pair_request.reset(dbus_message_ref(request));
      } else if (member == "UnregisterAgent") {
        PAIR_CHECK(dbus_message_has_path(request, "/org/bluez") && dbus_message_has_interface(request, "org.bluez.AgentManager1") &&
                   dbus_message_has_signature(request, "o") && sender == dbus_message_get_sender(request));
        const char *path = nullptr;
        PAIR_CHECK(dbus_message_get_args(request, nullptr, DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_INVALID) && path == agent_path);
        registered = 0; unregistration.reset(dbus_message_ref(request));
      } else PAIR_CHECK(false); // no default Agent, trust, bond removal or cancellation method
      if (error_at == member) {
        if (member == "RegisterAgent") registered = 0;
        peer.send(Message(dbus_message_new_error(request, "org.bluez.Error.NotAuthorized", "private fixture diagnostic")));
      } else if (malformed_at == member) {
        Message response(dbus_message_new_method_return(request)); dbus_uint32_t extra = 42;
        PAIR_CHECK(dbus_message_append_args(response.get(), DBUS_TYPE_UINT32, &extra, DBUS_TYPE_INVALID));
        peer.send(std::move(response));
      } else if (hold != member && member != "Pair") peer.empty_reply(request);
    };
    if (owned) {
      peer.objects[1].second[0].second[3].value = false;
      peer.objects[1].second[0].second[4].value = false;
      peer.on_method = [&](DBusMessage *request) {
        if (dbus_message_is_method_call(request, device_interface, "Connect")) {
          peer.objects[1].second[0].second[3].value = true;
          peer.objects[1].second[0].second[4].value = true;
          peer.empty_reply(request);
        } else if (!block_disconnect) peer.empty_reply(request);
      };
    }
    bool ready = false;
    PAIR_CHECK(owner.connect(owned, Clock::now() + std::chrono::seconds(2), [&](const char *error) {
      if (error) open_failure = error; ready = true;
    }, [&](const char *error) { open_failure = error; }));
    discovery_test::until(peer, owner, [&] { return ready; });
    PAIR_CHECK(open_failure.empty() && owner.active()); sender = owner.bus().unique_name();
  }
  void start(const Json &parameters = {{"capability", "DisplayYesNo"}}, int milliseconds = 2000) {
    PAIR_CHECK(pairing.start(parameters, 51, Clock::now() + std::chrono::milliseconds(milliseconds), [&](const Json &event) {
      events.push_back(event); return emit_ok;
    }, [&](std::optional<NativeFailure> error) {
      failure = std::move(error); ++completions; delivered = true;
    }));
  }
  void until(const std::function<bool()> &done, int milliseconds = 3000) {
    const auto deadline = Clock::now() + std::chrono::milliseconds(milliseconds);
    while (!done() && Clock::now() < deadline) {
      peer.poll(); std::vector<pollfd> none; pairing.poll(none, 1);
    }
    PAIR_CHECK(done());
  }
  Json answer(const Json &decision) const {
    PAIR_CHECK(!events.empty());
    return {{"challenge_id", events.back().at("challenge").at("id")}, {"decision", decision}};
  }
  void clean(bool alive) {
    if (!alive) until([&] { return registered == 0 && sender_releases == 1; }, 1000);
    PAIR_CHECK(delivered && completions == 1 && !pairing.active() && !pairing.pending_prompt() &&
               owner.active() == alive && !owner.closing() && owner.bus().export_count() == 0 &&
               owner.bus().response_count() == 0 && owner.bus().pending_count() == 0 && registered == 0);
    if (!alive) PAIR_CHECK(owner.bus().listener_count() == 0 && owner.bus().watch_count() == 0 && owner.bus().timeout_count() == 0);
  }
};

inline Json projection(const Json &input, const std::string &address) {
  PAIR_CHECK(fields(input, {"capability", "decision"}) && input.at("capability").is_string());
  Fixture fixture(address); fixture.start({{"capability", input.at("capability")}});
  fixture.until([&] { return bool(fixture.pair_request); });
  AgentCall challenge(fixture.peer, fixture.sender, fixture.agent_path, "RequestConfirmation", "ou");
  fixture.until([&] { return fixture.events.size() == 1; });
  PAIR_CHECK(!fixture.delivered);
  fixture.pairing.reply(fixture.answer(input.at("decision")));
  fixture.until([&] { return challenge.completed(); });
  const bool accepted = dbus_message_get_type(challenge.response.get()) == DBUS_MESSAGE_TYPE_METHOD_RETURN;
  if (accepted) fixture.peer.empty_reply(fixture.pair_request.get());
  fixture.until([&] { return fixture.delivered; }); fixture.clean(accepted);
  const auto &prompt = fixture.events.front().at("challenge");
  return {{"methods", fixture.methods}, {"challenge_kind", prompt.at("kind")}, {"challenge_value", prompt.at("value")},
          {"agent_accepted", accepted}, {"agent_reply_signature", dbus_message_get_signature(challenge.response.get())},
          {"result", fixture.failure ? fixture.failure->envelope() : Json{{"paired", true}}},
          {"owner_active", fixture.owner.active()}, {"native_completions", fixture.completions},
          {"pending_calls", fixture.owner.bus().pending_count()}, {"exports", fixture.owner.bus().export_count()},
          {"queued_replies", fixture.owner.bus().response_count()}, {"pending_prompt", fixture.pairing.pending_prompt()},
          {"remote_agents", fixture.registered}, {"sender_releases", fixture.sender_releases},
          {"disconnect_calls", fixture.peer.methods.size()}};
}
inline void invariants(const std::string &address) {
  // WBL-P03/S02/V06: explicit policy precedes Pair completion; all procedures
  // use the same actual unique sender, with no default Agent or bond mutation.
  for (const auto *capability : {"DisplayYesNo", "NoInputNoOutput", "KeyboardOnly"}) {
    Fixture fixture(address); fixture.start({{"capability", capability}});
    fixture.until([&] { return bool(fixture.pair_request); });
    PAIR_CHECK(fixture.owner.bus().export_count() == 1 && fixture.events.empty());
    AgentCall challenge(fixture.peer, fixture.sender, fixture.agent_path, "RequestConfirmation", "ou");
    fixture.until([&] { return fixture.events.size() == 1; });
    const auto &event = fixture.events.front();
    PAIR_CHECK(fields(event, {"version", "id", "event", "challenge"}) && event.at("version") == 1 &&
      event.at("id") == "51" && event.at("event") == "agent_challenge" && event.at("challenge").at("id") == "51:1" &&
      event.at("challenge").at("kind") == "confirm_passkey" && event.at("challenge").at("value") == 123456 &&
      event.at("challenge").at("peer") == Json({{"adapter", "/org/bluez/hci0"},
        {"address", "AA:BB:CC:DD:EE:FF"}, {"address_type", "random"}}) &&
      integer(event.at("challenge").at("timeout_ms"), 1, 2000) && !fixture.delivered);
    PAIR_CHECK(fixture.pairing.reply(fixture.answer({{"action", "accept"}})));
    fixture.until([&] { return challenge.completed(); });
    PAIR_CHECK(dbus_message_has_signature(challenge.response.get(), "") &&
      dbus_message_get_type(challenge.response.get()) == DBUS_MESSAGE_TYPE_METHOD_RETURN);
    fixture.peer.empty_reply(fixture.pair_request.get());
    fixture.until([&] { return fixture.delivered; });
    fixture.clean(true); PAIR_CHECK(!fixture.failure && fixture.peer.methods.empty());
    PAIR_CHECK(fixture.methods == std::vector<std::string>({"RegisterAgent", "Pair", "UnregisterAgent"}));
  }
  for (const Json &parameters : {Json::object(), Json{{"capability", "DisplayOnly"}},
                                 Json{{"capability", "DisplayYesNo"}, {"extra", true}}}) {
    Fixture fixture(address); fixture.start(parameters);
    fixture.clean(true); PAIR_CHECK(fixture.failure && fixture.failure->code() == "invalid_options" && fixture.methods.empty());
  }
  for (const auto *step : {"RegisterAgent", "Pair"}) {
    Fixture fixture(address); fixture.error_at = step; fixture.start();
    fixture.until([&] { return fixture.delivered; }); fixture.clean(true);
    PAIR_CHECK(fixture.failure && fixture.failure->envelope() == Json({{"code", "not_authorized"},
      {"name", "org.bluez.Error.NotAuthorized"}}));
    PAIR_CHECK(fixture.peer.methods.empty());
  }
  {
    Fixture fixture(address); fixture.start();
    fixture.until([&] { return bool(fixture.pair_request); });
    AgentCall challenge(fixture.peer, fixture.sender, fixture.agent_path, "RequestAuthorization", "o");
    fixture.until([&] { return fixture.events.size() == 1; });
    PAIR_CHECK(fixture.pairing.reply(fixture.answer({{"action", "reject"}})));
    fixture.until([&] { return fixture.delivered && challenge.completed(); }); fixture.clean(false);
    PAIR_CHECK(challenge.rejected() && fixture.failure && fixture.failure->code() == "pairing_rejected" && fixture.peer.methods.empty());
  }
  {
    Fixture fixture(address); fixture.start({{"capability", "DisplayYesNo"}}, 100);
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(fixture.failure && fixture.failure->code() == "pairing_rejected" && fixture.peer.methods.empty());
  }
  for (const auto *step : {"RegisterAgent", "Pair"}) {
    Fixture fixture(address); fixture.malformed_at = step; fixture.start();
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(fixture.failure && fixture.failure->code() == "invalid_response");
  }
  for (const auto *mode : {"wrong_id", "bad_decision", "wrong_peer", "overlap", "premature", "emit_full"}) {
    Fixture fixture(address); fixture.emit_ok = std::string(mode) != "emit_full"; fixture.start();
    fixture.until([&] { return bool(fixture.pair_request); });
    const char *device = std::string(mode) == "wrong_peer" ? "/org/bluez/hci0/other" : agent_test::device;
    AgentCall challenge(fixture.peer, fixture.sender, fixture.agent_path, "RequestAuthorization", "o", device);
    if (std::string(mode) == "wrong_peer" || std::string(mode) == "emit_full") {
      fixture.until([&] { return fixture.delivered && challenge.completed(); });
    } else {
      fixture.until([&] { return fixture.events.size() == 1; });
      if (std::string(mode) == "wrong_id") {
        PAIR_CHECK(!fixture.pairing.reply({{"challenge_id", "other"}, {"decision", {{"action", "accept"}}}}));
      } else if (std::string(mode) == "bad_decision") {
        PAIR_CHECK(!fixture.pairing.reply(fixture.answer({{"action", "pin"}, {"value", "1234"}})));
      } else if (std::string(mode) == "premature") {
        fixture.peer.empty_reply(fixture.pair_request.get());
      } else {
        AgentCall overlap(fixture.peer, fixture.sender, fixture.agent_path, "RequestConfirmation", "ou");
        fixture.until([&] { return fixture.delivered && challenge.completed() && overlap.completed(); });
        PAIR_CHECK(overlap.rejected());
      }
      fixture.until([&] { return fixture.delivered && challenge.completed(); });
    }
    fixture.clean(false); PAIR_CHECK(challenge.rejected() && fixture.failure && fixture.events.size() <= 1);
    PAIR_CHECK(fixture.failure->code() == (std::string(mode) == "emit_full" ? "resource_limit" : "pairing_rejected"));
  }
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return bool(fixture.pair_request); });
    discovery_test::Peer foreign(address, false);
    AgentCall attack(foreign, fixture.sender, fixture.agent_path, "RequestAuthorization", "o");
    fixture.until([&] { foreign.poll(); return attack.completed(); });
    PAIR_CHECK(attack.rejected() && fixture.events.empty() && !fixture.delivered && fixture.pairing.active());
    fixture.pairing.cancel(Clock::now() + std::chrono::milliseconds(500));
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
  }
  for (const auto *member : {"Cancel", "Release"}) {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return bool(fixture.pair_request); });
    AgentCall challenge(fixture.peer, fixture.sender, fixture.agent_path, "RequestAuthorization", "o");
    fixture.until([&] { return fixture.events.size() == 1; });
    if (std::string(member) == "Release") fixture.registered = 0;
    AgentCall control(fixture.peer, fixture.sender, fixture.agent_path, member, "");
    fixture.until([&] { return fixture.delivered && control.completed() && challenge.completed(); }); fixture.clean(false);
    PAIR_CHECK(challenge.rejected() && dbus_message_get_type(control.response.get()) == DBUS_MESSAGE_TYPE_METHOD_RETURN &&
      dbus_message_has_signature(control.response.get(), ""));
    PAIR_CHECK(fixture.methods.size() == (std::string(member) == "Release" ? 2U : 3U));
  }
  {
    Fixture fixture(address); fixture.hold = "RegisterAgent"; fixture.start();
    fixture.until([&] { return bool(fixture.registration); });
    fixture.pairing.cancel(Clock::now() + std::chrono::milliseconds(500));
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(!fixture.pair_request && fixture.failure && fixture.failure->code() == "pairing_rejected");
    fixture.peer.empty_reply(fixture.registration.get());
    std::vector<pollfd> none; fixture.pairing.poll(none, 0); fixture.peer.poll();
    PAIR_CHECK(fixture.completions == 1 && fixture.owner.bus().pending_count() == 0);
  }
  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return bool(fixture.pair_request); });
    fixture.peer.release(); fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(fixture.failure && fixture.failure->code() == "owner_changed");
  }

  {
    Fixture fixture(address); fixture.error_at = "UnregisterAgent"; fixture.start();
    fixture.until([&] { return bool(fixture.pair_request); }); fixture.peer.empty_reply(fixture.pair_request.get());
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(fixture.failure && fixture.failure->code() == "disconnected");
  }
  {
    // Unregister and Disconnect share the caller's already finite allowance.
    Fixture fixture(address, true); fixture.block_disconnect = true; fixture.hold = "UnregisterAgent";
    fixture.start(); fixture.until([&] { return bool(fixture.pair_request); });
    PAIR_CHECK(fixture.owner.link_owned());
    const auto began = Clock::now();
    fixture.pairing.cancel(began + std::chrono::milliseconds(300));
    fixture.until([&] { return fixture.peer.methods.size() == 2; });
    PAIR_CHECK(fixture.peer.methods[0].first == "Connect" && fixture.peer.methods[1].first == "Disconnect" &&
      fixture.peer.methods[0].second == fixture.peer.methods[1].second && fixture.peer.methods[0].second == fixture.sender);
    // A repeated cancellation cannot restart either cleanup phase.
    fixture.pairing.cancel(Clock::now() + std::chrono::milliseconds(500));
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(Clock::now() - began <= std::chrono::milliseconds(500));
    PAIR_CHECK(fixture.failure && fixture.failure->code() == "pairing_rejected");
  }
  {
    // A topology refresh canceled before registration leaves no pending query.
    Fixture fixture(address);
    fixture.peer.changed({{"Handle", "q", 24}});
    fixture.until([&] { return fixture.owner.stale(); });
    fixture.peer.on_query = [](auto) {};
    fixture.start(); fixture.pairing.cancel(Clock::now() + std::chrono::milliseconds(500));
    fixture.until([&] { return fixture.delivered; });
    PAIR_CHECK(!fixture.owner.active() && !fixture.owner.closing() && fixture.owner.bus().pending_count() == 0 &&
      fixture.methods.empty() && !fixture.pairing.active() && fixture.completions == 1);
  }
  {
    Fixture fixture(address);
    for (unsigned cycle = 0; cycle < 100; ++cycle) {
      NativePairing attempt(fixture.owner);
      bool completed = false;
      std::optional<NativeFailure> failure;
      fixture.pair_request.reset();
      PAIR_CHECK(attempt.start({{"capability", "NoInputNoOutput"}}, 100 + cycle,
        Clock::now() + std::chrono::seconds(2), [](const Json &) { return false; },
        [&](std::optional<NativeFailure> error) { failure = std::move(error); completed = true; }));
      const auto deadline = Clock::now() + std::chrono::seconds(3);
      bool replied = false;
      while (!completed && Clock::now() < deadline) {
        fixture.peer.poll(); std::vector<pollfd> none; attempt.poll(none, 1);
        if (fixture.pair_request && !replied) { fixture.peer.empty_reply(fixture.pair_request.get()); replied = true; }
      }
      PAIR_CHECK(completed && !failure && !attempt.active() && !attempt.pending_prompt() && fixture.registered == 0 &&
        fixture.owner.active() && fixture.owner.bus().export_count() == 0 && fixture.owner.bus().pending_count() == 0 &&
        fixture.owner.bus().response_count() == 0);
    }
    PAIR_CHECK(fixture.methods.size() == 300 && fixture.peer.methods.empty());
  }

  {
    Fixture fixture(address); fixture.start(); fixture.until([&] { return bool(fixture.pair_request); });
    unsigned canceled_callbacks = 0;
    for (unsigned count = 0; count < 63; ++count) {
      Message request(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "GetId"));
      PAIR_CHECK(fixture.owner.bus().call(request.get(), "s", Clock::now() + std::chrono::seconds(2),
        [&](BusReply) { ++canceled_callbacks; }));
    }
    PAIR_CHECK(fixture.owner.bus().pending_count() == 64);
    fixture.pairing.cancel(Clock::now() + std::chrono::milliseconds(500));
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(canceled_callbacks == 0 && fixture.methods == std::vector<std::string>({"RegisterAgent", "Pair"}));
  }
  {
    auto request = agent_test::message("RequestPinCode", "o");
    for (const std::string &name : {std::string("org.bluez.Error.Future"), std::string("org.other.Error.Failed"),
         std::string("org.bluez.Error.") + std::string(112, 'A'), std::string("org.bluez.Error.") + std::string(113, 'A')}) {
      BusReply reply{"remote_error", Message(dbus_message_new_error(request.get(), name.c_str(), "private fixture diagnostic"))};
      const auto result = NativeFailure::from(reply).envelope();
      PAIR_CHECK(result.at("code") == "remote_error" && result.dump().find("private") == std::string::npos);
      const bool named = name.size() <= 128 && name.rfind("org.bluez.Error.", 0) == 0;
      PAIR_CHECK(result.contains("name") == named);
      if (named) PAIR_CHECK(result.at("name") == name);
    }
    PAIR_CHECK(NativeFailure::local("private fixture diagnostic").envelope() == Json({{"code", "transport_error"}}));
  }

  {
    Fixture fixture(address);
    fixture.peer.changed({{"Handle", "q", 24}}); fixture.until([&] { return fixture.owner.stale(); });
    fixture.peer.on_query = [](auto) {};
    fixture.start({{"capability", "DisplayYesNo"}}, 50);
    fixture.until([&] { return fixture.delivered; }); fixture.clean(false);
    PAIR_CHECK(fixture.failure && fixture.failure->code() == "pairing_rejected" && fixture.methods.empty());
  }

}
} // namespace pairing_test
