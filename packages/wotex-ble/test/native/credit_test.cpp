// SPDX-License-Identifier: Apache-2.0
#include "credit.hpp"
#include <cstdlib>
#include <iostream>
using namespace wotex::ble;
static const std::string generation = "0123456789abcdef0123456789abcdef";
static void check(bool result) { if (!result) std::abort(); }
template <typename F> static void rejects(F action) {
  try { action(); } catch (const InvalidFrame &) { return; }
  std::abort();
}
static void invariants() {
  rejects([] { Credits invalid(""); });
  rejects([] { Credits invalid("0123456789ABCDEF0123456789ABCDEF"); });
  Credits credits(generation);
  check(credits.open(1, 64)); check(credits.open(2, 64));
  check(credits.reserve(1, 128) == 1); check(credits.reserve(2, 128) == 2);
  rejects([&] { credits.retire(1, 2); });
  check(credits.active_streams() == 2);
  credits.retire(1, 1);
  check(credits.available_frames() == 62 && credits.available_bytes() == 1048320);
  check(credits.active_streams() == 1 && credits.stream_records() == 2);
  rejects([&] { credits.retire(1, 1); });
  rejects([&] { credits.reserve(1, 128); });
  rejects([&] { credits.acknowledge(generation, 1, 129); });
  rejects([&] { credits.acknowledge(std::string(32, 'a'), 1, 128); });
  rejects([&] { credits.acknowledge(generation, 3, 384); });
  check(credits.available_frames() == 62);
  credits.acknowledge(generation, 1, 128);
  check(credits.available_frames() == 63 && credits.stream_records() == 1);
  rejects([&] { credits.acknowledge(generation, 1, 128); });
  credits.acknowledge(generation, 2, 256);
  check(credits.available_frames() == 64 && credits.available_bytes() == 1048576);
  credits.retire(2, 2);
  check(credits.stream_records() == 0);
  for (std::uint64_t id = 3; id < 100003; ++id) {
    check(credits.open(id, 1));
    auto seq = credits.reserve(id, 128); check(seq.has_value());
    check(!credits.reserve(id, 128).has_value());
    credits.retire(id, *seq);
    credits.acknowledge(generation, *seq, *seq * 128);
    check(credits.stream_records() == 0);
  }
  rejects([&] { credits.open(3, 1); });
  rejects([&] { credits.open(100004, 0); });
  rejects([&] { credits.open(100004, 10001); });
  Credits full(generation);
  for (std::uint64_t id = 1; id <= 64; ++id) check(full.open(id, 64));
  check(!full.open(65, 64));
  for (std::uint64_t id = 1; id <= 64; ++id) check(full.reserve(id, 128) == id);
  check(!full.reserve(1, 128));
  for (std::uint64_t id = 1; id <= 64; ++id) full.retire(id, id);
  check(full.active_streams() == 0 && full.stream_records() == 64);
  for (std::uint64_t id = 65; id <= 128; ++id) check(full.open(id, 64));
  check(full.stream_records() == 128);
  full.acknowledge(generation, 64, 8192);
  check(full.stream_records() == 64);
  for (std::uint64_t id = 65; id <= 128; ++id) full.retire(id, 0);
  check(full.stream_records() == 0);
  Credits bytes(generation); check(bytes.open(1, 64));
  for (int i = 0; i < 8; ++i) check(bytes.reserve(1, 131072).has_value());
  check(bytes.available_bytes() == 0 && bytes.available_frames() == 56);
  check(!bytes.reserve(1, 1));
  rejects([&] { bytes.reserve(1, 0); });
  rejects([&] { bytes.reserve(1, 131073); });
  Json ack = {{"version", 1}, {"event", "report_ack"}, {"session_generation", generation},
              {"report_sequence", 8}, {"acknowledged_bytes", 1048576}};
  auto forged = ack; forged["extra"] = true; rejects([&] { bytes.acknowledge(forged); });
  forged = ack; forged["report_sequence"] = true; rejects([&] { bytes.acknowledge(forged); });
  bytes.acknowledge(ack); check(bytes.available_bytes() == 1048576);
}

static Json trace(const Json &input) {
  const auto token = input.at("session_generation").get<std::string>();
  Credits credits(token);
  std::map<std::string, std::uint64_t> streams;
  struct Observation { std::uint64_t stream, sequence, bytes; bool consumed; };
  std::vector<Observation> observed;
  std::uint64_t acknowledged = 0, acknowledged_bytes = 0;
  std::size_t transmitted = 0;
  Json terminal = nullptr;
  auto acknowledge_prefix = [&] {
    auto sequence = acknowledged;
    auto bytes = acknowledged_bytes;
    for (const auto &report : observed) {
      if (report.sequence <= sequence) continue;
      if (!report.consumed) break;
      sequence = report.sequence; bytes += report.bytes;
    }
    if (sequence > acknowledged) {
      credits.acknowledge(token, sequence, bytes);
      acknowledged = sequence; acknowledged_bytes = bytes;
    }
  };
  try {
    for (const auto &event : input.at("events")) {
      const auto kind = event.at("event").get<std::string>();
      if (kind == "transmit") {
        if (!fields(event, {"event", "stream", "bytes"})) throw InvalidFrame();
        const auto label = event.at("stream").get<std::string>();
        if (!streams.count(label)) {
          const auto id = streams.size() + 1;
          check(credits.open(id, input.at("queue_limit").get<std::size_t>()));
          streams.emplace(label, id);
        }
        const auto bytes = event.at("bytes").get<std::size_t>();
        // These accepted trace cells have no deferred report queue. The actual
        // output queue and process-overproducer cases have separate acceptance.
        const auto result = credits.reserve(streams.at(label), bytes);
        if (!result) throw InvalidFrame();
        observed.push_back({streams.at(label), *result, bytes, false});
        ++transmitted;
      } else if (kind == "ack") {
        const auto sequence = event.at("report_sequence").get<std::uint64_t>();
        const auto bytes = event.at("acknowledged_bytes").get<std::uint64_t>();
        credits.acknowledge(event.at("session_generation").get<std::string>(), sequence, bytes);
        acknowledged = sequence; acknowledged_bytes = bytes;
        for (auto &report : observed) if (report.sequence <= sequence) report.consumed = true;
      } else if (kind == "retire") {
        const auto id = streams.at(event.at("stream").get<std::string>());
        credits.retire(id, event.at("last_report_sequence").get<std::uint64_t>());
        for (auto &report : observed) if (report.stream == id) report.consumed = true;
        acknowledge_prefix();
      } else if (kind == "consume") {
        const auto id = streams.at(event.at("stream").get<std::string>());
        const auto sequence = event.at("report_sequence").get<std::uint64_t>();
        bool found = false;
        for (auto &report : observed) if (report.stream == id && report.sequence == sequence) {
          report.consumed = true; found = true;
        }
        if (!found) throw InvalidFrame();
        acknowledge_prefix();
      } else throw InvalidFrame();
    }
  } catch (const InvalidFrame &) { terminal = "invalid_frame"; }
  return {{"transmitted", transmitted}, {"queued", 0}, {"terminal", terminal},
          {"frame_credit", credits.available_frames()}, {"byte_credit", credits.available_bytes()}};
}
int main(int argc, char **argv) {
  if (argc == 3 && std::string(argv[1]) == "--trace") {
    std::cout << trace(parse_line(std::string(argv[2]) + "\n")).dump() << '\n';
    return 0;
  }
  if (argc != 1) return 2;
  invariants();
  std::cout << "native credit invariants passed\n";
}
