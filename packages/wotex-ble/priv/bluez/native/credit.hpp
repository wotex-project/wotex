// SPDX-License-Identifier: Apache-2.0
// Native report reservations outlive a cancelled stream until an exact cumulative
// acknowledgement returns their credits. Storage depends only on active streams
// and at most 64 outstanding reports, not on session lifetime or churn.
#pragma once
#include "frame.hpp"
#include <deque>
#include <map>
#include <optional>

namespace wotex::ble {
class Credits {
  struct Stream {
    std::size_t window;
    std::size_t outstanding = 0;
    std::uint64_t last_sequence = 0;
    bool live = true;
  };
  struct Record {
    std::uint64_t sequence;
    std::uint64_t stream;
    std::size_t bytes;
  };
  std::string generation_;
  std::map<std::uint64_t, Stream> streams_;
  std::deque<Record> records_;
  std::size_t live_ = 0;
  std::size_t bytes_ = 0;
  std::uint64_t greatest_stream_ = 0;
  std::uint64_t sequence_ = 0;
  std::uint64_t sent_bytes_ = 0;
  std::uint64_t ack_sequence_ = 0;
  std::uint64_t ack_bytes_ = 0;
public:
  static constexpr std::size_t frame_limit = 64;
  static constexpr std::size_t byte_limit = 1048576;

  explicit Credits(std::string generation) : generation_(std::move(generation)) {
    if (generation_.size() != 32 ||
        !std::all_of(generation_.begin(), generation_.end(), [](char c) {
          return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        })) throw InvalidFrame();
  }

  bool open(std::uint64_t identifier, std::size_t queue_limit) {
    if (identifier == 0 || identifier <= greatest_stream_ ||
        queue_limit == 0 || queue_limit > 10000) throw InvalidFrame();
    if (live_ == 64) return false;
    greatest_stream_ = identifier;
    streams_.emplace(identifier, Stream{std::min<std::size_t>(16, queue_limit)});
    ++live_;
    return true;
  }

  // The caller computes bytes from the exact encoded line for next_sequence().
  // A null reservation leaves ownership with its bounded unsent-report queue.
  std::optional<std::uint64_t> reserve(std::uint64_t identifier, std::size_t bytes) {
    auto stream = streams_.find(identifier);
    if (stream == streams_.end() || !stream->second.live || bytes == 0 ||
        bytes > max_line) throw InvalidFrame();
    if (records_.size() == frame_limit || bytes > byte_limit - bytes_ ||
        stream->second.outstanding == stream->second.window) return std::nullopt;
    if (sequence_ == UINT64_MAX || bytes > UINT64_MAX - sent_bytes_)
      throw InvalidFrame();
    const auto next = sequence_ + 1;
    records_.push_back({next, identifier, bytes});
    sequence_ = next;
    sent_bytes_ += bytes;
    bytes_ += bytes;
    ++stream->second.outstanding;
    stream->second.last_sequence = next;
    return next;
  }

  void acknowledge(const std::string &generation, std::uint64_t sequence,
                   std::uint64_t bytes) {
    if (generation != generation_ || sequence <= ack_sequence_ ||
        sequence > sequence_) throw InvalidFrame();
    std::uint64_t expected_bytes = ack_bytes_;
    for (const auto &record : records_) {
      if (record.sequence > sequence) break;
      expected_bytes += record.bytes;
    }
    if (expected_bytes != bytes) throw InvalidFrame();
    while (!records_.empty() && records_.front().sequence <= sequence) {
      const auto record = records_.front();
      auto stream = streams_.find(record.stream);
      --stream->second.outstanding;
      if (!stream->second.live && stream->second.outstanding == 0) streams_.erase(stream);
      bytes_ -= record.bytes;
      records_.pop_front();
    }
    ack_sequence_ = sequence;
    ack_bytes_ = bytes;
  }

  void acknowledge(const Json &frame) {
    if (!fields(frame, {"version", "event", "session_generation", "report_sequence",
                        "acknowledged_bytes"}) ||
        !integer(frame["version"], 1, 1) || frame["event"] != "report_ack" ||
        !frame["session_generation"].is_string() ||
        !integer(frame["report_sequence"], 1, UINT64_MAX) ||
        !integer(frame["acknowledged_bytes"], 1, UINT64_MAX)) throw InvalidFrame();
    acknowledge(frame["session_generation"].get<std::string>(),
                frame["report_sequence"].get<std::uint64_t>(),
                frame["acknowledged_bytes"].get<std::uint64_t>());
  }

  // Retiring a stream never refunds outstanding credits. Its barrier marks only
  // that stream; another live stream still controls its own acknowledgement.
  void retire(std::uint64_t identifier, std::uint64_t last_sequence) {
    auto stream = streams_.find(identifier);
    if (stream == streams_.end() || !stream->second.live ||
        stream->second.last_sequence != last_sequence) throw InvalidFrame();
    stream->second.live = false;
    --live_;
    if (stream->second.outstanding == 0) streams_.erase(stream);
  }

  std::uint64_t next_sequence() const {
    if (sequence_ == UINT64_MAX) throw InvalidFrame();
    return sequence_ + 1;
  }
  std::size_t available_frames() const { return frame_limit - records_.size(); }
  std::size_t available_bytes() const { return byte_limit - bytes_; }
  std::size_t stream_records() const { return streams_.size(); }
  std::size_t active_streams() const { return live_; }
};
} // namespace wotex::ble
