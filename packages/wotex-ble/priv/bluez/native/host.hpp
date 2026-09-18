// SPDX-License-Identifier: Apache-2.0
// The SDK host owns one explicit BlueZ sender. Its caller supplies stdin/stdout
// polling and keeps it alive through bounded cooperative cleanup. SDK callbacks
// admit bounded frames; they never block on stdout or retain completed IDs.
#pragma once
#include "notifications.hpp"
#include "pages.hpp"
#include "pairing.hpp"
#include "procedures.hpp"
#include "reports.hpp"
#include <deque>

namespace wotex::ble {
class NativeHost {
  struct Pending {
    Json request;
    Deadline deadline;
    NativeOutput::ReplySlot slot;
    Pending(Json request, Deadline deadline, NativeOutput::ReplySlot slot)
      : request(std::move(request)), deadline(deadline), slot(std::move(slot)) {}
    const std::string &id() const { return request.at("id").get_ref<const std::string &>(); }
    const std::string &operation() const { return request.at("operation").get_ref<const std::string &>(); }
    const Json &parameters() const { return request.at("parameters"); }
    std::uint64_t number() const { return std::stoull(id()); }
  };
  NativeOutput output_;
  Sequence sequence_;
  NativePages pages_;
  std::unique_ptr<NativeReports> reports_;
  std::unique_ptr<LiveDiscovery> owner_;
  std::unique_ptr<NativeNotifications> notifications_;
  std::unique_ptr<NativeProcedure> procedure_;
  std::unique_ptr<NativePairing> pairing_;
  std::shared_ptr<Pending> active_;
  std::deque<std::shared_ptr<Pending>> queued_;
  std::set<std::uint64_t> streams_;
  std::map<std::string, std::shared_ptr<Pending>> controls_;
  Deadline stop_by_;
  bool opening_ = false, opened_ = false, closing_ = false, close_reply_ = false, finished_ = false;
  int status_ = 0;

  bool emit(const Json &frame) { return output_.control(EncodedFrame::from(frame, NativeOutput::control_frame_limit)); }
  void reply(const std::shared_ptr<Pending> &pending, const Json &result, std::optional<NativeFailure> failure = {}) {
    Json frame{{"version", 1}, {"id", pending->id()}, {"ok", !failure}};
    if (failure) frame["error"] = failure->envelope(); else frame["result"] = result;
    if (!output_.reply(pending->slot, EncodedFrame::from(frame))) throw InvalidFrame();
    if (active_ == pending) active_.reset();
  }
  void fail(const std::shared_ptr<Pending> &pending, std::string_view code) { reply(pending, {}, NativeFailure::local(code)); }
  void retire(std::uint64_t id, std::optional<NativeFailure> failure) {
    streams_.erase(id);
    if (reports_) reports_->retire(id, failure ? std::optional<Json>(failure->envelope()) : std::nullopt);
  }
  void close(bool response, Deadline deadline, int status) {
    if (closing_) {
      // Link or sender loss during an explicit close is part of that cleanup;
      // the final completion still reports any cleanup that did not finish.
      stop_by_ = std::min(stop_by_, deadline);
      if (!close_reply_) status_ = std::max(status_, status);
      return;
    }
    closing_ = true; close_reply_ = response; status_ = status;
    stop_by_ = std::min(deadline, Clock::now() + std::chrono::milliseconds(500));
    for (const auto &pending : queued_) fail(pending, "disconnected");
    queued_.clear();
    if (reports_) for (auto id : streams_) reports_->silence(id);
    if (notifications_) {
      const auto streams = streams_;
      for (auto id : streams) notifications_->cancel(id, stop_by_, [](const auto &) {});
      if (active_ && active_->operation() == "subscribe" && !streams.count(active_->number()))
        notifications_->cancel(active_->number(), stop_by_, [](const auto &) {});
    }
    if (pairing_ && pairing_->active()) pairing_->cancel(stop_by_);
    if (procedure_ && procedure_->active()) procedure_->cancel(stop_by_);
    // Pair and StopNotify get the original sender until their own bounded
    // cleanup completes. Only then may link ownership disconnect that sender.
  }
  void complete_close() {
    const bool protocol_active = (pairing_ && pairing_->active()) || (procedure_ && procedure_->active()) ||
                                (notifications_ && notifications_->active_count());
    if (!protocol_active && owner_ && owner_->active()) owner_->close(stop_by_);
    const bool owner_active = owner_ && (owner_->active() || owner_->closing());
    if ((!protocol_active && !owner_active) || Clock::now() >= stop_by_) {
      if (protocol_active || owner_active) status_ = 1;
      if (active_) fail(active_, "disconnected");
      for (const auto &[unused, pending] : controls_) { (void)unused; fail(pending, "disconnected"); }
      controls_.clear();
      if (close_reply_) {
        close_reply_ = false;
        Json frame{{"version", 1}, {"id", "close"}, {"ok", status_ == 0}};
        if (status_ == 0) frame["result"] = nullptr;
        else frame["error"] = NativeFailure::local("cleanup_timeout").envelope();
        if (!emit(frame)) status_ = 1;
      }
      // Component destruction abandons every remaining callback before the
      // sender closes. Process custody independently bounds a blocked SDK.
      notifications_.reset(); procedure_.reset(); pairing_.reset(); owner_.reset();
      finished_ = true;
    }
  }
  void open(const std::shared_ptr<Pending> &pending) {
    const auto &parameters = pending->parameters();
    if (!fields(parameters, {"peer", "connection", "bus_address"}) || !parameters.at("bus_address").is_string() ||
        (parameters.at("connection") != "borrowed" && parameters.at("connection") != "owned")) {
      fail(pending, "invalid_options"); close(false, pending->deadline, 1); return;
    }
    std::optional<NativePeer> peer;
    try { peer.emplace(NativePeer::from(parameters.at("peer"))); }
    catch (const InvalidObjects &) { fail(pending, "invalid_peer"); close(false, pending->deadline, 1); return; }
    try { owner_ = std::make_unique<LiveDiscovery>(parameters.at("bus_address").get<std::string>(), std::move(*peer)); }
    catch (const std::invalid_argument &) { fail(pending, "invalid_options"); close(false, pending->deadline, 1); return; }
    catch (const std::bad_alloc &) { fail(pending, "resource_limit"); close(false, pending->deadline, 1); return; }
    catch (const std::exception &error) { fail(pending, error.what()); close(false, pending->deadline, 1); return; }
    opening_ = true;
    const bool accepted = owner_->connect(parameters.at("connection") == "owned", pending->deadline, [this, pending](const char *error) {
      opening_ = false;
      if (closing_) return;
      if (error) { fail(pending, error); close(false, pending->deadline, 1); return; }
      opened_ = true;
      notifications_ = std::make_unique<NativeNotifications>(*owner_, [this](const Json &value) { return reports_->publish(value); },
        [this](std::uint64_t id, std::optional<NativeFailure> failure) { retire(id, std::move(failure)); });
      reply(pending, {{"generation", owner_->generation()}, {"device_path", owner_->snapshot()->device_path},
        {"link_owned", owner_->link_owned()}, {"sender", owner_->bus().unique_name()}});
    }, [this](const char *) { close(false, Clock::now() + std::chrono::milliseconds(500), 1); });
    if (!accepted) { opening_ = false; fail(pending, "resource_limit"); close(false, pending->deadline, 1); }
  }
  void discovery(const std::shared_ptr<Pending> &pending) {
    try {
      const auto request = PageRequest::from(pending->parameters());
      if (request.cursor) pages_.offset(request, owner_->generation(), owner_->stale());
      if (request.cursor) { reply(pending, pages_.page(request, pending->id(), owner_->snapshot()->characteristics, owner_->generation())); return; }
      if (!owner_->refresh(pending->deadline, [this, pending, request](const char *error) {
        if (closing_) return;
        if (error) { fail(pending, error); return; }
        try { reply(pending, pages_.page(request, pending->id(), owner_->snapshot()->characteristics, owner_->generation(), owner_->stale())); }
        catch (const PageFailure &failure) { fail(pending, failure.what()); }
      })) fail(pending, "busy");
    } catch (const PageFailure &error) { fail(pending, error.what()); }
  }
  // By value: the copy keeps the operation alive while dispatch clears active_, which the
  // caller passes.
  // NOLINTNEXTLINE(performance-unnecessary-value-param)
  void dispatch(std::shared_ptr<Pending> pending) {
    if (Clock::now() >= pending->deadline) { fail(pending, "timeout"); return; }
    const auto &operation = pending->operation();
    if (operation == "open") { open(pending); return; }
    if (!opened_ || !owner_ || !owner_->active()) { fail(pending, "disconnected"); return; }
    if (operation == "discover") discovery(pending);
    else if (operation == "read" || operation == "write" || operation == "health") {
      procedure_ = std::make_unique<NativeProcedure>(*owner_);
      if (!procedure_->start(operation, pending->parameters(), pending->number(), pending->deadline,
          [this](const Json &frame) { return emit(frame); }, [this, pending](ProcedureResult result) {
            reply(pending, result.value, std::move(result.failure));
          })) fail(pending, "busy");
    } else if (operation == "pair") {
      pairing_ = std::make_unique<NativePairing>(*owner_);
      if (!pairing_->start(pending->parameters(), pending->number(), pending->deadline,
          [this](const Json &frame) { return emit(frame); }, [this, pending](std::optional<NativeFailure> failure) {
            reply(pending, {{"paired", true}}, std::move(failure));
          })) fail(pending, "busy");
    } else if (operation == "subscribe") {
      if (!notifications_->subscribe(pending->parameters(), pending->number(), pending->deadline,
          [this, pending](SubscribeResult result) {
            if (!result.failure) {
              const auto &value = result.value;
              const Json metadata{{"source", "bluez_value_change"}, {"characteristic", value.at("characteristic")},
                {"requested_mode", value.at("requested_mode")}, {"effective_mode", value.at("effective_mode")}};
              if (!reports_->open(pending->number(), metadata, pending->parameters().at("queue_limit").get<std::size_t>())) throw InvalidFrame();
              streams_.insert(pending->number());
            }
            reply(pending, result.value, std::move(result.failure));
          })) fail(pending, "busy");
    } else throw InvalidFrame();
  }
  void control(const std::shared_ptr<Pending> &pending) {
    if (Clock::now() >= pending->deadline) { fail(pending, "timeout"); return; }
    if (!opened_ || !owner_ || !owner_->active()) { fail(pending, "disconnected"); return; }
    if (pending->operation() == "agent_reply") {
      if (!pairing_ || !pairing_->active() || !pairing_->reply(pending->parameters())) { fail(pending, "pairing_rejected"); return; }
      reply(pending, nullptr); return;
    }
    const auto &parameters = pending->parameters();
    if (!fields(parameters, {"subscription_id"}) || !parameters.at("subscription_id").is_string()) { fail(pending, "invalid_subscription"); return; }
    const auto &text = parameters.at("subscription_id").get_ref<const std::string &>();
    if (text.empty() || text.size() > 20 || text.front() == '0') { fail(pending, "invalid_subscription"); return; }
    std::uint64_t id = 0;
    for (char c : text) {
      if (c < '0' || c > '9' || id > (UINT64_MAX - static_cast<unsigned>(c - '0')) / 10) { fail(pending, "invalid_subscription"); return; }
      id = id * 10 + static_cast<unsigned>(c - '0');
    }
    if (text.empty() || text.front() == '0' || !id || !streams_.count(id)) { fail(pending, "invalid_subscription"); return; }
    reports_->silence(id); controls_.emplace(pending->id(), pending);
    if (!notifications_->cancel(id, pending->deadline, [this, pending](std::optional<NativeFailure> failure) {
      controls_.erase(pending->id()); reply(pending, nullptr, std::move(failure));
    })) { controls_.erase(pending->id()); fail(pending, "invalid_subscription"); }
  }
public:
  explicit NativeHost(std::function<std::string()> random) : pages_(std::move(random)) {
    if (!emit({{"version", 1}, {"event", "ready"}, {"backend", "bluez-native"},
      {"revision", "2123ab772fbe97d1369fc9e179ea87c3469cf98f"}})) throw InvalidFrame();
  }
  NativeHost(const NativeHost &) = delete;
  NativeHost &operator=(const NativeHost &) = delete;
  ~NativeHost() { notifications_.reset(); procedure_.reset(); pairing_.reset(); owner_.reset(); }
  void receive(const Json &frame) {
    if (finished_) throw InvalidFrame();
    if (frame.contains("event")) {
      if (fields(frame, {"version", "event", "session_generation"}) && frame.at("event") == "flow_open" &&
          integer(frame.at("version"), 1, 1) && !closing_ && !reports_ && !owner_ && frame.at("session_generation").is_string()) {
        reports_ = std::make_unique<NativeReports>(output_, frame.at("session_generation").get<std::string>()); return;
      }
      if (!reports_) throw InvalidFrame();
      reports_->acknowledge(frame); return;
    }
    if (closing_ || !reports_ || !sequence_.accept(frame)) throw InvalidFrame();
    const auto deadline = Clock::now() + std::chrono::milliseconds(frame.at("timeout_ms").get<unsigned>());
    if (frame.at("operation") == "close") { close(true, deadline, 0); return; }
    const auto slot = output_.reserve_reply(); if (!slot) throw InvalidFrame();
    auto pending = std::make_shared<Pending>(frame, deadline, *slot);
    if (pending->operation() == "agent_reply" || pending->operation() == "unsubscribe") control(pending);
    else queued_.push_back(std::move(pending));
  }
  // An admitted close already owns the bounded cleanup deadline and final result.
  // Later input loss or a termination signal cannot relabel it as a failure.
  void stop() {
    if (closing_) return;
    close(false, Clock::now() + std::chrono::milliseconds(500), 1);
  }
  void poll(std::vector<pollfd> &extra, int wait_ms) {
    if (finished_) return;
    if (closing_) {
      wait_ms = std::min(wait_ms, static_cast<int>(std::clamp<std::int64_t>(
        std::chrono::ceil<std::chrono::milliseconds>(stop_by_ - Clock::now()).count(), 0, 500)));
    }
    for (const auto &pending : queued_) {
      const auto remaining = std::chrono::ceil<std::chrono::milliseconds>(pending->deadline - Clock::now()).count();
      wait_ms = std::min(wait_ms, static_cast<int>(std::clamp<std::int64_t>(remaining, 0, 60000)));
    }
    if (owner_) owner_->poll(extra, wait_ms);
    else if (::poll(extra.data(), extra.size(), wait_ms) < 0 && errno != EINTR) throw std::runtime_error("poll_failure");
    std::vector<pollfd> none;
    if (procedure_) procedure_->poll(none, 0);
    if (pairing_) pairing_->poll(none, 0);
    if (notifications_) notifications_->poll(none, 0);
    if (closing_) { complete_close(); return; }
    for (auto item = queued_.begin(); item != queued_.end();) {
      if (Clock::now() < (*item)->deadline) { ++item; continue; }
      const auto expired = *item; item = queued_.erase(item); fail(expired, "timeout");
    }
    if (!active_ && !queued_.empty()) { active_ = queued_.front(); queued_.pop_front(); dispatch(active_); }
  }
  void flush(int descriptor) { output_.flush(descriptor); }
  std::size_t output_frames() const { return output_.pending_frames(); }
  Deadline close_deadline() const { return closing_ ? stop_by_ : Deadline::max(); }
  bool finished() const { return finished_; }
  int status() const { return status_; }
};
} // namespace wotex::ble
