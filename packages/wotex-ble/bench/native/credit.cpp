// SPDX-License-Identifier: Apache-2.0
// Cumulative report credit of the BLE native host (priv/bluez/native/credit.hpp):
// reservation of 320-byte reports and the validated cumulative
// acknowledgement frame that returns their credit, for one stream filling its
// 16-report window and for 64 streams with one report each, and the lifecycle
// of a stream (open, reserve, retire, acknowledge). The unit is one report,
// or one stream for the lifecycle.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <nanobench.h>

#include "credit.hpp"

namespace {
using wotex::ble::Credits;
using wotex::ble::Json;

const std::string generation = "0123456789abcdef0123456789abcdef";
constexpr std::size_t report_bytes = 320;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "credit: " << what << " failed\n";
  std::exit(1);
}

// The owner's report_ack frame; each acknowledgement rewrites its two counters.
class Acknowledgement {
  Json frame_{{"version", 1},
              {"event", "report_ack"},
              {"session_generation", generation},
              {"report_sequence", 1},
              {"acknowledged_bytes", 1}};
  std::uint64_t bytes_ = 0;

 public:
  void sent(std::size_t bytes) { bytes_ += bytes; }
  void apply(Credits &credits, std::uint64_t sequence) {
    frame_["report_sequence"] = sequence;
    frame_["acknowledged_bytes"] = bytes_;
    credits.acknowledge(frame_);
  }
};

std::uint64_t reserve(Credits &credits, Acknowledgement &ack, std::uint64_t stream) {
  const auto sequence = credits.reserve(stream, report_bytes);
  check(sequence.has_value(), "reservation");
  ack.sent(report_bytes);
  // NOLINTNEXTLINE(bugprone-unchecked-optional-access): check ends the run when sequence is empty
  return *sequence;
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.title("report credit")
      .unit("report")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  Credits window(generation);
  Acknowledgement window_ack;
  check(window.open(1, 64), "open");
  bench.batch(16).run("reserve 16 on 1 stream, acknowledge once", [&] {
    std::uint64_t last = 0;
    for (int i = 0; i < 16; ++i) last = reserve(window, window_ack, 1);
    check(window.available_frames() == 48, "window reserved");
    window_ack.apply(window, last);
    check(window.available_frames() == Credits::frame_limit, "window returned");
  });

  Credits streams(generation);
  Acknowledgement streams_ack;
  for (std::uint64_t stream = 1; stream <= 64; ++stream) check(streams.open(stream, 16), "open");
  check(!streams.open(65, 16), "live stream bound");
  bench.batch(64).run("reserve 1 on each of 64 streams, acknowledge once", [&] {
    std::uint64_t last = 0;
    for (std::uint64_t stream = 1; stream <= 64; ++stream)
      last = reserve(streams, streams_ack, stream);
    check(streams.available_frames() == 0, "streams reserved");
    streams_ack.apply(streams, last);
    check(streams.available_bytes() == Credits::byte_limit, "streams returned");
  });

  Credits lifecycle(generation);
  Acknowledgement lifecycle_ack;
  std::uint64_t identifier = 0;
  bench.title("stream credit lifecycle").unit("stream").batch(1);
  bench.run("open, reserve, retire and acknowledge", [&] {
    check(lifecycle.open(++identifier, 16), "open");
    const std::uint64_t sequence = reserve(lifecycle, lifecycle_ack, identifier);
    lifecycle.retire(identifier, sequence);
    lifecycle_ack.apply(lifecycle, sequence);
    check(lifecycle.stream_records() == 0 && lifecycle.active_streams() == 0, "stream released");
  });
  return 0;
}
