#ifndef WOTEX_MATTER_SUBSCRIPTION_HPP
#define WOTEX_MATTER_SUBSCRIPTION_HPP

#include "wotex_matter/interaction.hpp"

#include <cstdint>
#include <deque>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace wotex::matter {

enum class SubscriptionKind { Attribute, Event };

struct SubscriptionRequest {
  std::string subscription_id;
  SubscriptionKind kind{SubscriptionKind::Attribute};
  std::uint64_t fabric_id{0};
  std::uint64_t node_id{0};
  std::vector<PathSelector> paths{};
  std::uint16_t min_interval_s{1};
  std::uint16_t max_interval_s{60};
  bool resubscribe{false};
  std::uint16_t queue_limit{1000};
  std::uint32_t timeout_ms{0};
};

struct SubscriptionResponse {
  bool ok{false};
  std::string error_code;
  std::string subscription_id;
  std::uint64_t generation{0};
  std::uint16_t min_interval_s{0};
  std::uint16_t max_interval_s{0};
  std::uint32_t sdk_subscription_id{0};
};

struct SubscriptionReport {
  std::string subscription_id;
  std::uint64_t generation{0};
  SubscriptionKind kind{SubscriptionKind::Attribute};
  PathResult result{};
  bool initial{false};
  std::uint64_t report_id{0};
  std::uint16_t min_interval_s{0};
  std::uint16_t max_interval_s{0};
  std::uint32_t sdk_subscription_id{0};
};

enum class SubscriptionStatusKind { Resubscribing, Resubscribed };
enum class SubscriptionContinuity { Lost, Unknown };

struct SubscriptionStatus {
  std::string subscription_id;
  std::uint64_t generation{0};
  SubscriptionStatusKind status{SubscriptionStatusKind::Resubscribing};
  SubscriptionContinuity continuity{SubscriptionContinuity::Lost};
  std::uint8_t attempt{0};
  std::uint16_t min_interval_s{0};
  std::uint16_t max_interval_s{0};
  std::uint32_t sdk_subscription_id{0};
};

bool valid_subscription_request(const SubscriptionRequest &request);
bool valid_subscription_report(const SubscriptionRequest &request,
                               const SubscriptionReport &report);

class SubscriptionBuffer final {
 public:
  explicit SubscriptionBuffer(SubscriptionRequest request);

  void BeginReport();
  bool Add(PathResult result);
  void EndReport();
  bool Establish(std::uint32_t sdk_subscription_id,
                 std::uint16_t revised_min_interval_s,
                 std::uint16_t revised_max_interval_s);
  bool PrepareRecovery(std::uint64_t generation);
  void Activate();
  void Cancel();
  bool active() const;
  bool established() const;
  std::uint64_t generation() const;
  std::vector<SubscriptionReport> TakeReady();

 private:
  bool DuplicateInCurrentReport(const PathResult &result) const;
  bool SuppressedDuplicate(const PathResult &result);

  SubscriptionRequest request_;
  std::deque<SubscriptionReport> buffered_;
  std::vector<SubscriptionReport> ready_;
  std::vector<ConcretePath> current_attribute_paths_;
  std::vector<std::pair<ConcretePath, std::uint64_t>> current_event_ids_;
  std::vector<ConcretePath> initial_attribute_paths_;
  std::deque<std::pair<ConcretePath, std::uint64_t>> event_id_cache_;
  std::uint64_t generation_{1};
  std::uint64_t report_id_{0};
  std::uint32_t sdk_subscription_id_{0};
  std::uint16_t revised_min_interval_s_{0};
  std::uint16_t revised_max_interval_s_{0};
  bool in_report_{false};
  bool established_{false};
  bool activated_{false};
  bool active_{true};
};

class SubscriptionRecovery final {
 public:
  enum class Action { Disabled, Retry, Exhausted };

  struct Decision {
    Action action{Action::Disabled};
    std::uint64_t generation{1};
    std::uint8_t attempt{0};
    std::uint32_t remaining_ms{0};
  };

  explicit SubscriptionRecovery(bool enabled);
  Decision Next(std::uint64_t now_ms);
  void Established();
  void Cancel();
  bool recovering() const;
  std::uint64_t generation() const;

 private:
  static constexpr std::uint8_t kMaximumAttempts = 5;
  static constexpr std::uint32_t kMaximumDurationMs = 60000;

  bool enabled_{false};
  bool recovering_{false};
  std::uint64_t started_ms_{0};
  std::uint64_t generation_{1};
  std::uint8_t attempts_{0};
};

class ReportCreditManager final {
 public:
  enum class SubmitResult { Transmitted, Queued, StreamOverflow, Invalid };
  using Transmit = std::function<bool(const std::string &)>;

  ReportCreditManager(std::string session_generation, Transmit transmit);
  bool AddStream(const std::string &subscription_id, std::uint64_t generation,
                 std::size_t queue_limit);
  bool BeginRecovery(const std::string &subscription_id,
                     std::uint64_t previous_generation,
                     std::uint64_t next_generation, std::size_t queue_limit,
                     std::string barrier);
  SubmitResult Submit(const std::string &subscription_id,
                      std::uint64_t generation,
                      const std::function<std::string(std::uint64_t)> &encode);
  bool Acknowledge(std::uint64_t report_sequence,
                   std::uint64_t acknowledged_bytes);
  bool Retire(const std::string &subscription_id, std::uint64_t generation,
              std::string barrier);
  bool IsLive(const std::string &subscription_id, std::uint64_t generation) const;
  std::uint64_t last_transmitted(const std::string &subscription_id,
                                 std::uint64_t generation) const;

 private:
  struct Stream {
    std::uint64_t generation{0};
    std::size_t queue_limit{0};
    std::size_t outstanding{0};
    std::size_t queued{0};
    std::uint64_t last_transmitted{0};
    bool live{true};
  };
  struct Frame {
    std::string subscription_id;
    std::uint64_t generation{0};
    std::uint64_t sequence{0};
    std::string encoded;
    std::function<std::string(std::uint64_t)> encode;
    std::uint64_t cumulative_bytes{0};
  };

  std::string Key(const std::string &subscription_id,
                  std::uint64_t generation) const;
  bool CanTransmit(const Stream &stream, std::size_t bytes) const;
  bool TransmitFrame(Frame frame);
  bool Drain();

  std::string session_generation_;
  Transmit transmit_;
  std::unordered_map<std::string, Stream> streams_;
  std::deque<Frame> queued_;
  std::deque<Frame> outstanding_;
  std::uint64_t next_sequence_{1};
  std::uint64_t cumulative_transmitted_bytes_{0};
  std::uint64_t acknowledged_sequence_{0};
  std::uint64_t acknowledged_bytes_{0};
  std::size_t queued_bytes_{0};
  std::size_t outstanding_bytes_{0};
};

} // namespace wotex::matter

#endif
