// SPDX-License-Identifier: Apache-2.0
// One private libdbus connection and its event-loop registrations. The owner
// enters this object from one thread, keeps it alive through callbacks, and may
// close it explicitly. No shared bus, blocking call or process-global exit hook.
#pragma once
#include <dbus/dbus.h>
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <limits>
#include <memory>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace wotex::ble {
using Clock = std::chrono::steady_clock;
using Deadline = Clock::time_point;
struct MessageDelete { void operator()(DBusMessage *value) const { if (value) dbus_message_unref(value); } };
using Message = std::unique_ptr<DBusMessage, MessageDelete>;
struct BusReply { const char *error; Message message; };
using BusCallback = std::function<void(BusReply)>;
using SignalCallback = std::function<void(DBusMessage *)>;

class Bus {
  struct Listener {
    std::string sender, path, interface, member, signature;
    SignalCallback callback;
    bool active = true;
  };
  struct Watch { DBusWatch *value; bool active = true; };
  struct Timeout { DBusTimeout *value; Deadline due; bool active = true; };
  struct Pending {
    Bus *owner;
    DBusPendingCall *value;
    std::string sender;
    std::string signature;
    Deadline deadline;
    BusCallback callback;
    ~Pending() {
      if (value) {
        dbus_pending_call_set_notify(value, nullptr, nullptr, nullptr);
        dbus_pending_call_cancel(value);
        dbus_pending_call_unref(value);
      }
    }
  };
  DBusConnection *connection_ = nullptr;
  std::map<DBusWatch *, std::shared_ptr<Watch>> watches_;
  std::map<DBusTimeout *, std::shared_ptr<Timeout>> timeouts_;
  std::map<DBusPendingCall *, std::unique_ptr<Pending>> pending_;
  std::map<std::uint64_t, std::shared_ptr<Listener>> listeners_;
  std::uint64_t listener_sequence_ = 0;
  std::string unique_name_;
  const char *failure_ = nullptr;
  bool hello_sent_ = false;
  bool filter_installed_ = false;

  static DBusHandlerResult received(DBusConnection *, DBusMessage *message, void *data) noexcept {
    auto &owner = *static_cast<Bus *>(data);
    if (dbus_message_contains_unix_fds(message)) {
      owner.failure_ = "invalid_response";
      return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_SIGNAL)
      return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const char *sender = dbus_message_get_sender(message);
    if (!sender) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    try {
      std::vector<std::shared_ptr<Listener>> selected;
      for (const auto &[unused, listener] : owner.listeners_) {
        (void)unused;
        if (listener->sender == sender &&
            (listener->path.empty() || dbus_message_has_path(message, listener->path.c_str())) &&
            dbus_message_is_signal(message, listener->interface.c_str(), listener->member.c_str()))
          selected.push_back(listener);
      }
      for (const auto &listener : selected) {
        if (!listener->active) continue;
        if (!dbus_message_has_signature(message, listener->signature.c_str())) {
          owner.failure_ = "invalid_response";
          break;
        }
        listener->callback(message);
      }
    } catch (...) { owner.failure_ = "callback_failed"; }
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
  }

  static Deadline after(int interval) {
    return Clock::now() + std::chrono::milliseconds(std::max(0, interval));
  }
  static dbus_bool_t add_watch(DBusWatch *watch, void *data) noexcept {
    auto &owner = *static_cast<Bus *>(data);
    try {
      if (owner.watches_.size() >= 128) { owner.failure_ = "resource_limit"; return false; }
      owner.watches_.emplace(watch, std::make_shared<Watch>(Watch{watch}));
      return true;
    } catch (...) { owner.failure_ = "resource_limit"; return false; }
  }
  static void remove_watch(DBusWatch *watch, void *data) noexcept {
    auto &owner = *static_cast<Bus *>(data);
    auto found = owner.watches_.find(watch);
    if (found != owner.watches_.end()) {
      found->second->active = false;
      owner.watches_.erase(found);
    }
  }
  static void toggle_watch(DBusWatch *, void *) noexcept {}
  static dbus_bool_t add_timeout(DBusTimeout *timeout, void *data) noexcept {
    auto &owner = *static_cast<Bus *>(data);
    try {
      if (owner.timeouts_.size() >= 128) { owner.failure_ = "resource_limit"; return false; }
      owner.timeouts_.emplace(timeout, std::make_shared<Timeout>(
          Timeout{timeout, after(dbus_timeout_get_interval(timeout))}));
      return true;
    } catch (...) { owner.failure_ = "resource_limit"; return false; }
  }
  static void remove_timeout(DBusTimeout *timeout, void *data) noexcept {
    auto &owner = *static_cast<Bus *>(data);
    auto found = owner.timeouts_.find(timeout);
    if (found != owner.timeouts_.end()) {
      found->second->active = false;
      owner.timeouts_.erase(found);
    }
  }
  static void toggle_timeout(DBusTimeout *timeout, void *data) noexcept {
    auto &owner = *static_cast<Bus *>(data);
    auto found = owner.timeouts_.find(timeout);
    if (found != owner.timeouts_.end())
      found->second->due = after(dbus_timeout_get_interval(timeout));
  }
  static void notified(DBusPendingCall *call, void *data) noexcept {
    auto *pending = static_cast<Pending *>(data);
    pending->owner->complete(call);
  }
  void complete(DBusPendingCall *call) noexcept {
    auto found = pending_.find(call);
    if (found == pending_.end()) { failure_ = "invalid_response"; return; }
    auto pending = std::move(found->second);
    pending_.erase(found);
    Message reply(dbus_pending_call_steal_reply(call));
    pending->value = nullptr;
    dbus_pending_call_unref(call);
    const char *error = nullptr;
    if (Clock::now() >= pending->deadline) error = "timeout";
    else if (!reply) error = "invalid_response";
    else if (dbus_message_contains_unix_fds(reply.get())) error = failure_ = "invalid_response";
    else {
      const char *sender = dbus_message_get_sender(reply.get());
      if (!sender || pending->sender != sender) error = "invalid_response";
      else if (dbus_message_get_type(reply.get()) == DBUS_MESSAGE_TYPE_ERROR) error = "remote_error";
      else if (dbus_message_get_type(reply.get()) != DBUS_MESSAGE_TYPE_METHOD_RETURN ||
               pending->signature != dbus_message_get_signature(reply.get())) error = "invalid_response";
    }
    try { pending->callback({error, std::move(reply)}); }
    catch (...) { failure_ = "callback_failed"; }
  }
  bool enqueue(DBusMessage *message, const std::string &signature,
               Deadline deadline, BusCallback callback) {
    if (!connection_ || failure_ || pending_.size() >= 64) return false;
    if (!message || dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_METHOD_CALL ||
        dbus_message_get_serial(message) != 0 || signature.size() > 255 ||
        signature.find('\0') != std::string::npos ||
        !dbus_signature_validate(signature.c_str(), nullptr))
      throw std::invalid_argument("invalid_request");
    const char *destination = dbus_message_get_destination(message);
    if (!destination || (destination[0] != ':' && std::string(destination) != DBUS_SERVICE_DBUS))
      throw std::invalid_argument("invalid_destination");
    auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
    if (remaining < 1 || remaining > 60000) return false;
    auto state = std::make_unique<Pending>(Pending{this, nullptr, destination, signature,
                                                 deadline, std::move(callback)});
    DBusPendingCall *call = nullptr;
    if (!dbus_connection_send_with_reply(connection_, message, &call, static_cast<int>(remaining)) || !call) {
      failure_ = "transport_error";
      return false;
    }
    state->value = call;
    auto *data = state.get();
    pending_.emplace(call, std::move(state));
    if (!dbus_pending_call_set_notify(call, notified, data, nullptr)) {
      pending_.erase(call);
      failure_ = "resource_limit";
      return false;
    }
    return true;
  }
  void dispatch() {
    std::size_t budget = 64;
    while (connection_ && !failure_ && budget-- && dbus_connection_get_dispatch_status(connection_) == DBUS_DISPATCH_DATA_REMAINS) {
      if (dbus_connection_dispatch(connection_) == DBUS_DISPATCH_NEED_MEMORY) {
        failure_ = "resource_limit";
        break;
      }
    }
    if (connection_ && !dbus_connection_get_is_connected(connection_)) failure_ = "disconnected";
  }
public:
  explicit Bus(const std::string &address) {
    int major = 0, minor = 0, micro = 0;
    dbus_get_version(&major, &minor, &micro);
    if (major != 1 || minor != 16 || micro != 2)
      throw std::runtime_error("incompatible_backend");
    const bool local = address.rfind("unix:path=", 0) == 0 || address.rfind("unix:abstract=", 0) == 0;
    if (!local || address.back() == '=' || address.size() > 4096 || address.find("%00") != std::string::npos ||
        std::any_of(address.begin(), address.end(), [](unsigned char c) {
          return c <= 32 || c == ';';
        })) throw std::invalid_argument("invalid_bus_address");
    const auto comma = address.find(',');
    if (comma != std::string::npos) {
      const auto metadata = address.substr(comma);
      if (metadata.size() != 38 || metadata.rfind(",guid=", 0) != 0 ||
          !std::all_of(metadata.begin() + 6, metadata.end(), [](char c) {
            return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
          })) throw std::invalid_argument("invalid_bus_address");
    }
    DBusAddressEntry **entries = nullptr;
    int count = 0;
    if (!dbus_parse_address(address.c_str(), &entries, &count, nullptr))
      throw std::invalid_argument("invalid_bus_address");
    const char *endpoint = count == 1 ? dbus_address_entry_get_value(entries[0], "path") : nullptr;
    if (!endpoint && count == 1) endpoint = dbus_address_entry_get_value(entries[0], "abstract");
    const bool valid = endpoint && *endpoint;
    dbus_address_entries_free(entries);
    if (!valid) throw std::invalid_argument("invalid_bus_address");
    DBusError error = DBUS_ERROR_INIT;
    connection_ = dbus_connection_open_private(address.c_str(), &error);
    dbus_error_free(&error);
    if (!connection_) throw std::runtime_error("transport_unavailable");
    dbus_connection_set_exit_on_disconnect(connection_, false);
    dbus_connection_set_max_message_size(connection_, 4194304);
    dbus_connection_set_max_received_size(connection_, 8388608);
    // Reserve a bounded receive slot; reject any FD before a user callback.
    dbus_connection_set_max_message_unix_fds(connection_, 1);
    // A zero aggregate watermark also stalls messages containing no FDs.
    dbus_connection_set_max_received_unix_fds(connection_, 1);
    if (!dbus_connection_set_watch_functions(connection_, add_watch, remove_watch, toggle_watch, this, nullptr) ||
        !dbus_connection_set_timeout_functions(connection_, add_timeout, remove_timeout, toggle_timeout, this, nullptr)) {
      close();
      throw std::runtime_error("resource_limit");
    }
    filter_installed_ = dbus_connection_add_filter(connection_, received, this, nullptr);
    if (!filter_installed_) { close(); throw std::runtime_error("resource_limit"); }
  }
  Bus(const Bus &) = delete;
  Bus &operator=(const Bus &) = delete;
  ~Bus() { close(); }

  bool hello(Deadline deadline, BusCallback callback) {
    if (hello_sent_) return false;
    hello_sent_ = true;
    Message request(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS,
                                                DBUS_INTERFACE_DBUS, "Hello"));
    return enqueue(request.get(), "s", deadline,
      [this, callback = std::move(callback)](BusReply reply) mutable {
        if (!reply.error) {
          const char *name = nullptr;
          if (!dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID) ||
              !name || name[0] != ':' || !dbus_validate_bus_name(name, nullptr) ||
              !dbus_bus_set_unique_name(connection_, name)) reply.error = "invalid_response";
          else unique_name_ = name;
        }
        callback(std::move(reply));
      });
  }
  bool call(DBusMessage *message, const std::string &signature,
            Deadline deadline, BusCallback callback) {
    if (unique_name_.empty()) return false;
    return enqueue(message, signature, deadline, std::move(callback));
  }

  // Registration is local and precedes the caller's asynchronous AddMatch and
  // snapshot. Source checks remain necessary even when the daemon filters.
  std::uint64_t listen(std::string sender, std::string path, std::string interface,
                       std::string member, std::string signature, SignalCallback callback) {
    if (!connection_ || failure_ || unique_name_.empty() || listeners_.size() >= 64 ||
        listener_sequence_ == std::numeric_limits<std::uint64_t>::max())
      throw std::runtime_error("resource_limit");
    for (const auto *field : {&sender, &path, &interface, &member, &signature})
      if (field->size() > 4096 || field->find('\0') != std::string::npos)
        throw std::invalid_argument("invalid_listener");
    if (sender.empty() || (sender[0] != ':' && sender != DBUS_SERVICE_DBUS) ||
        !dbus_validate_bus_name(sender.c_str(), nullptr) ||
        (!path.empty() && !dbus_validate_path(path.c_str(), nullptr)) ||
        !dbus_validate_interface(interface.c_str(), nullptr) ||
        !dbus_validate_member(member.c_str(), nullptr) ||
        !dbus_signature_validate(signature.c_str(), nullptr) || !callback)
      throw std::invalid_argument("invalid_listener");
    const auto identity = ++listener_sequence_;
    listeners_.emplace(identity, std::make_shared<Listener>(Listener{
      std::move(sender), std::move(path), std::move(interface), std::move(member),
      std::move(signature), std::move(callback)}));
    return identity;
  }
  void unlisten(std::uint64_t identity) noexcept {
    const auto found = listeners_.find(identity);
    if (found == listeners_.end()) return;
    found->second->active = false;
    listeners_.erase(found);
  }

  // Extra descriptors belong to the caller (typically native stdin/stdout).
  // Their readiness is returned without transferring their ownership to libdbus.
  void poll(std::vector<pollfd> &extra, int wait_ms) {
    for (auto &descriptor : extra) descriptor.revents = 0;
    if (!connection_) return;
    dispatch();
    if (!connection_ || failure_) return;
    std::vector<std::shared_ptr<Watch>> selected;
    std::vector<pollfd> descriptors = extra;
    for (const auto &[unused, watch] : watches_) {
      (void)unused;
      if (!dbus_watch_get_enabled(watch->value)) continue;
      const auto flags = dbus_watch_get_flags(watch->value);
      short events = 0;
      if (flags & DBUS_WATCH_READABLE) events |= POLLIN;
      if (flags & DBUS_WATCH_WRITABLE) events |= POLLOUT;
      descriptors.push_back({dbus_watch_get_unix_fd(watch->value), events, 0});
      selected.push_back(watch);
    }
    const auto now = Clock::now();
    int timeout = std::clamp(wait_ms, 0, 1000);
    std::vector<std::shared_ptr<Timeout>> timers;
    for (const auto &[unused, timer] : timeouts_) {
      (void)unused;
      if (!dbus_timeout_get_enabled(timer->value)) continue;
      timers.push_back(timer);
      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(timer->due - now).count();
      timeout = std::min(timeout, static_cast<int>(std::clamp<std::int64_t>(remaining, 0, 1000)));
    }
    if (dbus_connection_get_dispatch_status(connection_) == DBUS_DISPATCH_DATA_REMAINS) timeout = 0;
    const int result = ::poll(descriptors.data(), descriptors.size(), timeout);
    if (result < 0) { if (errno != EINTR) failure_ = "transport_error"; return; }
    for (std::size_t i = 0; i < extra.size(); ++i) extra[i].revents = descriptors[i].revents;
    for (std::size_t i = 0; i < selected.size(); ++i) {
      const auto &watch = selected[i];
      const auto revents = descriptors[extra.size() + i].revents;
      if (!watch->active || !revents) continue;
      unsigned flags = 0;
      if (revents & POLLIN) flags |= DBUS_WATCH_READABLE;
      if (revents & POLLOUT) flags |= DBUS_WATCH_WRITABLE;
      if (revents & (POLLERR | POLLNVAL)) flags |= DBUS_WATCH_ERROR;
      if (revents & POLLHUP) flags |= DBUS_WATCH_HANGUP;
      if (!dbus_watch_handle(watch->value, flags)) failure_ = "resource_limit";
    }
    for (const auto &timer : timers) {
      if (!timer->active || !dbus_timeout_get_enabled(timer->value) || timer->due > Clock::now()) continue;
      timer->due = after(dbus_timeout_get_interval(timer->value));
      if (!dbus_timeout_handle(timer->value)) failure_ = "resource_limit";
    }
    dispatch();
  }

  void close() noexcept {
    for (const auto &[unused, listener] : listeners_) { (void)unused; listener->active = false; }
    listeners_.clear();
    pending_.clear();
    if (connection_) {
      if (filter_installed_) dbus_connection_remove_filter(connection_, received, this);
      filter_installed_ = false;
      dbus_connection_set_watch_functions(connection_, nullptr, nullptr, nullptr, nullptr, nullptr);
      dbus_connection_set_timeout_functions(connection_, nullptr, nullptr, nullptr, nullptr, nullptr);
      dbus_connection_close(connection_);
      dbus_connection_unref(connection_);
      connection_ = nullptr;
    }
    watches_.clear(); timeouts_.clear(); unique_name_.clear();
  }
  const std::string &unique_name() const { return unique_name_; }
  const char *failure() const { return failure_; }
  std::size_t pending_count() const { return pending_.size(); }
  std::size_t watch_count() const { return watches_.size(); }
  std::size_t timeout_count() const { return timeouts_.size(); }
  std::size_t listener_count() const { return listeners_.size(); }
};
} // namespace wotex::ble
