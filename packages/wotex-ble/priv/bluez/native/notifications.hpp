// SPDX-License-Identifier: Apache-2.0
// One connection's notification sessions. The enclosing host reserves output
// and flow credit; callbacks are nonblocking admission operations, never stdout.
#pragma once
#include "address.hpp"
#include "discovery.hpp"
#include "failure.hpp"
#include "notify_value.hpp"

namespace wotex::ble {
struct SubscribeResult { std::optional<NativeFailure> failure; Json value; };
class NativeNotifications {
public:
  using Completion = std::function<void(SubscribeResult)>;
  using Cancellation = std::function<void(std::optional<NativeFailure>)>;
  using Report = std::function<bool(const Json &)>;
  using Retirement = std::function<void(std::uint64_t, std::optional<NativeFailure>)>;
private:
  enum class Phase { resolving, starting, established, active, stopping, closing, finished };
  struct Entry {
    std::uint64_t identifier;
    NativeAddress address;
    std::string requested;
    std::optional<NotifyMode> mode;
    Json characteristic;
    std::optional<AttributeBytes> early;
    std::optional<NativeFailure> failure;
    std::optional<Bus::Ticket> call;
    Deadline deadline, cleanup_deadline;
    Completion completion;
    Cancellation cancelled;
    Phase phase = Phase::resolving;
    bool attempted = false, exposed = false, owns_refresh = false;
    Entry(std::uint64_t identifier, NativeAddress address, std::string requested, Deadline deadline, Completion completion)
      : identifier(identifier), address(std::move(address)), requested(std::move(requested)), deadline(deadline),
        completion(std::move(completion)) {}
  };
  struct State : std::enable_shared_from_this<State> {
    LiveDiscovery &owner;
    Report report;
    Retirement retired;
    std::map<std::uint64_t, std::shared_ptr<Entry>> entries;
    std::map<std::string, std::uint64_t> paths;
    std::uint64_t listener = 0, greatest_identifier = 0;
    explicit State(LiveDiscovery &owner, Report report, Retirement retired)
      : owner(owner), report(std::move(report)), retired(std::move(retired)) {}
    static bool live(const Entry &entry) {
      return entry.phase == Phase::resolving || entry.phase == Phase::starting ||
             entry.phase == Phase::established || entry.phase == Phase::active;
    }
    std::vector<std::shared_ptr<Entry>> snapshot() const {
      std::vector<std::shared_ptr<Entry>> result;
      for (const auto &[unused, entry] : entries) { (void)unused; result.push_back(entry); }
      return result;
    }
    void finish(const std::shared_ptr<Entry> &entry) {
      if (entry->phase == Phase::finished) return;
      entry->phase = Phase::finished;
      if (entry->call) owner.bus().cancel(*entry->call);
      entry->call.reset(); entry->early.reset();
      if (entry->owns_refresh) { owner.cancel_refresh(); entry->owns_refresh = false; }
      if (!entry->characteristic.is_null()) {
        const auto found = paths.find(entry->characteristic.at("object_path").get<std::string>());
        if (found != paths.end() && found->second == entry->identifier) paths.erase(found);
      }
      entries.erase(entry->identifier);
      if (entries.empty() && listener) { owner.bus().unlisten(listener); listener = 0; }
      auto completion = std::exchange(entry->completion, {});
      auto cancelled = std::exchange(entry->cancelled, {});
      if (completion) completion({entry->failure ? entry->failure : std::optional{NativeFailure::local("disconnected")}, {}});
      if (entry->exposed) retired(entry->identifier, entry->failure);
      if (cancelled) cancelled(entry->failure);
    }
    void force_close(const std::shared_ptr<Entry> &entry, NativeFailure failure) {
      if (!entry->failure) entry->failure = std::move(failure);
      entry->phase = Phase::closing;
      owner.close(entry->cleanup_deadline);
      if (!owner.closing()) finish(entry);
    }
    void stop(const std::shared_ptr<Entry> &entry, std::optional<NativeFailure> failure,
              Deadline deadline = Clock::now() + std::chrono::milliseconds(500)) {
      if (entry->phase == Phase::finished) return;
      if (!live(*entry)) { entry->cleanup_deadline = std::min(entry->cleanup_deadline, deadline); return; }
      entry->failure = std::move(failure); entry->early.reset();
      entry->cleanup_deadline = std::min(deadline, Clock::now() + std::chrono::milliseconds(500));
      if (entry->owns_refresh) { owner.cancel_refresh(); entry->owns_refresh = false; }
      if (entry->call) owner.bus().cancel(*entry->call);
      entry->call.reset(); entry->phase = Phase::stopping;
      if (!owner.active()) {
        entry->phase = Phase::closing;
        if (!owner.closing()) finish(entry);
        return;
      }
      if (!entry->attempted) { finish(entry); return; }
      if (Clock::now() >= entry->cleanup_deadline) { force_close(entry, NativeFailure::local("cleanup_timeout")); return; }
      Message request(dbus_message_new_method_call(owner.owner().c_str(),
        entry->characteristic.at("object_path").get_ref<const std::string &>().c_str(), characteristic_interface, "StopNotify"));
      std::weak_ptr<State> weak = shared_from_this(); std::weak_ptr<Entry> weak_entry = entry;
      entry->call = owner.bus().pending_call(request.get(), "", entry->cleanup_deadline, [weak, weak_entry](BusReply reply) {
        const auto state = weak.lock(); const auto entry = weak_entry.lock();
        if (!state || !entry || entry->phase != Phase::stopping) return;
        entry->call.reset();
        if (reply.error) state->force_close(entry, NativeFailure::from(reply));
        else state->finish(entry);
      });
      if (!entry->call) force_close(entry, NativeFailure::local("resource_limit"));
    }
    Json result(const Entry &entry) const {
      // NOLINTBEGIN(bugprone-unchecked-optional-access): an entry has its mode from the
      // moment it is resolving.
      return {{"subscription_id", std::to_string(entry.identifier)}, {"generation", 1},
        {"characteristic", entry.characteristic}, {"requested_mode", entry.mode->requested()}, {"effective_mode", entry.mode->effective()}};
      // NOLINTEND(bugprone-unchecked-optional-access)
    }
    void value(const std::shared_ptr<Entry> &entry, const AttributeBytes &bytes) {
      if (!live(*entry) || entry->phase == Phase::resolving) return;
      if (entry->phase != Phase::active) {
        if (entry->early) stop(entry, NativeFailure::local("response_limit"));
        else entry->early = bytes;
        return;
      }
      // NOLINTBEGIN(bugprone-unchecked-optional-access): an active entry has its mode.
      const Json envelope{{"version", 1}, {"subscription_id", std::to_string(entry->identifier)}, {"generation", 1},
        {"event", "value"}, {"value", bytes.envelope()}, {"metadata", {{"source", "bluez_value_change"},
          {"characteristic", entry->characteristic}, {"requested_mode", entry->mode->requested()}, {"effective_mode", entry->mode->effective()}}}};
      // NOLINTEND(bugprone-unchecked-optional-access)
      if (!report(envelope)) stop(entry, NativeFailure::local("queue_overflow"));
    }
    void signal(DBusMessage *message) {
      if (!owner.active()) return;
      const char *path = dbus_message_get_path(message);
      if (!path) return;
      for (const auto &entry : snapshot()) {
        if (!live(*entry) || entry->phase == Phase::resolving) continue;
        const bool characteristic = entry->characteristic.at("object_path") == path;
        const bool service = entry->characteristic.at("service_path") == path;
        const bool device = owner.snapshot() && owner.snapshot()->device_path == path;
        if (!characteristic && !service && !device) continue;
        try {
          const auto change = GattChange::from(message); const auto &metadata = change.metadata();
          if (characteristic && metadata.interface == characteristic_interface) {
            bool stale = false;
            for (const char *field : {"UUID", "Service", "Handle", "Flags"})
              stale = stale || metadata.values.contains(field) || metadata.invalidated.count(field);
            if (stale) stop(entry, NativeFailure::local("stale_discovery"));
            else if (metadata.invalidated.count("Notifying") || (change.notifying() && !*change.notifying()))
              stop(entry, NativeFailure::local("subscription_lost"));
            else if (metadata.invalidated.count("Value")) stop(entry, NativeFailure::local("invalid_response"));
            else if (change.value()) value(entry, *change.value());
          } else if (service && metadata.interface == service_interface &&
              (!metadata.values.empty() || metadata.invalidated.count("UUID") || metadata.invalidated.count("Device")))
            stop(entry, NativeFailure::local("stale_discovery"));
          else if (device && metadata.interface == device_interface) {
            for (const char *field : {"Adapter", "Address", "AddressType"}) {
              if (metadata.values.contains(field) || metadata.invalidated.count(field)) {
                stop(entry, NativeFailure::local("peer_changed")); break;
              }
            }
          }
        } catch (const InvalidObjects &error) { stop(entry, NativeFailure::local(error.what())); }
      }
    }
    void watch() {
      if (listener) return;
      std::weak_ptr<State> weak = shared_from_this();
      listener = owner.bus().listen(owner.owner(), "", "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as",
        [weak](DBusMessage *message) { const auto state = weak.lock(); if (state) state->signal(message); });
    }
    void dispatch(const std::shared_ptr<Entry> &entry) {
      entry->owns_refresh = false;
      if (!owner.active() || !owner.snapshot() || !owner.accept_link()) { stop(entry, NativeFailure::local("disconnected")); return; }
      try {
        entry->characteristic = entry->address.select(*owner.snapshot(), owner.generation());
        entry->mode.emplace(NotifyMode::from(entry->characteristic.at("flags"), entry->requested));
        const auto path = entry->characteristic.at("object_path").get<std::string>();
        if (paths.count(path)) { stop(entry, NativeFailure::local("already_subscribed")); return; }
        paths.emplace(path, entry->identifier); watch();
        if (Clock::now() >= entry->deadline) { stop(entry, NativeFailure::local("timeout")); return; }
        entry->phase = Phase::starting;
        Message request(dbus_message_new_method_call(owner.owner().c_str(), path.c_str(), characteristic_interface, "StartNotify"));
        std::weak_ptr<State> weak = shared_from_this(); std::weak_ptr<Entry> weak_entry = entry;
        entry->attempted = true;
        entry->call = owner.bus().pending_call(request.get(), "", entry->deadline, [weak, weak_entry](BusReply reply) {
          const auto state = weak.lock(); const auto entry = weak_entry.lock();
          if (!state || !entry || entry->phase != Phase::starting) return;
          entry->call.reset();
          if (Clock::now() >= entry->deadline) { state->stop(entry, NativeFailure::local("timeout")); return; }
          if (reply.error) {
            if (std::string(reply.error) == "remote_error") entry->attempted = false;
            state->stop(entry, NativeFailure::from(reply)); return;
          }
          entry->phase = Phase::established; entry->exposed = true;
          auto callback = std::exchange(entry->completion, {}); callback({{}, state->result(*entry)});
          if (entry->phase != Phase::established) return;
          entry->phase = Phase::active;
          auto early = std::exchange(entry->early, {});
          if (early) state->value(entry, *early);
        });
        if (!entry->call) stop(entry, NativeFailure::local("resource_limit"));
      } catch (const InvalidAddress &error) { stop(entry, NativeFailure::local(error.what())); }
      catch (const InvalidObjects &error) { stop(entry, NativeFailure::local(error.what())); }
    }
    void tick() {
      for (const auto &entry : snapshot()) {
        if (!owner.active()) {
          if (live(*entry)) stop(entry, NativeFailure::local(owner.failure().empty() ? "disconnected" : owner.failure()));
          if (!owner.closing()) finish(entry);
        } else if (entry->phase == Phase::stopping && Clock::now() >= entry->cleanup_deadline)
          force_close(entry, NativeFailure::local("cleanup_timeout"));
        else if ((entry->phase == Phase::resolving || entry->phase == Phase::starting) && Clock::now() >= entry->deadline)
          stop(entry, NativeFailure::local("timeout"));
      }
    }
    void abandon() noexcept {
      if (listener) owner.bus().unlisten(listener);
      listener = 0;
      // NOLINTNEXTLINE(bugprone-empty-catch): teardown must not throw; the failure is already terminal
      if (!entries.empty()) { try { owner.close(); } catch (...) {} }
      entries.clear(); paths.clear(); report = {}; retired = {};
    }
  };
  std::shared_ptr<State> state_;
public:
  NativeNotifications(LiveDiscovery &owner, Report report, Retirement retired)
    : state_(std::make_shared<State>(owner, std::move(report), std::move(retired))) {
    if (!state_->report || !state_->retired) throw std::invalid_argument("invalid_callbacks");
  }
  NativeNotifications(const NativeNotifications &) = delete;
  NativeNotifications &operator=(const NativeNotifications &) = delete;
  ~NativeNotifications() { state_->abandon(); }
  bool subscribe(const Json &parameters, std::uint64_t identifier, Deadline deadline, Completion completion) {
    auto state = state_;
    if (!completion || !identifier || identifier <= state->greatest_identifier) return false;
    if (!fields(parameters, {"address", "mode", "queue_limit"}) ||
        !integer(parameters.at("queue_limit"), 1, 10000) ||
        (parameters.at("mode") != "auto" && parameters.at("mode") != "notify" && parameters.at("mode") != "indicate")) {
      completion({NativeFailure::local("invalid_options"), {}}); return true;
    }
    std::optional<NativeAddress> address;
    try { address = NativeAddress::from(parameters.at("address")); }
    catch (const InvalidAddress &) { completion({NativeFailure::local("invalid_address"), {}}); return true; }
    if (state->entries.size() == 64) { completion({NativeFailure::local("busy"), {}}); return true; }
    if (!state->owner.active()) { completion({NativeFailure::local("disconnected"), {}}); return true; }
    state->greatest_identifier = identifier;
    auto entry = std::make_shared<Entry>(identifier, std::move(*address), parameters.at("mode").get<std::string>(), deadline, std::move(completion));
    state->entries.emplace(identifier, entry);
    if (Clock::now() >= deadline) { state->stop(entry, NativeFailure::local("timeout")); return true; }
    std::weak_ptr<State> weak = state; std::weak_ptr<Entry> weak_entry = entry;
    entry->owns_refresh = true;
    if (!state->owner.refresh(deadline, [weak, weak_entry](const char *error) {
      const auto state = weak.lock(); const auto entry = weak_entry.lock();
      if (!state || !entry || entry->phase != Phase::resolving) return;
      entry->owns_refresh = false;
      if (error) state->stop(entry, NativeFailure::local(error));
      else state->dispatch(entry);
    })) { entry->owns_refresh = false; state->stop(entry, NativeFailure::local("busy")); }
    return true;
  }
  bool cancel(std::uint64_t identifier, Deadline deadline, Cancellation completion) {
    auto state = state_; const auto found = state->entries.find(identifier);
    if (found == state->entries.end() || !completion || found->second->cancelled) return false;
    auto entry = found->second; entry->cancelled = std::move(completion);
    state->stop(entry, {}, deadline); return true;
  }
  void poll(std::vector<pollfd> &extra, int wait_ms) {
    auto state = state_; state->tick();
    for (const auto &entry : state->snapshot()) {
      if (entry->phase == Phase::active || entry->phase == Phase::established) continue;
      const auto deadline = State::live(*entry) ? entry->deadline : entry->cleanup_deadline;
      const auto remaining = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now()).count();
      wait_ms = std::min(wait_ms, static_cast<int>(std::clamp<std::int64_t>(remaining, 0, 1000)));
    }
    state->owner.poll(extra, wait_ms); state->tick();
  }
  std::size_t active_count() const { return state_->entries.size(); }
  std::size_t path_count() const { return state_->paths.size(); }
};
} // namespace wotex::ble
