// SPDX-License-Identifier: Apache-2.0
// Value admission joins stream identity, cumulative credit and nonblocking output.
// The caller supplies metadata from NativeNotifications' validated establishment,
// silences before SDK cleanup and retires once cleanup finishes. No callback waits.
#pragma once
#include "bytes.hpp"
#include "credit.hpp"
#include "error_value.hpp"
#include "output.hpp"
#include <set>

namespace wotex::ble {
class NativeReports {
  struct Stream {
    Json metadata;
    std::size_t limit, queued = 0;
    std::uint64_t last_sequence = 0;
    bool accepting = true;
  };
  struct Queued { std::uint64_t stream; AttributeBytes value; std::size_t charge; };
  NativeOutput &output_;
  std::string generation_;
  Credits credits_;
  std::map<std::uint64_t, Stream> streams_;
  std::deque<Queued> queued_;
  std::size_t queued_bytes_ = 0;
  Json envelope(std::uint64_t identifier, const Stream &stream, const AttributeBytes &value, std::uint64_t sequence) const {
    return {{"version", 1}, {"session_generation", generation_}, {"report_sequence", sequence},
      {"subscription_id", std::to_string(identifier)}, {"generation", 1}, {"event", "value"},
      {"value", value.envelope()}, {"metadata", stream.metadata}};
  }
  bool dispatch(std::uint64_t identifier, Stream &stream, const AttributeBytes &value) {
    const auto encoded = EncodedFrame::from(envelope(identifier, stream, value, credits_.next_sequence()));
    const auto sequence = credits_.reserve(identifier, encoded.size());
    if (!sequence) return false;
    // Output report storage is a subset of outstanding credits. A failure here
    // means the shared output channel violated its accounting and cannot recover.
    if (!output_.report(encoded, *sequence)) throw InvalidFrame();
    stream.last_sequence = *sequence; return true;
  }
  void erase(std::deque<Queued>::iterator &item) {
    auto &stream = streams_.at(item->stream); --stream.queued;
    queued_bytes_ -= item->charge; item = queued_.erase(item);
  }
  void drain() {
    // At most 64 visits. A credit-blocked stream cannot block another stream.
    std::set<std::uint64_t> blocked;
    for (auto item = queued_.begin(); item != queued_.end();) {
      auto &stream = streams_.at(item->stream);
      if (!blocked.count(item->stream) && dispatch(item->stream, stream, item->value)) erase(item);
      else { blocked.insert(item->stream); ++item; }
    }
  }
  static std::uint64_t identifier(const Json &value) {
    if (!value.is_string()) throw InvalidFrame();
    const auto &text = value.get_ref<const std::string &>();
    if (text.empty() || text.size() > 20 || text.front() == '0') throw InvalidFrame();
    std::uint64_t result = 0;
    for (const char digit : text) {
      if (digit < '0' || digit > '9' || result > (UINT64_MAX - (digit - '0')) / 10) throw InvalidFrame();
      result = result * 10 + (digit - '0');
    }
    return result;
  }
public:
  NativeReports(NativeOutput &output, std::string generation)
    : output_(output), generation_(std::move(generation)), credits_(generation_) {}
  NativeReports(const NativeReports &) = delete;
  NativeReports &operator=(const NativeReports &) = delete;

  // Metadata has already passed the native characteristic/mode constructors.
  // Validate its boundary and maximum report serialization before retaining it.
  bool open(std::uint64_t id, const Json &metadata, std::size_t queue_limit) {
    if (!fields(metadata, {"source", "characteristic", "requested_mode", "effective_mode"}) ||
        metadata.at("source") != "bluez_value_change" || !metadata.at("characteristic").is_object() ||
        (metadata.at("requested_mode") != "auto" && metadata.at("requested_mode") != "notify" && metadata.at("requested_mode") != "indicate") ||
        (metadata.at("effective_mode") != "notify" && metadata.at("effective_mode") != "indicate" && metadata.at("effective_mode") != "bluez_selected") ||
        (metadata.at("requested_mode") != "auto" && metadata.at("requested_mode") != metadata.at("effective_mode"))) throw InvalidFrame();
    // This bound is checked before copying metadata into persistent storage.
    EncodedFrame::from(metadata);
    Stream stream{metadata, queue_limit};
    EncodedFrame::from(envelope(id, stream, AttributeBytes::from_bytes(std::string(512, '\0')), UINT64_MAX));
    if (!credits_.open(id, queue_limit)) return false;
    streams_.emplace(id, std::move(stream)); return true;
  }

  bool publish(const Json &value) {
    if (!fields(value, {"version", "subscription_id", "generation", "event", "value", "metadata"}) ||
        !integer(value.at("version"), 1, 1) || !integer(value.at("generation"), 1, 1) || value.at("event") != "value") throw InvalidFrame();
    const auto id = identifier(value.at("subscription_id"));
    const auto found = streams_.find(id);
    if (found == streams_.end() || value.at("metadata") != found->second.metadata) throw InvalidFrame();
    auto &stream = found->second;
    AttributeBytes bytes = AttributeBytes::from(value.at("value"));
    if (!stream.accepting) return false;
    if (!stream.queued && dispatch(id, stream, bytes)) return true;
    // Twenty decimal sequence digits charge an upper bound before assignment;
    // queued values retain only bounded bytes and an ID, not copied metadata.
    const auto charge = EncodedFrame::from(envelope(id, stream, bytes, UINT64_MAX)).size();
    if (stream.queued == stream.limit || queued_.size() == 64 || charge > 1048576 - queued_bytes_) {
      silence(id); return false;
    }
    queued_.push_back({id, std::move(bytes), charge}); ++stream.queued; queued_bytes_ += charge; return true;
  }

  bool silence(std::uint64_t id) {
    const auto found = streams_.find(id);
    if (found == streams_.end() || !found->second.accepting) return false;
    found->second.accepting = false;
    for (auto item = queued_.begin(); item != queued_.end();) {
      if (item->stream == id) erase(item); else ++item;
    }
    return true;
  }

  bool retire(std::uint64_t id, const std::optional<Json> &failure = std::nullopt) {
    const auto found = streams_.find(id);
    if (found == streams_.end()) return false;
    if (failure && !native_error(*failure)) throw InvalidFrame();
    silence(id);
    if (failure) {
      const auto terminal = EncodedFrame::from(Json{{"version", 1}, {"session_generation", generation_},
        {"subscription_id", std::to_string(id)}, {"generation", 1}, {"event", "error"}, {"value", nullptr},
        {"metadata", {{"error", *failure}}}}, NativeOutput::control_frame_limit);
      if (!output_.control(terminal)) throw InvalidFrame();
    }
    const auto barrier = EncodedFrame::from(Json{{"version", 1}, {"session_generation", generation_},
      {"subscription_id", std::to_string(id)}, {"generation", 1}, {"event", "stream_retired"},
      {"last_report_sequence", found->second.last_sequence}}, NativeOutput::control_frame_limit);
    if (!output_.control(barrier)) throw InvalidFrame();
    credits_.retire(id, found->second.last_sequence); streams_.erase(found); return true;
  }

  void acknowledge(const Json &frame) {
    if (!frame.is_object() || !frame.contains("report_sequence") ||
        !integer(frame.at("report_sequence"), 1, output_.transmitted_report_sequence())) throw InvalidFrame();
    credits_.acknowledge(frame); drain();
  }
  std::size_t active_streams() const { return streams_.size(); }
  std::size_t credit_records() const { return credits_.stream_records(); }
  std::size_t queued_reports() const { return queued_.size(); }
  std::size_t queued_bytes() const { return queued_bytes_; }
  std::size_t available_frames() const { return credits_.available_frames(); }
  std::size_t available_bytes() const { return credits_.available_bytes(); }
};
} // namespace wotex::ble
