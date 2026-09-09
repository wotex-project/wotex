// SPDX-License-Identifier: Apache-2.0
// Live ObjectManager and explicit connection ownership. Metadata-only start
// does not change a radio link. connect admits the caller's owned/borrowed mode.
#pragma once
#include "objects.hpp"
#include "service.hpp"
#include <optional>

namespace wotex::ble {
class LiveDiscovery {
  using Callback = std::function<void(const char *)>;
  struct State : std::enable_shared_from_this<State> {
    BlueZService service;
    NativePeer peer;
    std::optional<Discovery> snapshot;
    Callback pending, lost;
    Callback close_done;
    std::function<void()> changed;
    Deadline deadline;
    Deadline cleanup_deadline;
    std::string terminal;
    std::uint64_t revision = 0, generation = 1;
    unsigned attempts = 0;
    bool active = true, started = false, watched = false, dirty = false, linked = false;
    bool connecting = false, owned_mode = false, connect_attempted = false;
    bool link_owned = false, waiting_state = false, delivered = false, closing = false;

    State(const std::string &address, NativePeer peer) : service(address), peer(std::move(peer)) {}
    void force_close() {
      active = false; pending = {}; lost = {}; changed = {}; snapshot.reset(); service.close();
      closing = false; link_owned = false; close_done = {};
    }
    void finish_close() {
      auto callback = std::exchange(close_done, {});
      force_close();
      if (callback) callback(nullptr);
    }
    void close(Callback callback = {}, Deadline stop_by = Clock::now() + std::chrono::milliseconds(500)) {
      if (closing) { cleanup_deadline = std::min(cleanup_deadline, stop_by); return; }
      if (!active) { if (callback) callback(nullptr); return; }
      active = false; closing = true; waiting_state = false;
      pending = {}; lost = {}; changed = {}; close_done = std::move(callback);
      cleanup_deadline = std::min(stop_by, Clock::now() + std::chrono::milliseconds(500));
      service.bus().cancel_calls();
      if (Clock::now() >= cleanup_deadline || !link_owned || !snapshot || service.owner().empty() || service.bus().failure()) {
        finish_close(); return;
      }
      Message request(dbus_message_new_method_call(service.owner().c_str(), snapshot->device_path.c_str(),
                                                   device_interface, "Disconnect"));
      std::weak_ptr<State> weak = shared_from_this();
      if (!service.bus().call(request.get(), "", cleanup_deadline, [weak](BusReply) {
        const auto state = weak.lock();
        if (state && state->closing) state->finish_close();
      })) finish_close();
    }
    void fail(const char *reason) {
      if (!active) return;
      terminal = reason;
      auto operation = std::move(pending);
      auto callback = delivered ? std::move(lost) : Callback{};
      close([operation = std::move(operation), callback = std::move(callback), reason = terminal](auto) {
        if (operation) operation(reason.c_str());
        if (callback) callback(reason.c_str());
      });
    }
    void invalidate() {
      if (revision == std::numeric_limits<std::uint64_t>::max()) { fail("generation_exhausted"); return; }
      ++revision; dirty = true;
      auto callback = changed;
      if (callback) callback();
      if (active && waiting_state) { waiting_state = false; attempts = 0; query(); }
    }
    void complete() {
      delivered = true;
      auto callback = std::exchange(pending, {});
      if (callback) callback(nullptr);
    }
    void advance_connection() {
      if (snapshot->connected && snapshot->services_resolved) {
        linked = true; complete(); return;
      }
      if (!owned_mode) { fail(snapshot->connected ? "services_unresolved" : "disconnected"); return; }
      if (snapshot->connected || connect_attempted) { waiting_state = true; return; }
      if (Clock::now() >= deadline) { fail("timeout"); return; }
      // The observed disconnected state and explicit owned mode authorize this
      // attempt's cleanup even when Connect's acknowledgement is lost.
      connect_attempted = true; link_owned = true;
      Message request(dbus_message_new_method_call(service.owner().c_str(), snapshot->device_path.c_str(), device_interface, "Connect"));
      std::weak_ptr<State> weak = shared_from_this();
      if (!service.bus().call(request.get(), "", deadline, [weak](BusReply reply) {
        const auto state = weak.lock();
        if (!state || !state->active) return;
        if (reply.error) {
          if (std::string(reply.error) == "remote_error") state->link_owned = false;
          state->fail(reply.error); return;
        }
        state->attempts = 0; state->query();
      })) fail(Clock::now() >= deadline ? "timeout" : "resource_limit");
    }
    bool selected(const std::string &path) const {
      if (!snapshot) return false;
      if (path == snapshot->device_path || path == peer.adapter || snapshot->service_paths.count(path)) return true;
      for (const auto &item : snapshot->characteristics)
        if (item.at("service_path") == path || item.at("object_path") == path) return true;
      return false;
    }
    static bool metadata(const std::string &interface, const std::string &name) {
      if (interface == device_interface)
        return name == "Adapter" || name == "Address" || name == "AddressType" ||
               name == "Connected" || name == "ServicesResolved";
      if (interface == service_interface) return name == "Device" || name == "UUID";
      if (interface == characteristic_interface)
        return name == "Service" || name == "UUID" || name == "Handle" || name == "Flags";
      return false;
    }
    void signal(DBusMessage *message) {
      if (!active) return;
      try {
        ObjectReader reader;
        if (dbus_message_is_signal(message, "org.freedesktop.DBus.Properties", "PropertiesChanged")) {
          auto update = reader.changed(message);
          bool relevant = !update.values.empty();
          for (const auto &name : update.invalidated) relevant = relevant || metadata(update.interface, name);
          if (!relevant) return;
          const auto *path = dbus_message_get_path(message);
          if (linked && path && snapshot->device_path == path && update.interface == device_interface &&
              ((update.values.contains("Connected") && !update.values.at("Connected").get<bool>()) ||
               (update.values.contains("ServicesResolved") && !update.values.at("ServicesResolved").get<bool>()))) {
            fail("disconnected"); return;
          }
        } else if (dbus_message_is_signal(message, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded")) {
          const auto update = reader.added(message);
          if (update.values().begin().value().empty()) return;
        } else {
          const auto update = reader.removed(message);
          const bool relevant = update.interfaces.count(adapter_interface) || update.interfaces.count(device_interface) ||
                                update.interfaces.count(service_interface) || update.interfaces.count(characteristic_interface);
          if (!relevant) return;
          if (linked && selected(update.path)) { fail("disconnected"); return; }
        }
        invalidate();
      } catch (const InvalidObjects &error) { fail(error.what()); }
    }
    void query() {
      if (!active || !pending) return;
      if (Clock::now() >= deadline) { fail("timeout"); return; }
      if (++attempts > 4) { fail("snapshot_unstable"); return; }
      Message request(dbus_message_new_method_call(service.owner().c_str(), "/",
          "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"));
      const auto observed = revision;
      std::weak_ptr<State> weak = shared_from_this();
      if (!service.bus().call(request.get(), "a{oa{sa{sv}}}", deadline, [weak, observed](BusReply reply) {
        const auto state = weak.lock();
        if (!state || !state->active) return;
        if (reply.error) { state->fail(reply.error); return; }
        try {
          // Validate even a raced response; revision changes do not license
          // malformed peer data or a second allocation budget.
          auto objects = ObjectReader().read(reply.message.get());
          auto current = discovery(objects, state->peer, state->generation);
          if (observed != state->revision) { state->query(); return; }
          if (state->snapshot && current.device_path != state->snapshot->device_path) {
            state->fail("peer_changed"); return;
          }
          if (state->linked && (!current.connected || !current.services_resolved)) {
            state->fail("disconnected"); return;
          }
          if (state->snapshot && (state->dirty || current.characteristics != state->snapshot->characteristics ||
                                  current.service_paths != state->snapshot->service_paths)) {
            if (state->generation == std::numeric_limits<std::uint64_t>::max()) {
              state->fail("generation_exhausted"); return;
            }
            ++state->generation;
            for (auto &item : current.characteristics) item["generation"] = state->generation;
          }
          state->snapshot = std::move(current); state->dirty = false;
          if (state->connecting && !state->delivered) state->advance_connection();
          else state->complete();
        } catch (const InvalidObjects &error) { state->fail(error.what()); }
      })) fail(Clock::now() >= deadline ? "timeout" : "resource_limit");
    }
    void match(unsigned index) {
      if (index == 2) { watched = true; query(); return; }
      const std::string rule = "type='signal',sender='" + service.owner() + "',interface='" +
        (index ? "org.freedesktop.DBus.ObjectManager" : "org.freedesktop.DBus.Properties") + "'";
      Message request(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "AddMatch"));
      const char *value = rule.c_str();
      if (!request || !dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID)) {
        fail("resource_limit"); return;
      }
      std::weak_ptr<State> weak = shared_from_this();
      if (!service.bus().call(request.get(), "", deadline, [weak, index](BusReply reply) {
        const auto state = weak.lock();
        if (!state || !state->active) return;
        if (reply.error) state->fail(reply.error);
        else state->match(index + 1);
      })) fail(Clock::now() >= deadline ? "timeout" : "resource_limit");
    }
    void watch() {
      std::weak_ptr<State> weak = shared_from_this();
      const auto callback = [weak](DBusMessage *message) {
        const auto state = weak.lock();
        if (state) state->signal(message);
      };
      service.bus().listen(service.owner(), "", "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as", callback);
      service.bus().listen(service.owner(), "/", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", "oa{sa{sv}}", callback);
      service.bus().listen(service.owner(), "/", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved", "oas", callback);
      match(0);
    }
  };
  std::shared_ptr<State> state_;
public:
  LiveDiscovery(const std::string &address, NativePeer peer)
    : state_(std::make_shared<State>(address, std::move(peer))) {}
  LiveDiscovery(const LiveDiscovery &) = delete;
  LiveDiscovery &operator=(const LiveDiscovery &) = delete;
  ~LiveDiscovery() { state_->force_close(); }
  bool start(Deadline deadline, Callback ready, Callback lost, std::function<void()> changed) {
    auto &state = *state_;
    if (!state.active || state.started || !ready || !lost || !changed) return false;
    state.started = true; state.deadline = deadline; state.pending = std::move(ready);
    state.lost = std::move(lost); state.changed = std::move(changed);
    std::weak_ptr<State> weak = state_;
    return state.service.start(deadline, [weak](const char *error) {
      const auto state = weak.lock();
      if (!state || !state->active) return;
      if (error) state->fail(error);
      else state->watch();
    }, [weak](const char *error) {
      const auto state = weak.lock();
      if (state) state->fail(error);
    });
  }
  bool connect(bool owned, Deadline deadline, Callback ready, Callback lost) {
    if (!state_->active || state_->started) return false;
    state_->connecting = true; state_->owned_mode = owned;
    return start(deadline, std::move(ready), std::move(lost), [] {});
  }
  bool refresh(Deadline deadline, Callback callback) {
    auto &state = *state_;
    if (!state.active || !state.watched || !state.snapshot || state.pending || !callback) return false;
    state.deadline = deadline; state.pending = std::move(callback); state.attempts = 0; state.query();
    return true;
  }
  bool accept_link() {
    auto &state = *state_;
    if (!state.active || state.dirty || state.pending || !state.snapshot ||
        !state.snapshot->connected || !state.snapshot->services_resolved) return false;
    state.linked = true; return true;
  }
  void poll(std::vector<pollfd> &extra, int wait_ms) {
    auto &state = *state_;
    if (state.closing || (state.connecting && !state.delivered)) {
      const auto deadline = state.closing ? state.cleanup_deadline : state.deadline;
      const auto remaining = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now()).count();
      wait_ms = std::min(wait_ms, static_cast<int>(std::clamp<std::int64_t>(remaining, 0, 1000)));
    }
    state.service.poll(extra, wait_ms);
    if (state.closing && (Clock::now() >= state.cleanup_deadline || !state.service.active())) state.finish_close();
    else if (state.active && state.connecting && !state.delivered && Clock::now() >= state.deadline) state.fail("timeout");
  }
  void close() { state_->close(); }
  void close(Deadline stop_by) { state_->close({}, stop_by); }
  const std::string &failure() const { return state_->terminal; }
  const NativePeer &peer() const { return state_->peer; }
  bool closing() const { return state_->closing; }
  bool link_owned() const { return state_->link_owned; }
  bool active() const { return state_->active; }
  bool stale() const { return state_->dirty; }
  std::uint64_t generation() const { return state_->generation; }
  const Discovery *snapshot() const { return state_->snapshot ? &*state_->snapshot : nullptr; }
  Bus &bus() { return state_->service.bus(); }
  const std::string &owner() const { return state_->service.owner(); }
};
} // namespace wotex::ble
