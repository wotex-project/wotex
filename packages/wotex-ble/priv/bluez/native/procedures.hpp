// SPDX-License-Identifier: Apache-2.0
// One bounded acknowledged GATT operation. The enclosing owner keeps discovery
// alive through callbacks and polls this operation until its terminal result.
#pragma once
#include "address.hpp"
#include "bytes.hpp"
#include "discovery.hpp"
#include "failure.hpp"

namespace wotex::ble {
struct ProcedureResult {
  std::optional<NativeFailure> failure;
  Json value;
  bool write_submitted;
};

class NativeProcedure {
public:
  using Completion = std::function<void(ProcedureResult)>;
  using Emit = std::function<bool(const Json &)>;
private:
  enum class Phase { idle, resolving, active, closing, finished };
  struct State : std::enable_shared_from_this<State> {
    LiveDiscovery &owner;
    Phase phase = Phase::idle;
    std::string operation, request_id;
    std::optional<NativeAddress> address;
    std::optional<AttributeBytes> bytes;
    std::optional<NativeFailure> failure;
    Json result;
    Deadline deadline, cleanup_deadline;
    Emit emit;
    Completion completion;
    bool write_submitted = false;
    explicit State(LiveDiscovery &owner) : owner(owner) {}
    void complete() {
      if (phase == Phase::finished) return;
      phase = Phase::finished;
      auto callback = std::exchange(completion, {});
      emit = {}; address.reset(); bytes.reset();
      if (callback) callback({std::move(failure), std::move(result), write_submitted});
    }
    void fail(NativeFailure error, bool close, Deadline stop_by = Clock::now() + std::chrono::milliseconds(500)) {
      if (phase == Phase::finished) return;
      if (phase == Phase::closing) { cleanup_deadline = std::min(cleanup_deadline, stop_by); return; }
      failure = std::move(error);
      if (!close) { complete(); return; }
      phase = Phase::closing;
      cleanup_deadline = std::min(stop_by, Clock::now() + std::chrono::milliseconds(500));
      owner.close(cleanup_deadline);
      if (!owner.closing()) complete();
    }
    static void append(bool accepted) { if (!accepted) throw std::runtime_error("resource_limit"); }
    static void option(DBusMessageIter &dictionary, const char *name, const char *signature, int type, const void *value) {
      DBusMessageIter entry, variant;
      append(dbus_message_iter_open_container(&dictionary, DBUS_TYPE_DICT_ENTRY, nullptr, &entry));
      append(dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &name));
      append(dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, signature, &variant));
      append(dbus_message_iter_append_basic(&variant, type, value));
      append(dbus_message_iter_close_container(&entry, &variant));
      append(dbus_message_iter_close_container(&dictionary, &entry));
    }
    Message request(const std::string &path) {
      Message message(dbus_message_new_method_call(owner.owner().c_str(), path.c_str(), characteristic_interface,
        operation == "write" ? "WriteValue" : "ReadValue"));
      if (!message) throw std::runtime_error("resource_limit");
      DBusMessageIter root, array, options;
      dbus_message_iter_init_append(message.get(), &root);
      if (operation == "write") {
        const auto &value = bytes->value();
        constexpr unsigned char empty = 0;
        const unsigned char *data = value.empty() ? &empty : value.data();
        append(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "y", &array));
        append(dbus_message_iter_append_fixed_array(&array, DBUS_TYPE_BYTE, &data, static_cast<int>(value.size())));
        append(dbus_message_iter_close_container(&root, &array));
      }
      append(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "{sv}", &options));
      if (operation == "write") {
        const char *type = "request"; dbus_uint16_t offset = 0;
        option(options, "type", "s", DBUS_TYPE_STRING, &type);
        option(options, "offset", "q", DBUS_TYPE_UINT16, &offset);
      }
      append(dbus_message_iter_close_container(&root, &options));
      return message;
    }
    static Json read(DBusMessage *message) {
      if (!message || !dbus_message_has_signature(message, "ay") || dbus_message_contains_unix_fds(message))
        throw InvalidValue();
      DBusMessageIter root, data;
      if (!dbus_message_iter_init(message, &root)) throw InvalidValue();
      dbus_message_iter_recurse(&root, &data);
      const unsigned char *value = nullptr; int count = 0;
      dbus_message_iter_get_fixed_array(&data, &value, &count);
      if (count < 0 || count > 512 || (count && !value)) throw InvalidValue();
      const auto view = count ? std::string_view(reinterpret_cast<const char *>(value), static_cast<std::size_t>(count)) : std::string_view{};
      return AttributeBytes::from_bytes(view).envelope();
    }
    void dispatch() {
      if (!owner.active() || !owner.snapshot() || !owner.accept_link()) {
        fail(NativeFailure::local("disconnected"), true); return;
      }
      try {
        const auto &item = address->select(*owner.snapshot(), owner.generation());
        const auto &flags = item.at("flags");
        if (std::find(flags.begin(), flags.end(), operation) == flags.end()) {
          fail(NativeFailure::local("not_permitted"), false); return;
        }
        auto message = request(item.at("object_path").get_ref<const std::string &>());
        if (Clock::now() >= deadline) { fail(NativeFailure::local("timeout"), true); return; }
        phase = Phase::active;
        if (operation == "write") {
          if (!emit({{"version", 1}, {"id", request_id}, {"event", "write_submitted"}})) {
            fail(NativeFailure::local("resource_limit"), false); return;
          }
          if (phase != Phase::active) return; // event handling may cancel the owner
          write_submitted = true;
        }
        std::weak_ptr<State> weak = shared_from_this();
        if (!owner.bus().call(message.get(), operation == "write" ? "" : "ay", deadline, [weak](BusReply reply) {
          const auto state = weak.lock();
          if (!state || state->phase != Phase::active) return;
          if (Clock::now() >= state->deadline) { state->fail(NativeFailure::local("timeout"), true); return; }
          if (reply.error) {
            auto failure = NativeFailure::from(reply);
            const auto &code = failure.code();
            const bool terminal = code == "timeout" || code == "disconnected" || code == "invalid_response" ||
                                  code == "transport_error" || code == "owner_changed" || code == "resource_limit";
            state->fail(std::move(failure), terminal); return;
          }
          try {
            if (state->operation == "read") state->result = read(reply.message.get());
          } catch (...) { state->fail(NativeFailure::local("invalid_response"), true); return; }
          state->complete();
        })) fail(NativeFailure::local(Clock::now() >= deadline ? "timeout" : "resource_limit"), true);
      } catch (const InvalidAddress &error) { fail(NativeFailure::local(error.what()), false); }
      catch (...) { fail(NativeFailure::local("resource_limit"), true); }
    }
    void start(const Json &parameters) {
      const bool valid = operation == "read" ? fields(parameters, {"address"}) :
        operation == "write" && fields(parameters, {"address", "value"});
      if (!valid) { fail(NativeFailure::local("invalid_options"), false); return; }
      try {
        address.emplace(NativeAddress::from(parameters.at("address")));
        if (operation == "write") bytes.emplace(AttributeBytes::from(parameters.at("value")));
      } catch (const InvalidAddress &) { fail(NativeFailure::local("invalid_address"), false); return; }
      catch (const InvalidValue &) { fail(NativeFailure::local("invalid_value"), false); return; }
      if (Clock::now() >= deadline) { fail(NativeFailure::local("timeout"), false); return; }
      if (!owner.active() || !owner.snapshot()) { fail(NativeFailure::local("disconnected"), false); return; }
      phase = Phase::resolving;
      std::weak_ptr<State> weak = shared_from_this();
      if (!owner.refresh(deadline, [weak](const char *error) {
        const auto state = weak.lock();
        if (!state || state->phase != Phase::resolving) return;
        if (error) state->fail(NativeFailure::local(error), true);
        else state->dispatch();
      })) fail(NativeFailure::local("busy"), false);
    }
    void tick() {
      if (phase == Phase::idle || phase == Phase::finished) return;
      if (phase == Phase::closing) {
        if (Clock::now() >= cleanup_deadline) owner.close(cleanup_deadline);
        if (!owner.closing()) complete();
      } else if (!owner.active()) {
        fail(NativeFailure::local(owner.failure().empty() ? "disconnected" : owner.failure()), true);
      } else if (Clock::now() >= deadline) fail(NativeFailure::local("timeout"), true);
    }
    void abandon() noexcept {
      if (phase == Phase::idle || phase == Phase::finished) return;
      completion = {}; emit = {};
      const auto stop_by = phase == Phase::closing ? cleanup_deadline : Clock::now() + std::chrono::milliseconds(500);
      try { owner.close(stop_by); } catch (...) {}
      phase = Phase::finished;
    }
  };
  std::shared_ptr<State> state_;
public:
  explicit NativeProcedure(LiveDiscovery &owner) : state_(std::make_shared<State>(owner)) {}
  NativeProcedure(const NativeProcedure &) = delete;
  NativeProcedure &operator=(const NativeProcedure &) = delete;
  ~NativeProcedure() { state_->abandon(); }
  bool start(std::string operation, const Json &parameters, std::uint64_t request_id, Deadline deadline, Emit emit, Completion completion) {
    auto state = state_;
    if (state->phase != Phase::idle || !request_id || !emit || !completion) return false;
    state->operation = std::move(operation); state->request_id = std::to_string(request_id);
    state->deadline = deadline; state->emit = std::move(emit); state->completion = std::move(completion);
    try { state->start(parameters); }
    catch (...) { state->fail(NativeFailure::local("resource_limit"), true); }
    return true;
  }
  void cancel(Deadline stop_by) { state_->fail(NativeFailure::local("timeout"), state_->phase != Phase::idle, stop_by); }
  void poll(std::vector<pollfd> &extra, int wait_ms) {
    auto state = state_;
    state->tick();
    if (state->phase != Phase::idle && state->phase != Phase::finished) {
      const auto deadline = state->phase == Phase::closing ? state->cleanup_deadline : state->deadline;
      const auto remaining = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now()).count();
      wait_ms = std::min(wait_ms, static_cast<int>(std::clamp<std::int64_t>(remaining, 0, 1000)));
    }
    state->owner.poll(extra, wait_ms); state->tick();
  }
  bool active() const { return state_->phase != Phase::idle && state_->phase != Phase::finished; }
};
} // namespace wotex::ble
