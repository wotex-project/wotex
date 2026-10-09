#include "wotex_matter/bridge_handoff.hpp"

#include <limits>

namespace wotex::matter {

BridgeConsumerHandoff::BridgeConsumerHandoff(Generation generation) : generation_(generation) {}

BridgeConsumerHandoff::Admission BridgeConsumerHandoff::Reserve(std::uint64_t now_ms,
                                                                std::uint64_t deadline_ms,
                                                                Ticket &ticket) {
  if (closed_) return Admission::Closed;
  if (deadline_ms <= now_ms || deadline_ms - now_ms > kMaximumDurationMs) {
    return Admission::InvalidDeadline;
  }
  if (!AcceptTime(now_ms)) return Admission::InvalidClock;
  if (pending_ == kCapacity) return Admission::Busy;
  if (greatest_id_ == std::numeric_limits<std::uint64_t>::max()) return Admission::Exhausted;
  for (auto &entry : entries_) {
    if (entry.id == 0) {
      entry = {++greatest_id_, deadline_ms, std::nullopt};
      ++pending_;
      ticket = {generation_, entry.id};
      return Admission::Reserved;
    }
  }
  return Admission::Busy;
}

BridgeConsumerHandoff::Reply BridgeConsumerHandoff::Resolve(const Ticket &ticket, Outcome outcome,
                                                            std::uint64_t received_ms) {
  auto *entry = Find(ticket);
  if (entry == nullptr) return Reply::UnknownTicket;
  if (closed_) return Reply::Closed;
  if (outcome != Outcome::Completed && outcome != Outcome::Denied && outcome != Outcome::Failed &&
      outcome != Outcome::Unknown)
    return Reply::InvalidOutcome;
  if (!AcceptTime(received_ms)) return Reply::InvalidClock;
  if (entry->outcome) return Reply::Duplicate;
  if (received_ms >= entry->deadline_ms) {
    entry->outcome = Outcome::TimedOut;
    return Reply::Late;
  }
  entry->outcome = outcome;
  return Reply::Stored;
}

BridgeConsumerHandoff::Consume BridgeConsumerHandoff::Take(const Ticket &ticket,
                                                           std::uint64_t now_ms, Outcome &outcome) {
  auto *entry = Find(ticket);
  if (entry == nullptr) return Consume::UnknownTicket;
  if (!AcceptTime(now_ms)) return Consume::InvalidClock;
  // A result staged before expiry is still unusable once the original native
  // deadline expires. Neither delayed delivery nor shutdown can revive it.
  if (!closed_ && now_ms >= entry->deadline_ms) entry->outcome = Outcome::TimedOut;
  if (!entry->outcome) return Consume::Pending;
  outcome = *entry->outcome;
  *entry = {};
  --pending_;
  return Consume::Completed;
}

std::optional<std::uint64_t> BridgeConsumerHandoff::Deadline(const Ticket &ticket) const {
  const auto *entry = Find(ticket);
  return entry != nullptr ? std::make_optional(entry->deadline_ms) : std::nullopt;
}

BridgeConsumerHandoff::ClockSample BridgeConsumerHandoff::Sample(const Generation &generation,
                                                                 std::uint64_t now_ms) {
  if (generation != generation_) return ClockSample::InvalidGeneration;
  if (closed_) return ClockSample::Closed;
  return AcceptTime(now_ms) ? ClockSample::Sampled : ClockSample::InvalidClock;
}

void BridgeConsumerHandoff::Close() {
  closed_ = true;
  for (auto &entry : entries_) {
    if (entry.id != 0) entry.outcome = Outcome::Closed;
  }
}

bool BridgeConsumerHandoff::closed() const { return closed_; }
std::size_t BridgeConsumerHandoff::pending() const { return pending_; }

BridgeConsumerHandoff::Entry *BridgeConsumerHandoff::Find(const Ticket &ticket) {
  if (ticket.generation != generation_ || ticket.id == 0) return nullptr;
  for (auto &entry : entries_) {
    if (entry.id == ticket.id) return &entry;
  }
  return nullptr;
}

const BridgeConsumerHandoff::Entry *BridgeConsumerHandoff::Find(const Ticket &ticket) const {
  if (ticket.generation != generation_ || ticket.id == 0) return nullptr;
  for (const auto &entry : entries_) {
    if (entry.id == ticket.id) return &entry;
  }
  return nullptr;
}

bool BridgeConsumerHandoff::AcceptTime(std::uint64_t now_ms) {
  if (last_time_ms_ && now_ms < *last_time_ms_) return false;
  last_time_ms_ = now_ms;
  return true;
}

} // namespace wotex::matter
