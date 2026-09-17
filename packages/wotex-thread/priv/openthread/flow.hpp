#ifndef WOTEX_THREAD_FLOW_HPP
#define WOTEX_THREAD_FLOW_HPP

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <limits>
#include <map>
#include <string>
#include <utility>

namespace wotex::thread {
constexpr std::size_t kSessionReportFrames = 64;
constexpr std::size_t kSessionReportBytes = 1048576;
constexpr std::size_t kStreamReportFrames = 16;
constexpr std::size_t kQueuedReportFrames = 64;
constexpr std::size_t kQueuedReportBytes = 1048576;
constexpr std::size_t kMaximumReportLine = 131072;
constexpr std::size_t kMaximumQueueLimit = 10000;
constexpr std::size_t kMaximumLiveStreams = 64;

inline bool session_generation(const std::string &value) {
  return value.size() == 32 && std::all_of(value.begin(), value.end(), [](char byte) {
           return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
         });
}

// Report frame and byte credit for one IPC session generation. A stream is a
// subscription ID plus its delivery generation. Transmitted records stay
// outstanding until the owner's exact cumulative acknowledgement; queued reports
// are encoded again with their assigned sequence when credit becomes available.
// Sequence 2^64-1 is never assigned; reaching it exhausts the generation.
class ReportFlow final {
 public:
  enum class Submission { transmitted, queued, overflow, failed };
  using Encoder = std::function<std::string(std::uint64_t report_sequence)>;
  using BarrierEncoder = std::function<std::string(std::uint64_t last_report_sequence)>;
  using Writer = std::function<bool(const std::string &frame)>;

  struct Snapshot {
    std::size_t queued = 0;
    std::size_t queued_bytes = 0;
    std::size_t frame_credit = kSessionReportFrames;
    std::size_t byte_credit = kSessionReportBytes;
    std::uint64_t acknowledged_sequence = 0;
    std::uint64_t last_sequence = 0;
  };

  // Reports and retirement barriers use distinct writers so the owner can
  // charge barriers to its separate control reservation.
  ReportFlow(std::string session, Writer report, Writer control)
      : session_(std::move(session)), report_(std::move(report)), control_(std::move(control)) {}

  bool add_stream(const std::string &subscription, std::uint64_t generation, std::size_t queue_limit) {
    if (failed_ || subscription.empty() || subscription.size() > 64 || generation == 0 ||
        queue_limit == 0 || queue_limit > kMaximumQueueLimit || live_ >= kMaximumLiveStreams ||
        streams_.count({subscription, generation}) != 0) return false;
    streams_.emplace(Key{subscription, generation}, Stream{queue_limit});
    ++live_;
    return true;
  }

  bool live(const std::string &subscription, std::uint64_t generation) const {
    const auto stream = streams_.find({subscription, generation});
    return stream != streams_.end() && stream->second.live;
  }

  Submission submit(const std::string &subscription, std::uint64_t generation, const Encoder &encode) {
    const Key key{subscription, generation};
    auto stream = streams_.find(key);
    if (failed_ || stream == streams_.end() || !stream->second.live) return Submission::failed;
    if (stream->second.queued == 0 && available(stream->second)) {
      std::string frame = encode(next_sequence_);
      if (frame.empty() || frame.size() >= kMaximumReportLine) return Submission::overflow;
      if (frame.size() + 1 <= kSessionReportBytes - outstanding_bytes_) {
        return transmit(key, stream->second, frame) ? Submission::transmitted : fail();
      }
    }
    // A queued report reserves its widest encoding: the maximum sequence.
    const std::size_t reserved = encode(std::numeric_limits<std::uint64_t>::max()).size() + 1;
    if (reserved < 2 || reserved > kMaximumReportLine || queued_.size() >= kQueuedReportFrames ||
        reserved > kQueuedReportBytes - queued_bytes_ || stream->second.queued >= stream->second.queue_limit) {
      return Submission::overflow;
    }
    queued_.push_back(Pending{key, encode, reserved});
    queued_bytes_ += reserved;
    maximum_.queued = std::max(maximum_.queued, queued_.size());
    maximum_.queued_bytes = std::max(maximum_.queued_bytes, queued_bytes_);
    ++stream->second.queued;
    return Submission::queued;
  }

  // Releases the contiguous prefix only for the exact session, a transmitted
  // unacknowledged sequence and its exact cumulative encoded byte count.
  bool acknowledge(const std::string &session, std::uint64_t report_sequence, std::uint64_t acknowledged_bytes) {
    if (failed_ || session != session_ || report_sequence <= acknowledged_sequence_ ||
        report_sequence >= next_sequence_) return false;
    const auto target = std::find_if(outstanding_.begin(), outstanding_.end(),
                                      [report_sequence](const Record &record) { return record.sequence == report_sequence; });
    if (target == outstanding_.end() || target->cumulative_bytes != acknowledged_bytes) return false;
    while (!outstanding_.empty() && outstanding_.front().sequence <= report_sequence) {
      const Record record = outstanding_.front();
      outstanding_.pop_front();
      outstanding_bytes_ -= record.bytes;
      auto stream = streams_.find(record.key);
      --stream->second.outstanding;
      if (!stream->second.live && stream->second.outstanding == 0) streams_.erase(stream);
    }
    acknowledged_sequence_ = report_sequence;
    return drain();
  }

  // Stops new reports, discards unsent ones and writes exactly one barrier
  // naming the last transmitted sequence. Outstanding credit remains until an
  // ordinary acknowledgement covers it.
  bool retire(const std::string &subscription, std::uint64_t generation, const BarrierEncoder &encode) {
    const Key key{subscription, generation};
    auto stream = streams_.find(key);
    if (failed_ || stream == streams_.end() || !stream->second.live) return false;
    stream->second.live = false;
    --live_;
    for (auto pending = queued_.begin(); pending != queued_.end();) {
      if (pending->key == key) {
        queued_bytes_ -= pending->reserved;
        pending = queued_.erase(pending);
      } else {
        ++pending;
      }
    }
    stream->second.queued = 0;
    const std::string barrier = encode(stream->second.last_sequence);
    if (barrier.empty() || !control_(barrier)) return halt();
    if (stream->second.outstanding == 0) streams_.erase(stream);
    return drain();
  }

  // Highest simultaneous queued and outstanding report counts and bytes observed.
  struct Maximum {
    std::size_t queued = 0;
    std::size_t queued_bytes = 0;
    std::size_t outstanding = 0;
    std::size_t outstanding_bytes = 0;
  };
  Maximum maximum() const { return maximum_; }

  Snapshot snapshot() const {
    return {queued_.size(), queued_bytes_, kSessionReportFrames - outstanding_.size(),
            kSessionReportBytes - outstanding_bytes_, acknowledged_sequence_, next_sequence_ - 1};
  }
  const std::string &session() const { return session_; }
  bool failed() const { return failed_; }
  std::size_t retained_streams() const { return streams_.size(); }

#ifdef WOTEX_THREAD_FLOW_TESTING
  bool seed_counters_for_testing(std::uint64_t sequence, std::uint64_t bytes) {
    if (sequence == 0 || !outstanding_.empty() || !queued_.empty()) return false;
    next_sequence_ = sequence;
    acknowledged_sequence_ = sequence - 1;
    transmitted_bytes_ = bytes;
    return true;
  }
#endif

 private:
  using Key = std::pair<std::string, std::uint64_t>;
  struct Stream {
    std::size_t queue_limit;
    std::size_t outstanding = 0;
    std::size_t queued = 0;
    std::uint64_t last_sequence = 0;
    bool live = true;
  };
  struct Record {
    Key key;
    std::uint64_t sequence;
    std::size_t bytes;
    std::uint64_t cumulative_bytes;
  };
  struct Pending {
    Key key;
    Encoder encode;
    std::size_t reserved;
  };

  bool available(const Stream &stream) const {
    return outstanding_.size() < kSessionReportFrames &&
           stream.outstanding < std::min(kStreamReportFrames, stream.queue_limit);
  }

  Submission fail() {
    failed_ = true;
    return Submission::failed;
  }
  bool halt() {
    failed_ = true;
    return false;
  }

  bool transmit(const Key &key, Stream &stream, const std::string &frame) {
    const std::size_t bytes = frame.size() + 1;
    if (next_sequence_ == std::numeric_limits<std::uint64_t>::max() ||
        bytes > std::numeric_limits<std::uint64_t>::max() - transmitted_bytes_ || !report_(frame)) {
      return false;
    }
    transmitted_bytes_ += bytes;
    outstanding_.push_back(Record{key, next_sequence_, bytes, transmitted_bytes_});
    outstanding_bytes_ += bytes;
    maximum_.outstanding = std::max(maximum_.outstanding, outstanding_.size());
    maximum_.outstanding_bytes = std::max(maximum_.outstanding_bytes, outstanding_bytes_);
    stream.last_sequence = next_sequence_++;
    ++stream.outstanding;
    return true;
  }

  // Preserves order within each stream; a stream without credit cannot block
  // another stream's queued report.
  bool drain() {
    for (auto pending = queued_.begin(); pending != queued_.end();) {
      auto stream = streams_.find(pending->key);
      const bool first = std::none_of(queued_.begin(), pending,
                                      [&pending](const Pending &earlier) { return earlier.key == pending->key; });
      if (!first || !available(stream->second)) { ++pending; continue; }
      std::string frame = pending->encode(next_sequence_);
      if (frame.empty() || frame.size() + 1 > pending->reserved) return halt();
      if (frame.size() + 1 > kSessionReportBytes - outstanding_bytes_) { ++pending; continue; }
      queued_bytes_ -= pending->reserved;
      --stream->second.queued;
      pending = queued_.erase(pending);
      if (!transmit(stream->first, stream->second, frame)) return halt();
    }
    return true;
  }

  std::string session_;
  Writer report_;
  Writer control_;
  std::map<Key, Stream> streams_;
  std::deque<Record> outstanding_;
  std::deque<Pending> queued_;
  std::uint64_t next_sequence_ = 1;
  std::uint64_t acknowledged_sequence_ = 0;
  std::uint64_t transmitted_bytes_ = 0;
  std::size_t outstanding_bytes_ = 0;
  std::size_t queued_bytes_ = 0;
  std::size_t live_ = 0;
  Maximum maximum_{};
  bool failed_ = false;
};
}  // namespace wotex::thread
#endif
