#ifndef WOTEX_MATTER_BRIDGE_HANDOFF_HPP
#define WOTEX_MATTER_BRIDGE_HANDOFF_HPP

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace wotex::matter {

// Internal, serialized request custody. The native owner supplies one process
// generation and times from one monotonic clock. Tickets never grant policy
// authority or publish observations. Each reserved slot remains occupied until
// the SDK owner consumes it, including after expiry or closure. Associated SDK
// contexts must remain owned for that entire interval.
class BridgeConsumerHandoff final {
 public:
  static constexpr std::size_t kCapacity = 16;
  static constexpr std::uint64_t kMaximumDurationMs = 500;
  using Generation = std::array<std::uint8_t, 16>;

  struct Ticket {
    Generation generation{};
    std::uint64_t id{0};
  };
  enum class Admission { Reserved, InvalidDeadline, InvalidClock, Busy, Exhausted, Closed };
  // Completed is a consumer logical result, never evidence of a physical effect.
  enum class Outcome { Completed, Denied, Failed, Unknown, TimedOut, Closed };
  enum class Reply { Stored, Late, Duplicate, UnknownTicket, InvalidOutcome, InvalidClock, Closed };
  enum class Consume { Pending, Completed, UnknownTicket, InvalidClock };
  enum class ClockSample { Sampled, InvalidGeneration, InvalidClock, Closed };

  explicit BridgeConsumerHandoff(Generation generation);
  BridgeConsumerHandoff(const BridgeConsumerHandoff &) = delete;
  BridgeConsumerHandoff &operator=(const BridgeConsumerHandoff &) = delete;

  Admission Reserve(std::uint64_t now_ms, std::uint64_t deadline_ms, Ticket &ticket);
  Reply Resolve(const Ticket &ticket, Outcome outcome, std::uint64_t received_ms);
  Consume Take(const Ticket &ticket, std::uint64_t now_ms, Outcome &outcome);
  // Samples share the custody clock history, without reserving or retiring a
  // request. A supplied generation must match even when custody is idle.
  ClockSample Sample(const Generation &generation, std::uint64_t now_ms);
  std::optional<std::uint64_t> Deadline(const Ticket &ticket) const;
  void Close();
  bool closed() const;
  std::size_t pending() const;

 private:
  // Test access changes only counter cutpoints; production has no seeding API.
  friend struct BridgeConsumerHandoffTestAccess;
  struct Entry {
    std::uint64_t id{0};
    std::uint64_t deadline_ms{0};
    std::optional<Outcome> outcome;
  };
  Entry *Find(const Ticket &ticket);
  const Entry *Find(const Ticket &ticket) const;
  bool AcceptTime(std::uint64_t now_ms);

  const Generation generation_;
  std::array<Entry, kCapacity> entries_{};
  std::uint64_t greatest_id_{0};
  std::optional<std::uint64_t> last_time_ms_;
  std::size_t pending_{0};
  bool closed_{false};
};

} // namespace wotex::matter

#endif
