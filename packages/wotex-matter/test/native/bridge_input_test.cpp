#include "wotex_matter/bridge_input.hpp"

#include <nlohmann/json.hpp>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <fcntl.h>
#include <iostream>
#include <limits>
#include <new>
#include <thread>
#include <unistd.h>

using namespace wotex::matter;

namespace {
std::atomic<int> allocation_failure{-1};
}

// Fail each real decoder allocation in turn, without a production fault hook.
void *operator new(std::size_t size) {
  if (allocation_failure.load() >= 0 && allocation_failure.fetch_sub(1) == 0) {
    allocation_failure = -1;
    throw std::bad_alloc();
  }
  if (auto *memory = std::malloc(size == 0 ? 1 : size)) return memory;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete[](void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, std::size_t) noexcept { std::free(memory); }
void operator delete[](void *memory, std::size_t) noexcept { std::free(memory); }

namespace {
using Handoff = BridgeConsumerHandoff;
using State = BridgeResultInput::State;
using Json = nlohmann::json;

std::string Generation(const Handoff::Generation &generation) {
  const char digits[] = "0123456789abcdef";
  std::string output;
  for (auto byte : generation) {
    output += digits[byte >> 4];
    output += digits[byte & 15];
  }
  return output;
}
Json Object(const Handoff::Ticket &ticket) {
  return {{"v", 1},
          {"backend", "matter-bridge"},
          {"type", "result"},
          {"generation", Generation(ticket.generation)},
          {"id", std::to_string(ticket.id)},
          {"outcome", "completed"}};
}
std::string Frame(const Handoff::Ticket &ticket) { return Object(ticket).dump() + '\n'; }
Json ProbeObject(const Handoff::Ticket &probe) {
  auto value = Object(probe);
  value.erase("outcome");
  value["type"] = "clock-probe";
  return value;
}
std::string ProbeFrame(const Handoff::Ticket &probe) { return ProbeObject(probe).dump() + '\n'; }

class Clock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
};
class ManualClock final : public BridgeHandoffClock {
 public:
  std::uint64_t now{100};
  std::uint64_t NowMs() noexcept override { return now; }
};
class Sink final : public BridgeResultSink {
 public:
  std::atomic<unsigned> ready{0}, closed{0};
  std::uint64_t probe_id{0}, probe_ms{0};
  bool refuse{false};
  bool Ready(const Handoff::Ticket &) noexcept override {
    ++ready;
    return !refuse;
  }
  bool ClockSample(const Handoff::Ticket &probe, std::uint64_t native_ms) noexcept override {
    probe_id = probe.id;
    probe_ms = native_ms;
    return !refuse;
  }
  void Closed() noexcept override { ++closed; }
};
Handoff::Ticket Reserve(BridgeHandoffOwner &owner) {
  Handoff::Ticket ticket;
  owner.With([&](auto &custody, auto now) {
    assert(custody.Reserve(now, now + Handoff::kMaximumDurationMs, ticket) ==
           Handoff::Admission::Reserved);
  });
  return ticket;
}
void Drain(BridgeHandoffOwner &owner, const Handoff::Ticket &ticket, Handoff::Outcome expected) {
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  assert(owner.Wait(ticket, outcome) == Handoff::Consume::Completed && outcome == expected);
}

void Decode() {
  const Handoff::Generation generation{1, 2, 3};
  auto frame = Object({generation, 1});
  BridgeResultFrame result;
  for (const auto &pair : {std::pair{"completed", Handoff::Outcome::Completed},
                           {"denied", Handoff::Outcome::Denied},
                           {"failed", Handoff::Outcome::Failed},
                           {"unknown", Handoff::Outcome::Unknown}}) {
    frame["outcome"] = pair.first;
    assert(DecodeBridgeResultFrame(frame.dump(), generation, result) ==
           BridgeResultDecode::Decoded);
    assert(result.ticket.generation == generation && result.ticket.id == 1 &&
           result.outcome == pair.second);
  }
  frame["outcome"] = "completed";
  frame["id"] = std::to_string(std::numeric_limits<std::uint64_t>::max());
  assert(DecodeBridgeResultFrame(frame.dump(), generation, result) == BridgeResultDecode::Decoded);
  assert(result.ticket.id == std::numeric_limits<std::uint64_t>::max());
  frame["id"] = "1";
  const auto valid = frame.dump();
  const auto refuse = [&](const std::string &source,
                          BridgeResultDecode expected = BridgeResultDecode::Malformed) {
    BridgeResultFrame sentinel{{{9}, 999}, Handoff::Outcome::Failed};
    assert(DecodeBridgeResultFrame(source, generation, sentinel) == expected);
    assert(sentinel.ticket.id == 999 && sentinel.ticket.generation[0] == 9 &&
           sentinel.outcome == Handoff::Outcome::Failed);
  };
  for (const auto &key : {"v", "backend", "type", "generation", "id", "outcome"}) {
    auto missing = frame;
    missing.erase(key);
    refuse(missing.dump());
    refuse(valid.substr(0, valid.size() - 1) + ",\"" + key + "\":" + frame[key].dump() + "}");
    for (const auto &wrong : {Json{}, Json::array(), Json::object(), Json(true)}) {
      auto changed = frame;
      changed[key] = wrong;
      refuse(changed.dump());
    }
  }
  for (const auto &identity :
       {"", "0", "01", "+1", "-1", " 1", "1 ", "1.0", "18446744073709551616"}) {
    auto changed = frame;
    changed["id"] = identity;
    refuse(changed.dump());
  }
  for (const auto &outcome : {"timeout", "closed", "success", "Completed"}) {
    auto changed = frame;
    changed["outcome"] = outcome;
    refuse(changed.dump());
  }
  auto changed = frame;
  changed["backend"] = "matter-native";
  refuse(changed.dump());
  changed = frame;
  changed["type"] = "request";
  refuse(changed.dump());
  changed = frame;
  changed["generation"] = Generation({9});
  refuse(changed.dump());
  changed["generation"] = std::string(32, 'A');
  refuse(changed.dump());
  for (const auto &version : {Json(1.0), Json(-1), Json(2), Json("1")}) {
    changed = frame;
    changed["v"] = version;
    refuse(changed.dump());
  }
  changed = frame;
  changed["id"] = 1;
  refuse(changed.dump());
  changed = frame;
  changed["extra"] = 1;
  refuse(changed.dump());
  for (const auto &suffix :
       {std::string("{}"), std::string(1, '\0'), std::string("\n"), std::string("\r")})
    refuse(valid + suffix);
  for (const auto &invalid : {"", "[]", "{", "true", "null", "{}"}) refuse(invalid);
  auto boundary = valid + std::string(511 - valid.size(), ' ');
  assert(DecodeBridgeResultFrame(boundary, generation, result) == BridgeResultDecode::Decoded);
  refuse(boundary + " ", BridgeResultDecode::Oversized);
}

void Refuse(const std::string &bytes, State expected, bool sink_refuses = false) {
  Handoff custody({1});
  Clock clock;
  BridgeHandoffOwner owner(custody, clock);
  const auto ticket = Reserve(owner);
  Sink sink;
  sink.refuse = sink_refuses;
  BridgeResultInput input(owner, {1}, sink);
  auto result = input.Feed(bytes.empty() ? Frame(ticket) : bytes);
  if (expected == State::Partial) result = input.End();
  assert(result == expected && sink.closed == 1);
  assert(input.End() == expected && input.Feed(Frame(ticket)) == expected && sink.closed == 1);
  Drain(owner, ticket, Handoff::Outcome::Closed);
}

void BatchAndDeadline() {
  Handoff custody({1});
  ManualClock clock;
  BridgeHandoffOwner owner(custody, clock);
  std::array<Handoff::Ticket, Handoff::kCapacity> tickets;
  for (auto &ticket : tickets) ticket = Reserve(owner);
  owner.With([](auto &core, auto now) {
    Handoff::Ticket extra;
    assert(core.Reserve(now, now + 500, extra) == Handoff::Admission::Busy);
  });
  Sink sink;
  BridgeResultInput input(owner, {1}, sink);
  auto frame = Frame(tickets[0]);
  frame.insert(frame.size() - 1, 512 - frame.size(), ' ');
  assert(frame.size() == 512);
  for (char byte : frame) assert(input.Feed(std::string_view(&byte, 1)) == State::Open);
  assert(input.Feed(Frame(tickets[0]) + Frame({{1}, 999})) == State::Open && sink.ready == 1);
  for (std::size_t i = 1; i < tickets.size(); i += 2) {
    auto pair = Frame(tickets[i]);
    if (i + 1 < tickets.size()) pair += Frame(tickets[i + 1]);
    assert(input.Feed(pair) == State::Open);
  }
  assert(sink.ready == tickets.size());
  clock.now = 600; // Staged completion cannot extend the original deadline.
  for (const auto &ticket : tickets) Drain(owner, ticket, Handoff::Outcome::TimedOut);
  assert(input.Feed(Frame(tickets[0])) == State::Open && sink.ready == tickets.size());
  assert(input.End() == State::Ended && sink.closed == 1);
}

void ClosureAndClock() {
  Handoff custody({1});
  ManualClock clock;
  BridgeHandoffOwner owner(custody, clock);
  const auto ticket = Reserve(owner);
  Sink sink;
  BridgeResultInput input(owner, {1}, sink);
  assert(input.Feed(Frame(ticket)) == State::Open && sink.ready == 1);
  assert(input.End() == State::Ended);
  Drain(owner, ticket, Handoff::Outcome::Closed); // EOF discards unconsumed staged results.

  Handoff regressing({1});
  BridgeHandoffOwner other(regressing, clock);
  const auto stale_clock_ticket = Reserve(other);
  Sink other_sink;
  BridgeResultInput other_input(other, {1}, other_sink);
  clock.now = 99;
  assert(other_input.Feed(Frame(stale_clock_ticket)) == State::Clock && other_sink.closed == 1);
  clock.now = 101;
  Drain(other, stale_clock_ticket, Handoff::Outcome::Closed);
}

void ProbeCodec() {
  const Handoff::Generation generation{1, 2, 3};
  const auto object = ProbeObject({generation, 1});
  const auto valid = object.dump();
  BridgeInputFrame frame;
  assert(DecodeBridgeInputFrame(valid, generation, frame) == BridgeResultDecode::Decoded);
  assert(frame.kind == BridgeInputFrame::Kind::ClockProbe && frame.result.ticket.id == 1 &&
         frame.result.ticket.generation == generation);
  BridgeResultFrame result{{{9}, 999}, Handoff::Outcome::Failed};
  assert(DecodeBridgeResultFrame(valid, generation, result) == BridgeResultDecode::Malformed &&
         result.ticket.id == 999);

  const auto refuse = [&](const std::string &bytes,
                          BridgeResultDecode expected = BridgeResultDecode::Malformed) {
    BridgeInputFrame sentinel{BridgeInputFrame::Kind::Result,
                              {{{9}, 999}, Handoff::Outcome::Failed}};
    assert(DecodeBridgeInputFrame(bytes, generation, sentinel) == expected);
    assert(sentinel.kind == BridgeInputFrame::Kind::Result && sentinel.result.ticket.id == 999 &&
           sentinel.result.ticket.generation[0] == 9 &&
           sentinel.result.outcome == Handoff::Outcome::Failed);
  };
  for (const auto &key : {"v", "backend", "type", "generation", "id"}) {
    auto changed = object;
    changed.erase(key);
    refuse(changed.dump());
    refuse(valid.substr(0, valid.size() - 1) + ",\"" + key + "\":" + object[key].dump() + "}");
    for (const auto &wrong : {Json{}, Json::array(), Json::object(), Json(true)}) {
      changed = object;
      changed[key] = wrong;
      refuse(changed.dump());
    }
  }
  auto changed = object;
  changed["outcome"] = "completed";
  refuse(changed.dump());
  for (const auto &id : {"0", "01", "+1", "-1", "1.0", "18446744073709551616"}) {
    changed = object;
    changed["id"] = id;
    refuse(changed.dump());
  }
  changed = object;
  changed["generation"] = Generation({9});
  refuse(changed.dump());
  changed = object;
  changed["type"] = "clock-sample";
  refuse(changed.dump());
  changed = object;
  changed["backend"] = "matter-native";
  refuse(changed.dump());
  changed = object;
  changed["v"] = 1.0;
  refuse(changed.dump());
  auto boundary = valid + std::string(511 - valid.size(), ' ');
  assert(DecodeBridgeInputFrame(boundary, generation, frame) == BridgeResultDecode::Decoded);
  refuse(boundary + " ", BridgeResultDecode::Oversized);
  for (const auto &suffix :
       {std::string("{}"), std::string(1, '\0'), std::string("\n"), std::string("\r")})
    refuse(valid + suffix);

  const auto maximum = std::numeric_limits<std::uint64_t>::max();
  changed = object;
  changed["id"] = std::to_string(maximum);
  assert(DecodeBridgeInputFrame(changed.dump(), generation, frame) == BridgeResultDecode::Decoded &&
         frame.result.ticket.id == maximum);
  for (const auto id : {std::uint64_t{1}, maximum}) {
    for (const auto native : {std::uint64_t{0}, maximum}) {
      std::string output = "sentinel";
      assert(EncodeBridgeClockSample(generation, id, native, output) == BridgeClockEncode::Encoded);
      assert(output.size() <= 512 && output.back() == '\n');
      const auto decoded = Json::parse(output);
      assert(decoded.size() == 6 && decoded["v"] == 1 && decoded["backend"] == "matter-bridge" &&
             decoded["type"] == "clock-sample" && decoded["generation"] == Generation(generation) &&
             decoded["id"] == std::to_string(id) && decoded["native_ms"] == std::to_string(native));
    }
  }
  std::string output = "sentinel";
  assert(EncodeBridgeClockSample(generation, 0, 1, output) == BridgeClockEncode::Malformed &&
         output == "sentinel");

  unsigned failed = 0;
  bool completed = false;
  for (int index = 0; index < 128; ++index) {
    output = "sentinel";
    allocation_failure = index;
    const auto encoded = EncodeBridgeClockSample(generation, maximum, maximum, output);
    allocation_failure = -1;
    if (encoded == BridgeClockEncode::Encoded) {
      completed = true;
      break;
    }
    assert(encoded == BridgeClockEncode::NoMemory && output == "sentinel");
    ++failed;
  }
  assert(completed && failed > 0);
}

void ProbeCustody() {
  Handoff custody({1});
  ManualClock clock;
  BridgeHandoffOwner owner(custody, clock);
  Sink sink;
  BridgeResultInput input(owner, {1}, sink);
  // Sampling is possible before the first request and cannot reserve credit.
  assert(input.Feed(ProbeFrame({{1}, 2})) == State::Open && sink.probe_id == 2 &&
         sink.probe_ms == 100 && custody.pending() == 0);
  const auto ticket = Reserve(owner);
  clock.now = 150;
  assert(input.Feed(ProbeFrame({{1}, 4}) + Frame(ticket)) == State::Open && sink.probe_id == 4 &&
         sink.probe_ms == 150 && sink.ready == 1 && custody.pending() == 1);
  clock.now = 600;
  Drain(owner, ticket, Handoff::Outcome::TimedOut);
  assert(input.Feed(ProbeFrame({{1}, 3})) == State::Malformed && sink.closed == 1 &&
         sink.probe_id == 4);

  for (const auto expected : {State::Clock, State::Malformed, State::Sink, State::Ended}) {
    Handoff core({1});
    clock.now = 100;
    BridgeHandoffOwner owned(core, clock);
    const auto pending = Reserve(owned);
    Sink notification;
    BridgeResultInput reader(
        owned, expected == State::Malformed ? Handoff::Generation{2} : Handoff::Generation{1},
        notification);
    if (expected == State::Clock) clock.now = 99;
    if (expected == State::Sink) notification.refuse = true;
    if (expected == State::Ended) owned.Close();
    const auto generation = expected == State::Malformed ? Handoff::Generation{2}
                                                         : Handoff::Generation{1};
    assert(reader.Feed(ProbeFrame({generation, 1})) == expected && notification.closed == 1);
    clock.now = 101;
    Drain(owned, pending, Handoff::Outcome::Closed);
  }
}

void AllocationFailure() {
  const Handoff::Generation generation{1};
  const auto valid = Object({generation, 1}).dump();
  bool completed = false;
  unsigned failures = 0;
  for (int index = 0; index < 128; ++index) {
    BridgeResultFrame output{{{9}, 999}, Handoff::Outcome::Failed};
    allocation_failure = index;
    const auto decoded = DecodeBridgeResultFrame(valid, generation, output);
    allocation_failure = -1;
    if (decoded == BridgeResultDecode::Decoded) {
      completed = true;
      break;
    }
    ++failures;
    assert(decoded == BridgeResultDecode::NoMemory && output.ticket.id == 999 &&
           output.ticket.generation[0] == 9 && output.outcome == Handoff::Outcome::Failed);
  }
  assert(completed && failures > 0);
  Handoff custody(generation);
  Clock clock;
  BridgeHandoffOwner owner(custody, clock);
  const auto ticket = Reserve(owner);
  Sink sink;
  BridgeResultInput input(owner, generation, sink);
  const auto frame = Frame(ticket);
  allocation_failure = 0;
  const auto state = input.Feed(frame);
  allocation_failure = -1;
  assert(state == State::NoMemory && sink.closed == 1 && sink.ready == 0);
  Drain(owner, ticket, Handoff::Outcome::Closed);
}

void Pipes() {
  Handoff custody({1});
  Clock clock;
  BridgeHandoffOwner owner(custody, clock);
  const auto first = Reserve(owner), second = Reserve(owner);
  Sink sink;
  BridgeResultInput input(owner, {1}, sink);
  int descriptors[2];
  assert(pipe(descriptors) == 0);
  const int flags = fcntl(descriptors[0], F_GETFL);
  std::atomic<bool> stop{false}, finished{false};
  State terminal = State::Open;
  std::thread reader([&] {
    terminal = input.Run(descriptors[0], stop);
    finished = true;
  });
  const auto frame = Frame(first);
  std::mutex stack;
  std::lock_guard<std::mutex> stack_owner(stack);
  for (char byte : frame) assert(write(descriptors[1], &byte, 1) == 1);
  Drain(owner, first, Handoff::Outcome::Completed);
  assert(!finished);
  assert(write(descriptors[1], frame.data(), frame.size()) == static_cast<ssize_t>(frame.size()));
  assert(close(descriptors[1]) == 0);
  Drain(owner, second, Handoff::Outcome::Closed);
  reader.join(); // Notifications occur after custody unlocks; inspect them after joining.
  assert(terminal == State::Ended && sink.closed == 1 && sink.ready == 1);
  assert(fcntl(descriptors[0], F_GETFL) == flags && close(descriptors[0]) == 0);

  for (const auto expected : {State::Cancelled, State::Read, State::Partial, State::Malformed}) {
    Handoff core({1});
    BridgeHandoffOwner pipe_owner(core, clock);
    const auto ticket = Reserve(pipe_owner);
    Sink notification;
    BridgeResultInput stream(pipe_owner, {1}, notification);
    assert(pipe(descriptors) == 0);
    const int original = fcntl(descriptors[0], F_GETFL);
    stop = false;
    std::thread other_reader(
        [&] { terminal = stream.Run(expected == State::Read ? -1 : descriptors[0], stop); });
    if (expected == State::Cancelled) stop = true; // Writer stays open through the join.
    else if (expected != State::Read) {
      const auto bytes = expected == State::Partial ? "{" : "\n";
      assert(write(descriptors[1], bytes, 1) == 1);
      assert(close(descriptors[1]) == 0);
    }
    Drain(pipe_owner, ticket, Handoff::Outcome::Closed);
    other_reader.join();
    assert(terminal == expected && notification.closed == 1 &&
           fcntl(descriptors[0], F_GETFL) == original);
    if (expected == State::Cancelled || expected == State::Read) assert(close(descriptors[1]) == 0);
    assert(close(descriptors[0]) == 0);
  }
}
} // namespace

int main() {
  Decode();
  ProbeCodec();
  ProbeCustody();
  BatchAndDeadline();
  ClosureAndClock();
  AllocationFailure();
  Pipes();
  Refuse("\n", State::Malformed);
  Refuse(std::string(512, ' '), State::Oversized);
  Refuse("{", State::Partial);
  Refuse("{}\n", State::Malformed);
  Refuse("", State::Sink, true);
  std::cout << "bounded bridge results, deadlines, pipe loss and cancellation passed\n";
}
