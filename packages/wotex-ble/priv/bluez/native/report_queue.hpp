// SPDX-License-Identifier: Apache-2.0
// Reports without cumulative credit wait here in stream order. The queue owns
// only bounded payloads and admission charges; its caller owns credit, output
// and stream termination. No entry survives discard, and no lifetime history
// is retained after a stream leaves the queue.
#pragma once
#include "frame.hpp"
#include <deque>
#include <map>
#include <set>

namespace wotex::ble {
template <class Payload> class ReportQueue {
  struct Entry {
    std::uint64_t stream;
    Payload payload;
    std::size_t charge;
  };
  std::deque<Entry> entries_;
  std::map<std::uint64_t, std::size_t> streams_;
  std::size_t bytes_ = 0;

  void erase(typename std::deque<Entry>::iterator &entry) {
    const auto stream = streams_.find(entry->stream);
    if (--stream->second == 0) streams_.erase(stream);
    bytes_ -= entry->charge;
    entry = entries_.erase(entry);
  }

public:
  static constexpr std::size_t frame_limit = 64;
  static constexpr std::size_t byte_limit = 1048576;

  // A false result admits nothing. The caller terminates that stream instead of
  // dropping an arbitrary report or waiting for credit inside an SDK callback.
  bool admit(std::uint64_t stream, std::size_t stream_limit, Payload payload, std::size_t charge) {
    if (stream == 0 || stream_limit == 0 || stream_limit > 10000 || charge == 0 ||
        charge > byte_limit) throw InvalidFrame();
    if (queued(stream) == stream_limit || entries_.size() == frame_limit ||
        charge > byte_limit - bytes_) return false;
    entries_.push_back({stream, std::move(payload), charge});
    ++streams_[stream];
    bytes_ += charge;
    return true;
  }

  // Dispatch returns false when that stream lacks credit. The stream's later
  // entries then keep their order, while other streams may still progress.
  template <class Dispatch> void drain(Dispatch dispatch) {
    std::set<std::uint64_t> blocked;
    for (auto entry = entries_.begin(); entry != entries_.end();) {
      if (!blocked.count(entry->stream) && dispatch(entry->stream, entry->payload)) erase(entry);
      else { blocked.insert(entry->stream); ++entry; }
    }
  }

  void discard(std::uint64_t stream) {
    for (auto entry = entries_.begin(); entry != entries_.end();) {
      if (entry->stream == stream) erase(entry); else ++entry;
    }
  }

  std::size_t queued(std::uint64_t stream) const {
    const auto found = streams_.find(stream);
    return found == streams_.end() ? 0 : found->second;
  }
  std::size_t size() const { return entries_.size(); }
  std::size_t bytes() const { return bytes_; }
  std::size_t stream_records() const { return streams_.size(); }
};
} // namespace wotex::ble
