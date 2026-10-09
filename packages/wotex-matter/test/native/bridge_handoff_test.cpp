#include "wotex_matter/bridge_handoff.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>

namespace wotex::matter {

struct BridgeConsumerHandoffTestAccess {
  static void Counter(BridgeConsumerHandoff &owner, std::uint64_t value) {
    owner.greatest_id_ = value;
  }
};

} // namespace wotex::matter

namespace {

using Handoff = wotex::matter::BridgeConsumerHandoff;

void Require(bool condition, const char *message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}

void BoundedOwnership() {
  Handoff owner({1});
  std::array<Handoff::Ticket, Handoff::kCapacity> tickets{};
  Handoff::Ticket sentinel{{9}, 99};
  Require(owner.Reserve(100, 100, sentinel) == Handoff::Admission::InvalidDeadline &&
              sentinel.id == 99 && sentinel.generation[0] == 9,
          "elapsed deadline changed output");
  Require(owner.Reserve(100, 601, sentinel) == Handoff::Admission::InvalidDeadline,
          "handoff exceeded 500 ms");
  for (auto &ticket : tickets) {
    Require(owner.Reserve(100, 600, ticket) == Handoff::Admission::Reserved,
            "sixteen reservations unavailable");
    Require(owner.Deadline(ticket) == 600, "absolute deadline changed");
  }
  Require(owner.Reserve(100, 600, sentinel) == Handoff::Admission::Busy && sentinel.id == 99,
          "seventeenth reservation changed output");
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(owner.Take(tickets[0], 599, outcome) == Handoff::Consume::Pending &&
              outcome == Handoff::Outcome::Unknown && owner.pending() == 16,
          "admission completed or released a native context");
  Require(owner.Take(tickets[0], 600, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::TimedOut && !owner.Deadline(tickets[0]),
          "exact deadline did not expire custody");
  Require(
      owner.Resolve(tickets[0], Handoff::Outcome::Completed, 600) == Handoff::Reply::UnknownTicket,
      "late reply resurrected a consumed context");
  Handoff::Ticket replacement;
  Require(
      owner.Reserve(600, 1100, replacement) == Handoff::Admission::Reserved && replacement.id == 17,
      "released slot reused request identity");
  Require(owner.Resolve(tickets[1], Handoff::Outcome::Completed, 600) == Handoff::Reply::Late &&
              owner.pending() == 16,
          "expiry released unconsumed SDK context credit");
  Require(owner.Reserve(600, 1100, sentinel) == Handoff::Admission::Busy,
          "expired context allowed a seventeenth owner");
  Require(
      owner.Resolve(replacement, Handoff::Outcome::Denied, 700) == Handoff::Reply::Stored &&
          owner.Resolve(replacement, Handoff::Outcome::Completed, 701) == Handoff::Reply::Duplicate,
      "consumer denial was overwritten");
  owner.Close();
  owner.Close();
  Require(owner.closed() && owner.Reserve(701, 1201, sentinel) == Handoff::Admission::Closed &&
              owner.pending() == 16,
          "closure released contexts or allowed admission");
  Require(owner.Resolve(replacement, Handoff::Outcome::Completed, 701) == Handoff::Reply::Closed,
          "closed owner accepted a result");
  Require(owner.Take(replacement, 701, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Closed,
          "shutdown delivered staged result");
  for (std::size_t index = 1; index < tickets.size(); ++index) {
    Require(owner.Take(tickets[index], 701, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::Closed,
            "closure omitted exact native context");
  }
  Require(owner.pending() == 0, "closure retained consumed context credit");
}

void ExactResults() {
  for (auto result : {Handoff::Outcome::Completed, Handoff::Outcome::Denied,
                      Handoff::Outcome::Failed, Handoff::Outcome::Unknown}) {
    Handoff owner({2});
    Handoff::Ticket ticket;
    Handoff::Outcome outcome = Handoff::Outcome::Closed;
    Require(owner.Reserve(100, 600, ticket) == Handoff::Admission::Reserved &&
                owner.Resolve(ticket, result, 599) == Handoff::Reply::Stored,
            "consumer result refused before deadline");
    Require(owner.Take(ticket, 599, outcome) == Handoff::Consume::Completed && outcome == result,
            "consumer logical result changed");
    Require(owner.Take(ticket, 599, outcome) == Handoff::Consume::UnknownTicket,
            "context consumed twice");
    Require(owner.Reserve(600, 1100, ticket) == Handoff::Admission::Reserved &&
                owner.Resolve(ticket, result, 1099) == Handoff::Reply::Stored,
            "next result admission failed");
    Require(owner.Take(ticket, 1100, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::TimedOut,
            "delayed result escaped absolute expiry");
  }
}

void IdentityAndClock() {
  Handoff owner({3});
  Handoff::Ticket ticket;
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(owner.Reserve(100, 600, ticket) == Handoff::Admission::Reserved, "identity fixture");
  auto foreign = ticket;
  foreign.generation[15] = 1;
  Require(!owner.Deadline(foreign) &&
              owner.Resolve(foreign, Handoff::Outcome::Completed, 99999) ==
                  Handoff::Reply::UnknownTicket &&
              owner.Take(foreign, 99999, outcome) == Handoff::Consume::UnknownTicket &&
              outcome == Handoff::Outcome::Unknown,
          "foreign generation changed custody");
  foreign = ticket;
  foreign.id = 0;
  Require(owner.Resolve(foreign, Handoff::Outcome::Completed, 100) == Handoff::Reply::UnknownTicket,
          "zero ticket admitted");
  for (auto forged : {Handoff::Outcome::TimedOut, Handoff::Outcome::Closed}) {
    Require(owner.Resolve(ticket, forged, 100) == Handoff::Reply::InvalidOutcome,
            "consumer forged owner timeout or closure");
  }
  Require(owner.Resolve(ticket, Handoff::Outcome::Completed, 99) == Handoff::Reply::InvalidClock &&
              owner.Take(ticket, 99, outcome) == Handoff::Consume::InvalidClock &&
              outcome == Handoff::Outcome::Unknown,
          "clock before admission changed result");
  Handoff::Ticket unchanged{{4}, 4};
  Require(
      owner.Reserve(99, 599, unchanged) == Handoff::Admission::InvalidClock && unchanged.id == 4,
      "regressed clock admitted a new request");
  Require(owner.Resolve(ticket, Handoff::Outcome::Completed, 200) == Handoff::Reply::Stored &&
              owner.Take(ticket, 199, outcome) == Handoff::Consume::InvalidClock &&
              owner.pending() == 1,
          "regression delivered a staged result");
  Require(owner.Take(ticket, 200, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Completed,
          "valid delivery after clock refusal");
}

void Exhaustion() {
  Handoff owner({4});
  Handoff::Ticket ticket;
  const auto maximum = std::numeric_limits<std::uint64_t>::max();
  wotex::matter::BridgeConsumerHandoffTestAccess::Counter(owner, maximum - 1);
  Require(owner.Reserve(maximum - 500, maximum, ticket) == Handoff::Admission::Reserved &&
              ticket.id == maximum,
          "last representable request refused");
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(owner.Take(ticket, maximum, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::TimedOut,
          "maximum deadline wrapped");
  const auto preserved = ticket;
  Require(owner.Reserve(maximum, 0, ticket) == Handoff::Admission::InvalidDeadline &&
              ticket.id == preserved.id,
          "wrapped deadline admitted");
  Handoff counter({5});
  wotex::matter::BridgeConsumerHandoffTestAccess::Counter(counter, maximum);
  Require(counter.Reserve(100, 600, ticket) == Handoff::Admission::Exhausted &&
              ticket.id == preserved.id && counter.pending() == 0,
          "request identity exhaustion wrapped or changed output");
}

} // namespace

int main() {
  BoundedOwnership();
  ExactResults();
  IdentityAndClock();
  Exhaustion();
  std::cout << "bridge consumer handoff custody passed\n";
}
