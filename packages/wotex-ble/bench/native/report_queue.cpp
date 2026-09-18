// SPDX-License-Identifier: Apache-2.0
// The unsent-report queue of the BLE native host
// (priv/bluez/native/report_queue.hpp) holding 20-byte attribute values
// charged 320 bytes each: admission of 64 reports and a drain that dispatches
// them all, on one stream and on 8 streams; a drain in which 4 of 8 streams
// lack credit, whose queued reports are then discarded; and admission of 64
// reports on one stream followed by its discard, the path of a silenced
// stream. Each operation is one report.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <nanobench.h>

#include "bytes.hpp"
#include "report_queue.hpp"

namespace {
using wotex::ble::AttributeBytes;
using Queue = wotex::ble::ReportQueue<AttributeBytes>;

constexpr std::size_t reports = 64;
constexpr std::size_t charge = 320;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "report_queue: " << what << " failed\n";
  std::exit(1);
}

// Admits `reports` copies of `value`, round-robin over `streams` streams.
void admit(Queue &queue, const AttributeBytes &value, std::uint64_t streams) {
  for (std::size_t i = 0; i < reports; ++i)
    check(queue.admit(i % streams + 1, reports, value, charge), "admission");
  check(queue.size() == reports && queue.bytes() == reports * charge, "admitted");
}

// Drains the queue; streams for which `credited` is false stay queued.
template <class Credited> std::size_t drain(Queue &queue, Credited credited) {
  std::size_t dispatched = 0;
  queue.drain([&](std::uint64_t stream, const AttributeBytes &value) {
    if (!credited(stream)) return false;
    dispatched += value.value().size();
    return true;
  });
  return dispatched;
}

} // namespace

int main() {
  const AttributeBytes value = AttributeBytes::from_bytes(std::string(20, '\x5a'));
  const auto all = [](std::uint64_t) { return true; };
  const auto even = [](std::uint64_t stream) { return stream % 2 == 0; };
  Queue queue;

  ankerl::nanobench::Bench bench;
  bench.title("report queue")
      .unit("report")
      .batch(reports)
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(50));

  for (const std::uint64_t streams : {1U, 8U}) {
    const std::string name = streams == 1 ? "1 stream" : std::to_string(streams) + " streams";
    bench.run("admit 64 on " + name + ", drain all", [&] {
      admit(queue, value, streams);
      check(drain(queue, all) == reports * 20, "dispatch");
      check(queue.size() == 0 && queue.bytes() == 0 && queue.stream_records() == 0, "drained");
    });
  }
  bench.run("admit 64 on 8 streams, drain with 4 credit-blocked, discard them", [&] {
    admit(queue, value, 8);
    check(drain(queue, even) == reports / 2 * 20, "partial dispatch");
    check(queue.size() == reports / 2 && queue.stream_records() == 4, "blocked streams kept");
    for (std::uint64_t stream = 1; stream <= 8; stream += 2) queue.discard(stream);
    check(queue.size() == 0 && queue.bytes() == 0 && queue.stream_records() == 0, "discarded");
  });
  bench.run("admit 64 on 1 stream, discard", [&] {
    admit(queue, value, 1);
    queue.discard(1);
    check(queue.size() == 0 && queue.bytes() == 0 && queue.stream_records() == 0, "discarded");
  });
  return 0;
}
