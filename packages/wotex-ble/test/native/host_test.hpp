// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "host.hpp"
#include "discovery_test.hpp"
#include "pairing_test.hpp"
#include <array>

namespace host_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) { if (!value) throw std::runtime_error("native host assertion at line " + std::to_string(line)); }
#define HOST_CHECK(value) ::host_test::verify((value), __LINE__)
inline const std::string session_generation = "0123456789abcdef0123456789abcdef";
inline const Json gatt_address{{"service", "180f"}, {"characteristic", "2a19"}, {"object_path", nullptr}, {"handle", nullptr}, {"generation", nullptr}};
struct Fixture {
  discovery_test::Peer peer;
  NativeHost host{[] { return std::string(32, 'a'); }};
  std::array<int, 2> descriptors{-1, -1};
  std::vector<Json> frames;
  Lines decoder;
  std::uint64_t report_bytes = 0, report_sequence = 0;
  Message held;
  std::string hold;
  std::string sender;
  unsigned disconnects = 0, notifications = 0, stops = 0;
  const std::string address;
  explicit Fixture(const std::string &address) : peer(address), address(address) {
    HOST_CHECK(::pipe(descriptors.data()) == 0);
    for (int fd : descriptors) HOST_CHECK(::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK) == 0);
    peer.objects.back().second[0].second.back().value = Json::array({"read", "write", "notify"});
    peer.on_method = [&](DBusMessage *request) { HOST_CHECK(dbus_message_is_method_call(request, device_interface, "Disconnect")); ++disconnects; peer.empty_reply(request); };
    peer.on_other = [&](DBusMessage *request) {
      const std::string method = dbus_message_get_member(request);
      HOST_CHECK(sender == dbus_message_get_sender(request) && peer.sender() == dbus_message_get_destination(request));
      if (method == "StartNotify") ++notifications;
      if (method == "StopNotify") ++stops;
      if (hold == method) { held.reset(dbus_message_ref(request)); return; }
      Message reply(dbus_message_new_method_return(request));
      if (method == "ReadValue") {
        HOST_CHECK(dbus_message_has_signature(request, "a{sv}"));
        const unsigned char bytes[] = {1, 255}; const unsigned char *data = bytes;
        HOST_CHECK(dbus_message_append_args(reply.get(), DBUS_TYPE_ARRAY, DBUS_TYPE_BYTE, &data, 2, DBUS_TYPE_INVALID));
      } else if (method == "GetAll") {
        HOST_CHECK(dbus_message_has_signature(request, "s") && dbus_message_has_path(request, "/org/bluez/hci0/device"));
        DBusMessageIter root, dictionary; dbus_message_iter_init_append(reply.get(), &root);
        HOST_CHECK(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "{sv}", &dictionary));
        for (const auto &property : peer.objects[1].second[0].second) object_test::property(dictionary, property);
        HOST_CHECK(dbus_message_iter_close_container(&root, &dictionary));
      } else if (method == "WriteValue") HOST_CHECK(dbus_message_has_signature(request, "aya{sv}"));
      else if (method == "StartNotify" || method == "StopNotify") HOST_CHECK(dbus_message_has_signature(request, ""));
      else HOST_CHECK(false);
      peer.send(std::move(reply));
    };
    flush(); HOST_CHECK(frames.size() == 1 && frames[0].at("event") == "ready");
    host.receive({{"version", 1}, {"event", "flow_open"}, {"session_generation", session_generation}});
  }
  ~Fixture() { for (int descriptor : descriptors) if (descriptor >= 0) ::close(descriptor); }
  void flush() {
    host.flush(descriptors[1]); std::array<char, 8192> bytes{};
    for (;;) {
      const auto count = ::read(descriptors[0], bytes.data(), bytes.size());
      if (count < 0) { HOST_CHECK(errno == EAGAIN || errno == EWOULDBLOCK); break; }
      HOST_CHECK(count > 0);
      decoder.feed(std::string_view(bytes.data(), static_cast<std::size_t>(count)), [&](std::string_view line) {
        auto frame = parse_line(line);
        if (frame.contains("report_sequence")) { report_bytes += line.size(); report_sequence = frame.at("report_sequence").get<std::uint64_t>(); }
        frames.push_back(std::move(frame));
      });
    }
  }
  void until(const std::function<bool()> &done) {
    const auto deadline = Clock::now() + std::chrono::seconds(3);
    while (!done() && Clock::now() < deadline) { peer.poll(); std::vector<pollfd> none; host.poll(none, 1); flush(); }
    HOST_CHECK(done());
  }
  const Json *response(const std::string &id) const {
    for (const auto &frame : frames) if (frame.contains("id") && frame.at("id") == id && frame.contains("ok")) return &frame;
    return nullptr;
  }
  void request(const std::string &id, const std::string &operation, const Json &parameters = Json::object(), unsigned timeout = 2000) {
    host.receive({{"version", 1}, {"id", id}, {"operation", operation}, {"parameters", parameters}, {"timeout_ms", timeout}});
  }
  void open() {
    request("open", "open", {{"peer", {{"adapter", "/org/bluez/hci0"}, {"address", "AA:BB:CC:DD:EE:FF"}, {"address_type", "random"}}},
      {"connection", "borrowed"}, {"bus_address", address}});
    until([&] { return response("open"); }); HOST_CHECK(response("open")->at("ok") == true);
    sender = response("open")->at("result").at("sender").get<std::string>();
    HOST_CHECK(sender != peer.sender());
  }
  void close() {
    request("close", "close"); until([&] { return host.finished(); }); flush();
    HOST_CHECK(host.status() == 0 && response("close") && response("close")->at("ok") == true && !disconnects);
  }
};
inline void invariants(const std::string &address) {
  {
    Fixture f(address); f.open();
    f.request("1", "discover"); f.until([&] { return f.response("1"); });
    HOST_CHECK(f.response("1")->at("result").at("characteristics").size() == 1 && f.peer.calls == 2);
    f.request("2", "read", {{"address", gatt_address}}); f.until([&] { return f.response("2"); });
    HOST_CHECK(f.response("2")->at("result") == Json({{"type", "bytes"}, {"base64", "Af8="}}));
    f.request("3", "write", {{"address", gatt_address}, {"value", {{"type", "bytes"}, {"base64", "Ag=="}}}});
    f.until([&] { return f.response("3"); }); HOST_CHECK(f.response("3")->at("ok") == true);
    f.request("4", "health"); f.until([&] { return f.response("4"); });
    HOST_CHECK(f.response("4")->at("result") == Json({{"connected", true}, {"services_resolved", true}}));
    f.close();
  }
  {
    Fixture f(address); f.open();
    f.request("1", "subscribe", {{"address", gatt_address}, {"mode", "notify"}, {"queue_limit", 2}});
    f.until([&] { return f.response("1"); }); HOST_CHECK(f.response("1")->at("ok") == true && f.notifications == 1);
    f.hold = "ReadValue"; f.request("2", "read", {{"address", gatt_address}}); f.until([&] { return bool(f.held); });
    f.request("3", "unsubscribe", {{"subscription_id", "1"}});
    f.until([&] { return f.response("3"); }); HOST_CHECK(f.stops == 1 && f.response("3")->at("ok") == true && !f.response("2"));
    f.request("4", "discover", Json::object(), 20); f.until([&] { return f.response("4"); });
    HOST_CHECK(f.response("4")->at("error").at("code") == "timeout" && !f.response("2"));
    // Completing the independent held read keeps ordinary work usable.
    Message response(dbus_message_new_method_return(f.held.get())); const unsigned char *bytes = nullptr;
    HOST_CHECK(dbus_message_append_args(response.get(), DBUS_TYPE_ARRAY, DBUS_TYPE_BYTE, &bytes, 0, DBUS_TYPE_INVALID));
    f.peer.send(std::move(response)); f.until([&] { return f.response("2"); }); f.close();
  }
  {
    Fixture f(address); f.open(); f.hold = "StartNotify";
    f.request("1", "subscribe", {{"address", gatt_address}, {"mode", "notify"}, {"queue_limit", 2}});
    f.until([&] { return bool(f.held); }); f.close();
    HOST_CHECK(f.stops == 1 && f.response("1") && f.response("1")->at("ok") == false);
  }
  {
    Fixture f(address); f.open();
    f.request("1", "subscribe", {{"address", gatt_address}, {"mode", "auto"}, {"queue_limit", 2}});
    f.until([&] { return f.response("1"); });
    for (unsigned i = 0; i < 5; ++i) f.peer.changed({{"Value", "ay", Json::array({i})}});
    f.until([&] { return f.stops == 1 && !f.frames.empty() && f.frames.back().value("event", "") == "stream_retired"; });
    HOST_CHECK(f.report_sequence == 2 && f.frames[f.frames.size() - 2].at("event") == "error" &&
      f.frames[f.frames.size() - 2].at("metadata").at("error").at("code") == "queue_overflow");
    f.host.receive({{"version", 1}, {"event", "report_ack"}, {"session_generation", session_generation},
      {"report_sequence", f.report_sequence}, {"acknowledged_bytes", f.report_bytes}});
    f.request("2", "read", {{"address", gatt_address}}); f.until([&] { return f.response("2"); });
    HOST_CHECK(f.response("2")->at("ok") == true); f.close();
  }
  {
    Fixture f(address); f.open(); const auto calls = f.peer.calls;
    f.request("1", "discover", {{"cursor", std::string(32, 'f')}}); f.until([&] { return f.response("1"); });
    HOST_CHECK(f.response("1")->at("error").at("code") == "invalid_cursor" && f.peer.calls == calls);
    f.peer.changed({{"Flags", "as", Json::array({"read", "write", "notify"})}}); f.peer.barrier();
    f.request("2", "discover"); f.until([&] { return f.response("2"); });
    HOST_CHECK(f.response("2")->at("ok") == true && f.response("2")->at("result").at("generation") == 2); f.close();
  }
  {
    Fixture f(address); f.open(); Message pair; std::string agent; unsigned registration = 0;
    f.peer.on_other = [&](DBusMessage *request) {
      const std::string method = dbus_message_get_member(request);
      HOST_CHECK(f.sender == dbus_message_get_sender(request));
      if (method == "RegisterAgent") {
        const char *path = nullptr, *capability = nullptr;
        HOST_CHECK(dbus_message_get_args(request, nullptr, DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_STRING, &capability, DBUS_TYPE_INVALID));
        HOST_CHECK(std::string(capability) == "DisplayYesNo"); agent = path; ++registration;
      } else if (method == "Pair") { pair.reset(dbus_message_ref(request)); return; }
      else { HOST_CHECK(method == "UnregisterAgent" && registration == 1); --registration; }
      f.peer.empty_reply(request);
    };
    f.request("1", "pair", {{"capability", "DisplayYesNo"}}); f.until([&] { return bool(pair); });
    pairing_test::AgentCall prompt(f.peer, f.sender, agent, "RequestAuthorization", "o");
    f.until([&] { return f.frames.back().value("event", "") == "agent_challenge"; });
    const auto challenge = f.frames.back().at("challenge").at("id");
    f.request("agent-2", "agent_reply", {{"challenge_id", challenge}, {"decision", {{"action", "accept"}}}});
    f.until([&] { return f.response("agent-2") && prompt.completed(); });
    HOST_CHECK(f.response("agent-2")->at("ok") == true && !prompt.rejected());
    f.peer.empty_reply(pair.get()); f.until([&] { return f.response("1"); });
    HOST_CHECK(!registration && f.response("1")->at("ok") == true); f.close();
  }

  {
    // BlueZ drops the link after a rejected Pair. Link loss while an explicit
    // close owns cleanup cannot turn that completed close into a failure.
    Fixture f(address); f.open(); Message pair, unregister;
    f.peer.on_other = [&](DBusMessage *request) {
      const std::string method = dbus_message_get_member(request);
      if (method == "Pair") { pair.reset(dbus_message_ref(request)); return; }
      if (method == "UnregisterAgent") { unregister.reset(dbus_message_ref(request)); return; }
      f.peer.empty_reply(request);
    };
    f.request("1", "pair", {{"capability", "DisplayYesNo"}}); f.until([&] { return bool(pair); });
    f.request("close", "close"); f.until([&] { return bool(unregister); });
    f.peer.changed({{"Connected", "b", false}}, device_interface, "/org/bluez/hci0/device");
    for (unsigned turn = 0; turn < 20; ++turn) { f.peer.poll(); std::vector<pollfd> none; f.host.poll(none, 1); f.flush(); }
    f.peer.empty_reply(unregister.get()); f.until([&] { return f.host.finished(); }); f.flush();
    HOST_CHECK(f.response("1") && f.response("1")->at("ok") == false);
    HOST_CHECK(f.response("close") && f.response("close")->at("ok") == true && f.response("close")->at("result").is_null());
    HOST_CHECK(f.host.status() == 0 && !f.disconnects);
  }
  {
    Fixture f(address); f.open();
    f.request("1", "subscribe", {{"address", gatt_address}, {"mode", "auto"}, {"queue_limit", 2}});
    f.until([&] { return f.response("1"); });
    f.request("2", "unsubscribe", {{"subscription_id", "1"}, {"generation", 1}});
    f.until([&] { return f.response("2"); });
    HOST_CHECK(f.response("2")->at("error").at("code") == "invalid_subscription" && f.stops == 0);
    f.close(); HOST_CHECK(f.stops == 1);
  }
  {
    Fixture f(address); f.open(); const auto calls = f.peer.calls;
    for (unsigned id = 1; id <= 64; ++id) f.request(std::to_string(id), "health");
    // Close is separately reserved even while every ordinary reply slot is held.
    f.close(); HOST_CHECK(f.peer.calls == calls);
    for (unsigned id = 1; id <= 64; ++id) HOST_CHECK(f.response(std::to_string(id))->at("error").at("code") == "disconnected");
  }

}
} // namespace host_test
