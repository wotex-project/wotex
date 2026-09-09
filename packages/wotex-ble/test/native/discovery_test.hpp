// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "discovery.hpp"
#include "objects_test.hpp"

namespace discovery_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) { if (!value) throw std::runtime_error("live discovery assertion at line " + std::to_string(line)); }
#define DISCOVERY_CHECK(value) ::discovery_test::verify((value), __LINE__)
class Peer {
  DBusConnection *connection_;
  static DBusHandlerResult receive(DBusConnection *, DBusMessage *message, void *data) noexcept {
    auto &self = *static_cast<Peer *>(data);
    if (!dbus_message_is_method_call(message, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"))
      return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    try {
      ++self.calls;
      DISCOVERY_CHECK(dbus_message_has_path(message, "/") && dbus_message_has_signature(message, ""));
      if (self.on_query) self.on_query(message);
      else self.reply(message);
    } catch (...) { self.failed = true; }
    return DBUS_HANDLER_RESULT_HANDLED;
  }
public:
  std::vector<object_test::Object> objects = object_test::baseline;
  unsigned calls = 0;
  bool failed = false;
  std::function<void(DBusMessage *)> on_query;
  explicit Peer(const std::string &address, bool own = true) {
    connection_ = dbus_connection_open_private(address.c_str(), nullptr); DISCOVERY_CHECK(connection_);
    dbus_connection_set_exit_on_disconnect(connection_, false);
    DISCOVERY_CHECK(dbus_bus_register(connection_, nullptr));
    DISCOVERY_CHECK(dbus_connection_add_filter(connection_, receive, this, nullptr));
    if (own) DISCOVERY_CHECK(dbus_bus_request_name(connection_, "org.bluez", DBUS_NAME_FLAG_DO_NOT_QUEUE, nullptr) == DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER);
  }
  ~Peer() {
    dbus_connection_remove_filter(connection_, receive, this);
    dbus_connection_close(connection_); dbus_connection_unref(connection_);
  }
  void release() { DISCOVERY_CHECK(dbus_bus_release_name(connection_, "org.bluez", nullptr) == DBUS_RELEASE_NAME_REPLY_RELEASED); }
  void barrier() {
    Message request(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "GetId"));
    Message reply(dbus_connection_send_with_reply_and_block(connection_, request.get(), 1000, nullptr));
    DISCOVERY_CHECK(reply && dbus_message_get_type(reply.get()) == DBUS_MESSAGE_TYPE_METHOD_RETURN &&
                    dbus_message_has_signature(reply.get(), "s"));
  }
  std::string sender() const { return dbus_bus_get_unique_name(connection_); }
  void send(Message message) {
    DISCOVERY_CHECK(dbus_connection_send(connection_, message.get(), nullptr));
    dbus_connection_flush(connection_);
  }
  void reply(DBusMessage *request) {
    auto response = object_test::message(objects);
    DISCOVERY_CHECK(dbus_message_set_destination(response.get(), dbus_message_get_sender(request)));
    DISCOVERY_CHECK(dbus_message_set_reply_serial(response.get(), dbus_message_get_serial(request)));
    send(std::move(response));
  }
  void changed(const std::vector<object_test::Property> &values, const std::string &interface = characteristic_interface,
               const std::string &path = "/org/bluez/hci0/device/service/char", const std::string &destination = "") {
    auto message = object_test::changed_message(values, {}, interface);
    DISCOVERY_CHECK(dbus_message_set_path(message.get(), path.c_str()));
    if (!destination.empty()) DISCOVERY_CHECK(dbus_message_set_destination(message.get(), destination.c_str()));
    send(std::move(message));
  }
  void poll() {
    DISCOVERY_CHECK(dbus_connection_read_write(connection_, 0));
    for (unsigned count = 0; count < 64 && dbus_connection_get_dispatch_status(connection_) == DBUS_DISPATCH_DATA_REMAINS; ++count)
      dbus_connection_dispatch(connection_);
    DISCOVERY_CHECK(!failed);
  }
};
inline void until(Peer &peer, LiveDiscovery &owner, const std::function<bool()> &done) {
  const auto deadline = Clock::now() + std::chrono::seconds(3);
  while (!done() && Clock::now() < deadline) {
    peer.poll(); std::vector<pollfd> none; owner.poll(none, 1);
  }
  DISCOVERY_CHECK(done());
}
inline void opening(Peer &peer, LiveDiscovery &owner, std::string &failure, unsigned &changes) {
  bool ready = false;
  DISCOVERY_CHECK(owner.start(Clock::now() + std::chrono::seconds(2), [&](const char *error) {
    if (error) failure = error;
    ready = true;
  }, [&](const char *error) { failure = error; }, [&] { ++changes; }));
  until(peer, owner, [&] { return ready; });
}
inline void refresh(Peer &peer, LiveDiscovery &owner, std::string &failure) {
  bool ready = false;
  DISCOVERY_CHECK(owner.refresh(Clock::now() + std::chrono::seconds(2), [&](const char *error) {
    if (error) failure = error;
    ready = true;
  }));
  until(peer, owner, [&] { return ready; });
}
inline void invariants(const std::string &address) {
  // WBL-V03: the signal subscription is effective before the first snapshot.
  {
    Peer peer(address);
    peer.on_query = [&](DBusMessage *request) {
      if (peer.calls == 1) {
        peer.changed({{"Handle", "q", 23}});
        peer.reply(request); // stale snapshot, delivered after the signal
        peer.objects[3].second[0].second[2].value = 23;
      } else peer.reply(request);
    };
    LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0;
    opening(peer, owner, failure, changes);
    DISCOVERY_CHECK(failure.empty() && peer.calls == 2 && changes == 1 && owner.generation() == 1);
    DISCOVERY_CHECK(owner.snapshot() && owner.snapshot()->characteristics[0]["handle"] == 23 && owner.accept_link());
    DISCOVERY_CHECK(owner.bus().listener_count() == 4 && owner.bus().pending_count() == 0);
    DISCOVERY_CHECK(owner.owner() == peer.sender() && owner.owner() != owner.bus().unique_name());
    refresh(peer, owner, failure); DISCOVERY_CHECK(owner.generation() == 1 && failure.empty());

    Peer foreign(address, false);
    foreign.changed({{"Connected", "b", false}}, device_interface, "/org/bluez/hci0/device", owner.bus().unique_name());
    // This foreign-sender round trip proves the daemon routed its preceding
    // forged signal before the owner's refresh is submitted.
    foreign.barrier();
    refresh(peer, owner, failure);
    DISCOVERY_CHECK(failure.empty() && changes == 1 && owner.generation() == 1);
    peer.changed({{"Value", "ay", Json::array({1})}});
    refresh(peer, owner, failure); DISCOVERY_CHECK(failure.empty() && changes == 1 && owner.generation() == 1);

    peer.changed({{"Flags", "as", Json::array({"read", "notify"})}});
    until(peer, owner, [&] { return changes == 2; });
    DISCOVERY_CHECK(owner.stale() && !owner.accept_link());
    // A change restored before refresh still invalidates the old generation.
    refresh(peer, owner, failure); DISCOVERY_CHECK(failure.empty() && owner.generation() == 2 && !owner.stale());
    peer.objects[3].second[0].second[2].value = 24;
    refresh(peer, owner, failure); DISCOVERY_CHECK(failure.empty() && owner.generation() == 3);
    peer.release();
    until(peer, owner, [&] { return !owner.active(); });
    DISCOVERY_CHECK(failure == "owner_changed" && !owner.snapshot() && owner.bus().pending_count() == 0);
    DISCOVERY_CHECK(owner.bus().listener_count() == 0 && owner.bus().watch_count() == 0 && owner.bus().timeout_count() == 0);
  }
  // Four independently raced replies exhaust one operation, not its deadline.
  {
    Peer peer(address);
    peer.on_query = [&](DBusMessage *request) { peer.changed({{"Handle", "q", 17}}); peer.reply(request); };
    LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0;
    opening(peer, owner, failure, changes);
    DISCOVERY_CHECK(failure == "snapshot_unstable" && peer.calls == 4 && changes == 4 && !owner.active());
  }
  // Selected Device1 identity never retargets, even to an otherwise valid path.
  {
    Peer peer(address); LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0; opening(peer, owner, failure, changes);
    peer.objects[1].first = "/different_device";
    refresh(peer, owner, failure); DISCOVERY_CHECK(failure == "peer_changed" && !owner.active());
  }
  for (bool signal : {false, true}) {
    Peer peer(address); LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0; opening(peer, owner, failure, changes);
    DISCOVERY_CHECK(owner.accept_link());
    if (signal) {
      peer.changed({{"ServicesResolved", "b", false}}, device_interface, "/org/bluez/hci0/device");
      until(peer, owner, [&] { return !owner.active(); });
    } else { peer.objects[1].second[0].second[3].value = false; refresh(peer, owner, failure); }
    DISCOVERY_CHECK(failure == "disconnected" && !owner.active());
  }
  // A selected service with no characteristic still owns a topology identity.
  {
    Peer peer(address); peer.objects.resize(3);
    LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0; opening(peer, owner, failure, changes);
    DISCOVERY_CHECK(owner.accept_link() && owner.snapshot()->characteristics.empty());
    // Construct the selected empty-service path in the actual signal body.
    Message message(dbus_message_new_signal("/", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved"));
    DBusMessageIter root, array; dbus_message_iter_init_append(message.get(), &root);
    object_test::string(root, "/org/bluez/hci0/device/service", DBUS_TYPE_OBJECT_PATH);
    DISCOVERY_CHECK(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "s", &array));
    object_test::string(array, service_interface); DISCOVERY_CHECK(dbus_message_iter_close_container(&root, &array));
    peer.send(std::move(message)); until(peer, owner, [&] { return !owner.active(); });
    DISCOVERY_CHECK(failure == "disconnected");
  }
  // A malformed signal from the selected sender closes the generation; an
  // unknown property of the same signature remains an ignored extension.
  {
    Peer peer(address); LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0; opening(peer, owner, failure, changes);
    peer.changed({{"Unknown", "u", 42}});
    refresh(peer, owner, failure); DISCOVERY_CHECK(changes == 0 && failure.empty());
    peer.changed({{"Handle", "u", 17}});
    until(peer, owner, [&] { return !owner.active(); });
    DISCOVERY_CHECK(failure == "invalid_response" && changes == 0);
  }
  // The change callback can close its owner without retaining a late query.
  {
    Peer peer(address); LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    bool ready = false; unsigned changes = 0;
    DISCOVERY_CHECK(owner.start(Clock::now() + std::chrono::seconds(2), [&](const char *error) {
      DISCOVERY_CHECK(!error); ready = true;
    }, [](auto) { throw std::runtime_error("closed owner received terminal callback"); }, [&] {
      owner.close(); ++changes;
    }));
    until(peer, owner, [&] { return ready; });
    peer.changed({{"Handle", "q", 23}});
    until(peer, owner, [&] { return !owner.active(); });
    DISCOVERY_CHECK(changes == 1 && owner.bus().pending_count() == 0 && owner.bus().listener_count() == 0);
  }
  // Deadline/close cancel a query without waiting for its peer's late response.
  for (bool timeout : {false, true}) {
    Peer peer(address); LiveDiscovery owner(address, NativePeer::from(object_test::peer_fields));
    std::string failure; unsigned changes = 0; opening(peer, owner, failure, changes);
    Message held;
    peer.on_query = [&](DBusMessage *request) { held.reset(dbus_message_ref(request)); };
    unsigned callbacks = 0;
    std::string operation_error;
    DISCOVERY_CHECK(owner.refresh(Clock::now() + std::chrono::milliseconds(50), [&](const char *error) {
      operation_error = error ? error : "unexpected_success"; ++callbacks;
    }));
    DISCOVERY_CHECK(!owner.refresh(Clock::now() + std::chrono::seconds(1), [](auto) {}));
    until(peer, owner, [&] { return held != nullptr; });
    if (timeout) until(peer, owner, [&] { return !owner.active(); });
    else { owner.close(); owner.close(); }
    peer.reply(held.get()); std::vector<pollfd> none; owner.poll(none, 1);
    DISCOVERY_CHECK(callbacks == unsigned(timeout) && !owner.snapshot() && owner.bus().pending_count() == 0);
    if (timeout && operation_error != "timeout") throw std::runtime_error("query deadline: " + operation_error);
    DISCOVERY_CHECK(owner.bus().listener_count() == 0 && owner.bus().watch_count() == 0 && owner.bus().timeout_count() == 0);
  }
}
} // namespace discovery_test
