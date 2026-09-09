// SPDX-License-Identifier: Apache-2.0
// Owns one private sender and pins org.bluez to one unique service identity.
// The enclosing event loop retains this object through callbacks and poll().
#pragma once
#include "bus.hpp"

namespace wotex::ble {
class BlueZService {
  using Callback = std::function<void(const char *)>;
  struct State : std::enable_shared_from_this<State> {
    Bus bus;
    Callback ready, lost;
    std::string owner;
    Deadline deadline;
    std::uint64_t changes = 0;
    bool started = false, active = true, established = false;
    explicit State(const std::string &address) : bus(address) {}

    static Message method(const char *member) {
      return Message(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS,
                                                  DBUS_INTERFACE_DBUS, member));
    }
    void close() {
      active = false; ready = {}; lost = {}; owner.clear(); bus.close();
    }
    void fail(const char *reason) {
      if (!active) return;
      auto callback = established ? std::move(lost) : std::move(ready);
      close();
      if (callback) callback(reason);
    }
    void resolve() {
      auto request = method("GetNameOwner");
      const char *name = "org.bluez";
      if (!request || !dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID)) {
        fail("resource_limit"); return;
      }
      const auto revision = changes;
      std::weak_ptr<State> weak = shared_from_this();
      if (!bus.call(request.get(), "s", deadline, [weak, revision](BusReply reply) {
        const auto state = weak.lock();
        if (!state || !state->active) return;
        if (reply.error) { state->fail(reply.error); return; }
        if (revision != state->changes) { state->fail("disconnected"); return; }
        const char *name = nullptr;
        if (!dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID) ||
            !name || name[0] != ':' || !dbus_validate_bus_name(name, nullptr) || name == state->bus.unique_name()) {
          state->fail("invalid_response"); return;
        }
        state->owner = name;
        state->established = true;
        auto callback = std::move(state->ready);
        if (callback) callback(nullptr);
      })) fail("resource_limit");
    }
    void watch() {
      std::weak_ptr<State> weak = shared_from_this();
      bus.listen(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "NameOwnerChanged", "sss",
        [weak](DBusMessage *message) {
          const auto state = weak.lock();
          if (!state || !state->active) return;
          const char *name = nullptr, *before = nullptr, *after = nullptr;
          if (!dbus_message_get_args(message, nullptr, DBUS_TYPE_STRING, &name,
              DBUS_TYPE_STRING, &before, DBUS_TYPE_STRING, &after, DBUS_TYPE_INVALID)) {
            state->fail("invalid_response"); return;
          }
          if (std::string(name) != "org.bluez") return;
          if ((!std::string(before).empty() && (before[0] != ':' || !dbus_validate_bus_name(before, nullptr))) ||
              (!std::string(after).empty() && (after[0] != ':' || !dbus_validate_bus_name(after, nullptr)))) {
            state->fail("invalid_response"); return;
          }
          if (state->established || state->changes == std::numeric_limits<std::uint64_t>::max())
            state->fail("disconnected");
          else ++state->changes;
        });
      auto request = method("AddMatch");
      const char *rule = "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'";
      if (!request || !dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &rule, DBUS_TYPE_INVALID)) {
        fail("resource_limit"); return;
      }
      if (!bus.call(request.get(), "", deadline, [weak](BusReply reply) {
        const auto state = weak.lock();
        if (!state || !state->active) return;
        if (reply.error) state->fail(reply.error);
        else state->resolve();
      })) fail("resource_limit");
    }
  };
  std::shared_ptr<State> state_;
public:
  explicit BlueZService(const std::string &address) : state_(std::make_shared<State>(address)) {}
  BlueZService(const BlueZService &) = delete;
  BlueZService &operator=(const BlueZService &) = delete;
  ~BlueZService() { close(); }

  bool start(Deadline deadline, Callback ready, Callback lost) {
    auto &state = *state_;
    if (state.started || !state.active || !ready || !lost) return false;
    state.started = true; state.deadline = deadline;
    state.ready = std::move(ready); state.lost = std::move(lost);
    std::weak_ptr<State> weak = state_;
    if (!state.bus.hello(deadline, [weak](BusReply reply) {
      const auto state = weak.lock();
      if (!state || !state->active) return;
      if (reply.error) state->fail(reply.error);
      else state->watch();
    })) state.fail("timeout");
    return true;
  }
  void poll(std::vector<pollfd> &extra, int wait_ms) {
    state_->bus.poll(extra, wait_ms);
    if (const auto error = state_->bus.failure()) state_->fail(error);
  }
  void close() { state_->close(); }
  Bus &bus() { return state_->bus; }
  const std::string &owner() const { return state_->owner; }
  bool active() const { return state_->active; }
};
} // namespace wotex::ble
