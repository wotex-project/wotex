#include "wotex_matter/subscription.hpp"

#include <algorithm>
#include <limits>
#include <set>
#include <tuple>
#include <utility>

namespace wotex::matter {
namespace {

constexpr std::size_t kSessionReportCredit = 64;
constexpr std::size_t kSessionByteCredit = 1048576;
constexpr std::size_t kStreamReportCredit = 16;
constexpr std::size_t kMaximumQueuedReports = 64;
constexpr std::size_t kMaximumQueuedBytes = 1048576;

bool SamePath(const ConcretePath &left, const ConcretePath &right) {
  return left.fabric_id == right.fabric_id && left.node_id == right.node_id &&
      left.endpoint == right.endpoint && left.cluster == right.cluster &&
      left.member == right.member;
}

bool Matches(const PathSelector &selector, const ConcretePath &path) {
  return selector.fabric_id == path.fabric_id && selector.node_id == path.node_id &&
      selector.endpoint == path.endpoint && selector.cluster == path.cluster &&
      selector.member == path.member;
}

bool AdmittedRecipe(SubscriptionKind kind, std::uint32_t cluster,
                    std::uint32_t member) {
  if (kind == SubscriptionKind::Event) {
    return cluster == 0x0039U && member == 0x0003U;
  }
  return (cluster == 0x0201U && member == 0x0000U) ||
      (cluster == 0x0006U && member == 0x0000U) ||
      (cluster == 0x0039U && member == 0x0011U) ||
      (cluster == 0x0402U && member == 0x0000U);
}

} // namespace

bool valid_subscription_request(const SubscriptionRequest &request) {
  if (request.subscription_id.size() != 32 || request.fabric_id == 0 ||
      request.node_id == 0 || request.paths.empty() || request.paths.size() > 64 ||
      request.min_interval_s > request.max_interval_s ||
      request.max_interval_s == 0 || request.queue_limit == 0 ||
      request.queue_limit > 10000 || request.timeout_ms == 0 ||
      request.timeout_ms > 60000) {
    return false;
  }
  if (!std::all_of(request.subscription_id.begin(), request.subscription_id.end(),
                   [](unsigned char byte) {
                     return (byte >= '0' && byte <= '9') ||
                         (byte >= 'a' && byte <= 'f');
                   })) {
    return false;
  }
  std::set<std::tuple<std::uint16_t, std::uint32_t, std::uint32_t>> paths;
  for (const PathSelector &path : request.paths) {
    if (path.fabric_id != request.fabric_id || path.node_id != request.node_id ||
        !path.endpoint || !path.cluster || !path.member ||
        !AdmittedRecipe(request.kind, *path.cluster, *path.member) ||
        !paths.emplace(*path.endpoint, *path.cluster, *path.member).second) {
      return false;
    }
  }
  return true;
}

bool valid_subscription_report(const SubscriptionRequest &request,
                               const SubscriptionReport &report) {
  if (report.subscription_id != request.subscription_id ||
      report.generation == 0 || report.kind != request.kind ||
      report.report_id == 0 || report.max_interval_s == 0 ||
      report.min_interval_s > report.max_interval_s) {
    return false;
  }
  const bool kind = request.kind == SubscriptionKind::Attribute
      ? report.result.attribute.has_value() && !report.result.event &&
            !report.result.error
      : report.result.event.has_value() && !report.result.attribute &&
            !report.result.error;
  return kind && std::any_of(request.paths.begin(), request.paths.end(),
                             [&report](const PathSelector &path) {
                               return Matches(path, report.result.path);
                             });
}

SubscriptionBuffer::SubscriptionBuffer(SubscriptionRequest request)
    : request_(std::move(request)) {}

void SubscriptionBuffer::BeginReport() {
  if (!active_ || in_report_ || report_id_ == std::numeric_limits<std::uint64_t>::max()) {
    active_ = false;
    return;
  }
  ++report_id_;
  in_report_ = true;
  current_attribute_paths_.clear();
  current_event_ids_.clear();
}

bool SubscriptionBuffer::Add(PathResult result) {
  if (!active_ || !in_report_) {
    return false;
  }
  if (DuplicateInCurrentReport(result) || SuppressedDuplicate(result)) {
    return true;
  }

  SubscriptionReport report;
  report.subscription_id = request_.subscription_id;
  report.generation = generation_;
  report.kind = request_.kind;
  report.result = std::move(result);
  report.initial = !established_;
  report.report_id = report_id_;
  report.min_interval_s = established_ ? revised_min_interval_s_
                                       : request_.min_interval_s;
  report.max_interval_s = established_ ? revised_max_interval_s_
                                       : request_.max_interval_s;
  report.sdk_subscription_id = sdk_subscription_id_;

  if (!valid_subscription_report(request_, report) ||
      buffered_.size() + ready_.size() >= request_.queue_limit) {
    active_ = false;
    return false;
  }

  if (request_.kind == SubscriptionKind::Attribute) {
    current_attribute_paths_.push_back(report.result.path);
    if (!established_) {
      initial_attribute_paths_.push_back(report.result.path);
    }
  } else {
    current_event_ids_.emplace_back(report.result.path,
                                    report.result.event->event_number);
    event_id_cache_.emplace_back(report.result.path,
                                 report.result.event->event_number);
    if (event_id_cache_.size() > 1024) {
      event_id_cache_.pop_front();
    }
  }

  if (activated_) {
    ready_.push_back(std::move(report));
  } else {
    buffered_.push_back(std::move(report));
  }
  return true;
}

void SubscriptionBuffer::EndReport() { in_report_ = false; }

bool SubscriptionBuffer::Establish(std::uint32_t sdk_subscription_id,
                                   std::uint16_t revised_min_interval_s,
                                   std::uint16_t revised_max_interval_s) {
  if (!active_ || established_ || revised_max_interval_s == 0 ||
      revised_min_interval_s > revised_max_interval_s) {
    active_ = false;
    return false;
  }
  sdk_subscription_id_ = sdk_subscription_id;
  revised_min_interval_s_ = revised_min_interval_s;
  revised_max_interval_s_ = revised_max_interval_s;
  established_ = true;
  for (SubscriptionReport &report : buffered_) {
    report.sdk_subscription_id = sdk_subscription_id_;
    report.min_interval_s = revised_min_interval_s_;
    report.max_interval_s = revised_max_interval_s_;
  }
  return true;
}

bool SubscriptionBuffer::PrepareRecovery(std::uint64_t generation) {
  if (!active_ || generation == 0 ||
      generation_ == std::numeric_limits<std::uint64_t>::max() ||
      generation != generation_ + 1) {
    active_ = false;
    return false;
  }
  generation_ = generation;
  report_id_ = 0;
  sdk_subscription_id_ = 0;
  revised_min_interval_s_ = 0;
  revised_max_interval_s_ = 0;
  in_report_ = false;
  established_ = false;
  activated_ = false;
  buffered_.clear();
  ready_.clear();
  current_attribute_paths_.clear();
  current_event_ids_.clear();
  initial_attribute_paths_.clear();
  return true;
}

void SubscriptionBuffer::Activate() {
  if (!active_ || !established_ || activated_) {
    return;
  }
  activated_ = true;
  while (!buffered_.empty()) {
    ready_.push_back(std::move(buffered_.front()));
    buffered_.pop_front();
  }
}

void SubscriptionBuffer::Cancel() {
  active_ = false;
  buffered_.clear();
  ready_.clear();
}

bool SubscriptionBuffer::active() const { return active_; }
bool SubscriptionBuffer::established() const { return established_; }
std::uint64_t SubscriptionBuffer::generation() const { return generation_; }

std::vector<SubscriptionReport> SubscriptionBuffer::TakeReady() {
  std::vector<SubscriptionReport> reports;
  reports.swap(ready_);
  return reports;
}

bool SubscriptionBuffer::DuplicateInCurrentReport(const PathResult &result) const {
  if (request_.kind == SubscriptionKind::Attribute) {
    return std::any_of(current_attribute_paths_.begin(),
                       current_attribute_paths_.end(),
                       [&result](const ConcretePath &path) {
                         return SamePath(path, result.path);
                       });
  }
  if (!result.event) {
    return false;
  }
  return std::any_of(current_event_ids_.begin(), current_event_ids_.end(),
                     [&result](const auto &identity) {
                       return SamePath(identity.first, result.path) &&
                           identity.second == result.event->event_number;
                     });
}

bool SubscriptionBuffer::SuppressedDuplicate(const PathResult &result) {
  if (request_.kind == SubscriptionKind::Attribute) {
    return !established_ &&
        std::any_of(initial_attribute_paths_.begin(),
                    initial_attribute_paths_.end(),
                    [&result](const ConcretePath &path) {
                      return SamePath(path, result.path);
                    });
  }
  if (!result.event) {
    return false;
  }
  return std::any_of(event_id_cache_.begin(), event_id_cache_.end(),
                     [&result](const auto &identity) {
                       return SamePath(identity.first, result.path) &&
                           identity.second == result.event->event_number;
                     });
}

SubscriptionRecovery::SubscriptionRecovery(bool enabled) : enabled_(enabled) {}

SubscriptionRecovery::Decision SubscriptionRecovery::Next(std::uint64_t now_ms) {
  if (!enabled_) {
    return {Action::Disabled, generation_, 0, 0};
  }
  if (!recovering_) {
    if (generation_ == std::numeric_limits<std::uint64_t>::max()) {
      return {Action::Exhausted, generation_, 0, 0};
    }
    recovering_ = true;
    started_ms_ = now_ms;
    attempts_ = 0;
    ++generation_;
  }
  const std::uint64_t elapsed = now_ms >= started_ms_ ? now_ms - started_ms_ : 0;
  if (elapsed >= kMaximumDurationMs || attempts_ >= kMaximumAttempts) {
    return {Action::Exhausted, generation_, attempts_, 0};
  }
  ++attempts_;
  return {Action::Retry, generation_, attempts_,
          static_cast<std::uint32_t>(kMaximumDurationMs - elapsed)};
}

void SubscriptionRecovery::Established() {
  recovering_ = false;
  started_ms_ = 0;
  attempts_ = 0;
}

void SubscriptionRecovery::Cancel() {
  enabled_ = false;
  Established();
}

bool SubscriptionRecovery::recovering() const { return recovering_; }
std::uint64_t SubscriptionRecovery::generation() const { return generation_; }

ReportCreditManager::ReportCreditManager(std::string session_generation,
                                         Transmit transmit)
    : session_generation_(std::move(session_generation)),
      transmit_(std::move(transmit)) {}

std::string ReportCreditManager::Key(const std::string &subscription_id,
                                     std::uint64_t generation) const {
  return subscription_id + ":" + std::to_string(generation);
}

bool ReportCreditManager::AddStream(const std::string &subscription_id,
                                    std::uint64_t generation,
                                    std::size_t queue_limit) {
  const std::string key = Key(subscription_id, generation);
  const std::size_t live_streams =
      static_cast<std::size_t>(std::count_if(
          streams_.begin(), streams_.end(),
          [](const auto &entry) { return entry.second.live; }));
  if (subscription_id.empty() || generation == 0 || queue_limit == 0 ||
      queue_limit > 10000 || live_streams >= 64 || streams_.size() >= 128 ||
      streams_.count(key) != 0) {
    return false;
  }
  streams_.emplace(key, Stream{generation, queue_limit});
  return true;
}

bool ReportCreditManager::BeginRecovery(const std::string &subscription_id,
                                        std::uint64_t previous_generation,
                                        std::uint64_t next_generation,
                                        std::size_t queue_limit,
                                        std::string barrier) {
  if (next_generation == 0 || previous_generation == next_generation ||
      streams_.count(Key(subscription_id, next_generation)) != 0) {
    return false;
  }
  if (!Retire(subscription_id, previous_generation, std::move(barrier))) {
    return false;
  }
  return AddStream(subscription_id, next_generation, queue_limit);
}

bool ReportCreditManager::CanTransmit(const Stream &stream,
                                      std::size_t bytes) const {
  return outstanding_.size() < kSessionReportCredit &&
      outstanding_bytes_ <= kSessionByteCredit &&
      bytes <= kSessionByteCredit - outstanding_bytes_ &&
      stream.outstanding < std::min(kStreamReportCredit, stream.queue_limit);
}

ReportCreditManager::SubmitResult ReportCreditManager::Submit(
    const std::string &subscription_id, std::uint64_t generation,
    const std::function<std::string(std::uint64_t)> &encode) {
  auto stream = streams_.find(Key(subscription_id, generation));
  if (stream == streams_.end() || !stream->second.live ||
      next_sequence_ == std::numeric_limits<std::uint64_t>::max()) {
    return SubmitResult::Invalid;
  }
  const std::uint64_t sequence = next_sequence_;
  std::string encoded = encode(sequence);
  const std::size_t bytes = encoded.size() + 1;
  if (encoded.empty() || bytes > kSessionByteCredit) {
    return SubmitResult::StreamOverflow;
  }
  Frame frame{subscription_id, generation, sequence, std::move(encoded), encode,
              0};
  if (CanTransmit(stream->second, bytes) && queued_.empty()) {
    return TransmitFrame(std::move(frame)) ? SubmitResult::Transmitted
                                           : SubmitResult::Invalid;
  }
  frame.sequence = 0;
  frame.encoded = encode(std::numeric_limits<std::uint64_t>::max());
  const std::size_t queued_bytes = frame.encoded.size() + 1;
  if (queued_.size() >= kMaximumQueuedReports ||
      queued_bytes_ > kMaximumQueuedBytes ||
      queued_bytes > kMaximumQueuedBytes - queued_bytes_ ||
      stream->second.queued >= stream->second.queue_limit) {
    return SubmitResult::StreamOverflow;
  }
  queued_bytes_ += queued_bytes;
  ++stream->second.queued;
  queued_.push_back(std::move(frame));
  return SubmitResult::Queued;
}

bool ReportCreditManager::TransmitFrame(Frame frame) {
  auto stream = streams_.find(Key(frame.subscription_id, frame.generation));
  if (stream == streams_.end() || !stream->second.live ||
      next_sequence_ == std::numeric_limits<std::uint64_t>::max()) {
    return false;
  }
  frame.sequence = next_sequence_;
  frame.encoded = frame.encode(frame.sequence);
  if (frame.encoded.empty() || frame.encoded.size() + 1 > kSessionByteCredit ||
      !transmit_(frame.encoded)) {
    return false;
  }
  ++next_sequence_;
  const std::size_t bytes = frame.encoded.size() + 1;
  cumulative_transmitted_bytes_ += bytes;
  frame.cumulative_bytes = cumulative_transmitted_bytes_;
  outstanding_bytes_ += bytes;
  ++stream->second.outstanding;
  stream->second.last_transmitted = frame.sequence;
  outstanding_.push_back(std::move(frame));
  return true;
}

bool ReportCreditManager::Acknowledge(std::uint64_t report_sequence,
                                      std::uint64_t acknowledged_bytes) {
  if (report_sequence <= acknowledged_sequence_ || outstanding_.empty()) {
    return false;
  }
  auto target = std::find_if(outstanding_.begin(), outstanding_.end(),
                             [report_sequence](const Frame &frame) {
                               return frame.sequence == report_sequence;
                             });
  if (target == outstanding_.end() || target->cumulative_bytes != acknowledged_bytes) {
    return false;
  }
  while (!outstanding_.empty() && outstanding_.front().sequence <= report_sequence) {
    Frame frame = std::move(outstanding_.front());
    outstanding_.pop_front();
    const std::size_t bytes = frame.encoded.size() + 1;
    outstanding_bytes_ -= bytes;
    auto stream = streams_.find(Key(frame.subscription_id, frame.generation));
    if (stream != streams_.end() && stream->second.outstanding > 0) {
      --stream->second.outstanding;
      if (!stream->second.live && stream->second.outstanding == 0 &&
          stream->second.queued == 0) {
        streams_.erase(stream);
      }
    }
  }
  acknowledged_sequence_ = report_sequence;
  acknowledged_bytes_ = acknowledged_bytes;
  return Drain();
}

bool ReportCreditManager::Drain() {
  while (!queued_.empty()) {
    Frame frame = std::move(queued_.front());
    auto stream = streams_.find(Key(frame.subscription_id, frame.generation));
    if (stream == streams_.end() || !stream->second.live) {
      queued_bytes_ -= frame.encoded.size() + 1;
      queued_.pop_front();
      continue;
    }
    const std::string encoded = frame.encode(next_sequence_);
    if (!CanTransmit(stream->second, encoded.size() + 1)) {
      break;
    }
    queued_bytes_ -= frame.encoded.size() + 1;
    --stream->second.queued;
    queued_.pop_front();
    if (!TransmitFrame(std::move(frame))) {
      return false;
    }
  }
  return true;
}

bool ReportCreditManager::Retire(const std::string &subscription_id,
                                 std::uint64_t generation,
                                 std::string barrier) {
  auto stream = streams_.find(Key(subscription_id, generation));
  if (stream == streams_.end() || !stream->second.live) {
    return false;
  }
  stream->second.live = false;
  for (auto iterator = queued_.begin(); iterator != queued_.end();) {
    if (iterator->subscription_id == subscription_id &&
        iterator->generation == generation) {
      queued_bytes_ -= iterator->encoded.size() + 1;
      --stream->second.queued;
      iterator = queued_.erase(iterator);
    } else {
      ++iterator;
    }
  }
  if (!transmit_(barrier)) {
    return false;
  }
  if (stream->second.outstanding == 0) {
    streams_.erase(stream);
  }
  return Drain();
}

bool ReportCreditManager::IsLive(const std::string &subscription_id,
                                 std::uint64_t generation) const {
  const auto stream = streams_.find(Key(subscription_id, generation));
  return stream != streams_.end() && stream->second.live;
}

std::uint64_t ReportCreditManager::last_transmitted(
    const std::string &subscription_id, std::uint64_t generation) const {
  const auto stream = streams_.find(Key(subscription_id, generation));
  return stream == streams_.end() ? 0 : stream->second.last_transmitted;
}

} // namespace wotex::matter
