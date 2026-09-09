// SPDX-License-Identifier: Apache-2.0
// One explicit Agent registration and Pair attempt. The enclosing native owner
// keeps LiveDiscovery alive through this object's callbacks and destruction.
#pragma once
#include "agent.hpp"
#include "discovery.hpp"
#include "failure.hpp"
#include <optional>

namespace wotex::ble {
class NativePairing {
public:
  using Completion = std::function<void(std::optional<NativeFailure>)>;
  using Emit = std::function<bool(const Json &)>;
private:
  enum class Phase { idle, discovering, registering, pairing, closing, finished };
  struct State : std::enable_shared_from_this<State> {
    LiveDiscovery &owner;
    NativePeer peer;
    Phase phase = Phase::idle;
    std::uint64_t export_id = 0, challenge_sequence = 0;
    std::string request_id, object_path, device_path, bluez_owner, challenge_id;
    std::optional<AgentPrompt> prompt;
    std::optional<NativeFailure> failure;
    Deadline deadline, cleanup_deadline;
    Completion completion;
    Emit emit;
    bool registered = false, register_uncertain = false, pair_uncertain = false;
    bool close_sender = false;

    explicit State(LiveDiscovery &owner) : owner(owner), peer(owner.peer()) {}
    static Message method(const std::string &sender, const std::string &path,
                          const char *interface, const char *member) {
      return Message(dbus_message_new_method_call(sender.c_str(), path.c_str(), interface, member));
    }
    bool reject(DBusMessage *request) {
      return owner.bus().respond(Message(dbus_message_new_error(request, "org.bluez.Error.Rejected", nullptr)));
    }
    void reject_prompt() {
      if (!prompt) return;
      auto current = std::move(*prompt); prompt.reset(); challenge_id.clear();
      try {
        auto decision = current.decide({{"action", "reject"}});
        if (!owner.bus().respond(std::move(decision.response))) close_sender = true;
      } catch (...) { close_sender = true; }
    }
    void detach() {
      reject_prompt();
      owner.bus().unexport(export_id); export_id = 0;
    }
    void complete() {
      if (phase == Phase::finished) return;
      if (!failure && Clock::now() >= deadline) failure = NativeFailure::local("pairing_rejected");
      phase = Phase::finished; registered = false; register_uncertain = false; pair_uncertain = false;
      auto callback = std::exchange(completion, {});
      emit = {};
      if (callback) callback(std::move(failure));
    }
    void finish_cleanup() {
      if (close_sender) {
        if (!failure) failure = NativeFailure::local("disconnected");
        owner.close(cleanup_deadline);
        if (owner.closing()) return;
      }
      complete();
    }
    void close(std::optional<NativeFailure> error, Deadline stop_by) {
      if (phase == Phase::finished) return;
      if (phase == Phase::closing) { cleanup_deadline = std::min(cleanup_deadline, stop_by); return; }
      failure = std::move(error);
      close_sender = close_sender || phase == Phase::discovering;
      phase = Phase::closing;
      cleanup_deadline = std::min(stop_by, Clock::now() + std::chrono::milliseconds(500));
      close_sender = close_sender || register_uncertain || pair_uncertain;
      detach(); // local prompt/export ownership ends before an asynchronous wait
      if (!registered || !owner.active() || owner.bus().failure() || Clock::now() >= cleanup_deadline) {
        if (registered) close_sender = true;
        finish_cleanup(); return;
      }
      auto request = method(bluez_owner, "/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent");
      const char *path = object_path.c_str();
      if (!request || !dbus_message_append_args(request.get(), DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_INVALID)) {
        close_sender = true; finish_cleanup(); return;
      }
      // Reserve the second half of the remaining native allowance for owned
      // connection cleanup. Unregistration cannot consume a fresh full grace.
      const auto now = Clock::now();
      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(cleanup_deadline - now);
      const auto unregister_deadline = std::min(cleanup_deadline, now + std::max(std::chrono::milliseconds(1), remaining / 2));
      std::weak_ptr<State> weak = shared_from_this();
      if (!owner.bus().call(request.get(), "", unregister_deadline, [weak](BusReply reply) {
        const auto state = weak.lock();
        if (!state || state->phase != Phase::closing) return;
        state->registered = false;
        if (reply.error) state->close_sender = true;
        state->finish_cleanup();
      })) { close_sender = true; finish_cleanup(); }
    }
    void fail(NativeFailure error) {
      if (error.code() == "timeout") error = NativeFailure::local("pairing_rejected");
      close(std::move(error), Clock::now() + std::chrono::milliseconds(500));
    }
    void receive(DBusMessage *request) {
      if (phase != Phase::pairing) {
        reject(request); fail(NativeFailure::local("pairing_rejected")); return;
      }
      const char *member = dbus_message_get_member(request);
      if (member && (std::string(member) == "Release" || std::string(member) == "Cancel") &&
          dbus_message_has_signature(request, "")) {
        if (std::string(member) == "Release") registered = false;
        reject_prompt();
        if (!owner.bus().respond(Message(dbus_message_new_method_return(request)))) close_sender = true;
        fail(NativeFailure::local("pairing_rejected")); return;
      }
      bool retained = false;
      try {
        if (prompt || Clock::now() >= deadline || challenge_sequence == std::numeric_limits<std::uint64_t>::max())
          throw PairingRejected();
        prompt.emplace(AgentPrompt::from(request, device_path)); retained = true;
        challenge_id = request_id + ":" + std::to_string(++challenge_sequence);
        const auto remaining = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now()).count();
        if (remaining <= 0) throw PairingRejected();
        Json event = {{"version", 1}, {"id", request_id}, {"event", "agent_challenge"},
          {"challenge", {{"id", challenge_id},
            {"peer", {{"adapter", peer.adapter}, {"address", peer.address}, {"address_type", peer.address_type}}},
            {"kind", prompt->kind()}, {"value", prompt->value()}, {"timeout_ms", std::min<std::int64_t>(remaining, 60000)}}}};
        if (!emit(event)) { fail(NativeFailure::local("resource_limit")); return; }
      } catch (const PairingRejected &) {
        // A newly retained prompt is rejected by detach. An overlapping or
        // malformed request still needs its own fixed rejection response.
        if (!retained) reject(request);
        fail(NativeFailure::local("pairing_rejected"));
      } catch (...) {
        close_sender = true; fail(NativeFailure::local("resource_limit"));
      }
    }
    void pair() {
      phase = Phase::pairing; pair_uncertain = true;
      auto request = method(bluez_owner, device_path, device_interface, "Pair");
      std::weak_ptr<State> weak = shared_from_this();
      if (!owner.bus().call(request.get(), "", deadline, [weak](BusReply reply) {
        const auto state = weak.lock();
        if (!state || state->phase != Phase::pairing) return;
        if (Clock::now() >= state->deadline || (reply.error && std::string(reply.error) == "timeout")) {
          state->fail(NativeFailure::local("pairing_rejected")); return;
        }
        if (reply.error) {
          if (std::string(reply.error) == "remote_error") state->pair_uncertain = false;
          state->fail(NativeFailure::from(reply)); return;
        }
        state->pair_uncertain = false;
        if (state->prompt) {
          state->close_sender = true; state->fail(NativeFailure::local("pairing_rejected")); return;
        }
        state->close(std::nullopt, Clock::now() + std::chrono::milliseconds(500));
      })) fail(NativeFailure::local("resource_limit"));
    }
    void start(const Json &parameters) {
      if (!fields(parameters, {"capability"}) || !parameters.at("capability").is_string()) {
        failure = NativeFailure::local("invalid_options"); complete(); return;
      }
      const auto &capability = parameters.at("capability").get_ref<const std::string &>();
      if (capability != "NoInputNoOutput" && capability != "DisplayYesNo" && capability != "KeyboardOnly") {
        failure = NativeFailure::local("invalid_options"); complete(); return;
      }
      if (!owner.active() || !owner.snapshot()) {
        failure = NativeFailure::local("disconnected"); complete(); return;
      }
      if (Clock::now() >= deadline) { failure = NativeFailure::local("pairing_rejected"); complete(); return; }
      if (owner.stale()) {
        phase = Phase::discovering;
        std::weak_ptr<State> weak = shared_from_this();
        if (!owner.refresh(deadline, [weak, capability](const char *error) {
          const auto state = weak.lock();
          if (!state || state->phase != Phase::discovering) return;
          if (error) state->fail(NativeFailure::local(error));
          else state->register_agent(capability);
        })) fail(NativeFailure::local("busy"));
      } else register_agent(capability);
    }
    void register_agent(const std::string &capability) {
      if (!owner.accept_link()) { fail(NativeFailure::local("disconnected")); return; }
      if (Clock::now() >= deadline) { fail(NativeFailure::local("pairing_rejected")); return; }
      device_path = owner.snapshot()->device_path; bluez_owner = owner.owner();
      std::weak_ptr<State> weak = shared_from_this();
      export_id = owner.bus().export_interface(bluez_owner, object_path, "org.bluez.Agent1", [weak](DBusMessage *request) {
        const auto state = weak.lock();
        if (state) state->receive(request);
      });
      phase = Phase::registering; registered = true; register_uncertain = true;
      auto request = method(bluez_owner, "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent");
      const char *path = object_path.c_str(), *name = capability.c_str();
      if (!request || !dbus_message_append_args(request.get(), DBUS_TYPE_OBJECT_PATH, &path,
          DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID)) { fail(NativeFailure::local("resource_limit")); return; }
      if (!owner.bus().call(request.get(), "", deadline, [weak](BusReply reply) {
        const auto state = weak.lock();
        if (!state || state->phase != Phase::registering) return;
        if (Clock::now() >= state->deadline || (reply.error && std::string(reply.error) == "timeout")) {
          state->fail(NativeFailure::local("pairing_rejected")); return;
        }
        if (reply.error) {
          if (std::string(reply.error) == "remote_error") {
            state->registered = false; state->register_uncertain = false;
          }
          state->fail(NativeFailure::from(reply)); return;
        }
        state->register_uncertain = false; state->pair();
      })) fail(NativeFailure::local("resource_limit"));
    }
    bool reply(const Json &parameters) {
      if (phase != Phase::pairing || !prompt || Clock::now() >= deadline ||
          !fields(parameters, {"challenge_id", "decision"}) || parameters.at("challenge_id") != challenge_id) {
        if (phase != Phase::finished) fail(NativeFailure::local("pairing_rejected"));
        return false;
      }
      auto current = std::move(*prompt); prompt.reset(); challenge_id.clear();
      try {
        auto decision = current.decide(parameters.at("decision"));
        if (!owner.bus().respond(std::move(decision.response))) {
          close_sender = true; fail(NativeFailure::local("disconnected")); return false;
        }
        if (!decision.accepted) fail(NativeFailure::local("pairing_rejected"));
        return true;
      } catch (...) {
        try {
          auto rejected = current.decide({{"action", "reject"}});
          if (!owner.bus().respond(std::move(rejected.response))) close_sender = true;
        } catch (...) { close_sender = true; }
        fail(NativeFailure::local("pairing_rejected")); return false;
      }
    }
    void tick() {
      if (phase == Phase::idle || phase == Phase::finished) return;
      if (phase == Phase::closing) {
        if (Clock::now() >= cleanup_deadline) {
          close_sender = true;
          if (!failure) failure = NativeFailure::local("disconnected");
          owner.close(cleanup_deadline);
          if (!owner.closing()) complete();
        } else if (!owner.active() && !owner.closing()) finish_cleanup();
      } else if (!owner.active()) {
        fail(NativeFailure::local(owner.failure().empty() ? "disconnected" : owner.failure()));
      } else if (Clock::now() >= deadline) fail(NativeFailure::local("pairing_rejected"));
    }
    void abandon() noexcept {
      if (phase == Phase::idle || phase == Phase::finished) return;
      completion = {}; emit = {};
      const auto stop_by = phase == Phase::closing ? cleanup_deadline : Clock::now() + std::chrono::milliseconds(500);
      try { detach(); owner.close(stop_by); } catch (...) {}
      phase = Phase::finished;
    }
  };
  std::shared_ptr<State> state_;
public:
  explicit NativePairing(LiveDiscovery &owner) : state_(std::make_shared<State>(owner)) {}
  NativePairing(const NativePairing &) = delete;
  NativePairing &operator=(const NativePairing &) = delete;
  ~NativePairing() { state_->abandon(); }
  bool start(const Json &parameters, std::uint64_t request_id, Deadline deadline, Emit emit, Completion completion) {
    auto state = state_;
    if (state->phase != Phase::idle || !request_id || !emit || !completion) return false;
    state->request_id = std::to_string(request_id);
    state->object_path = "/org/wotex/ble/agent_" + state->request_id;
    state->deadline = deadline; state->emit = std::move(emit); state->completion = std::move(completion);
    try { state->start(parameters); }
    catch (...) { state->fail(NativeFailure::local("resource_limit")); }
    return true;
  }
  bool reply(const Json &parameters) { return state_->reply(parameters); }
  void cancel(Deadline stop_by) { state_->close(NativeFailure::local("pairing_rejected"), stop_by); }
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
  bool pending_prompt() const { return bool(state_->prompt); }
  const std::string &object_path() const { return state_->object_path; }
};
} // namespace wotex::ble
