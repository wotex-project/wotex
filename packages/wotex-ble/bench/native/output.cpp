// SPDX-License-Identifier: Apache-2.0
// Bounded serialization and nonblocking output of the BLE native host
// (priv/bluez/native/output.hpp): validation and encoding of a value report
// envelope into a frame, and admission followed by a flush through write(2)
// to /dev/null of 64 replies (each into its reserved slot) and of 64 report
// frames with increasing report sequences. Each operation is one frame.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <nanobench.h>

#include "bytes.hpp"
#include "output.hpp"

namespace {
using wotex::ble::AttributeBytes;
using wotex::ble::EncodedFrame;
using wotex::ble::Json;
using wotex::ble::NativeOutput;

constexpr std::size_t frames = 64;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "output: " << what << " failed\n";
  std::exit(1);
}

Json metadata() {
  return {{"source", "bluez_value_change"},
          {"requested_mode", "auto"},
          {"effective_mode", "notify"},
          {"characteristic",
           {{"service_uuid", "0000181a-0000-1000-8000-00805f9b34fb"},
            {"characteristic_uuid", "00002a6e-0000-1000-8000-00805f9b34fb"},
            {"service_path", "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service000e"},
            {"object_path", "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service000e/char000f"},
            {"handle", 15},
            {"flags", {"read", "notify"}},
            {"generation", 1}}}};
}

// The value report NativeReports emits for a `size`-byte value.
Json report(std::size_t size, std::uint64_t sequence) {
  return {{"version", 1},
          {"session_generation", "0123456789abcdef0123456789abcdef"},
          {"report_sequence", sequence},
          {"subscription_id", "7"},
          {"generation", 1},
          {"event", "value"},
          {"value", AttributeBytes::from_bytes(std::string(size, '\x5a')).envelope()},
          {"metadata", metadata()}};
}

void drain(NativeOutput &output, int sink) {
  for (unsigned turn = 0; output.pending_frames() != 0; ++turn) {
    check(turn < 1024, "drain");
    output.flush(sink);
  }
}

} // namespace

int main() {
  const int sink = ::open("/dev/null", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
  check(sink >= 0, "open /dev/null");
  auto output = std::make_unique<NativeOutput>();
  std::uint64_t sequence = 0;

  ankerl::nanobench::Bench bench;
  bench.title("native output").unit("frame").warmup(100).minEpochTime(std::chrono::milliseconds(20));

  for (const std::size_t size : {20U, 512U}) {
    const Json envelope = report(size, UINT64_MAX);
    const std::size_t encoded = EncodedFrame::from(envelope).size();
    check(encoded < 4096, "report size");
    bench.run("encode report, " + std::to_string(size) + " B value", [&] {
      const EncodedFrame frame = EncodedFrame::from(envelope);
      check(frame.size() == encoded, "encoded size");
      ankerl::nanobench::doNotOptimizeAway(frame);
    });
  }

  const EncodedFrame reply = EncodedFrame::from(
      Json{{"version", 1},
           {"id", "42"},
           {"ok", true},
           {"result", {{"type", "bytes"}, {"base64", "NBI="}}}});
  bench.batch(frames).run("reserve, reply and flush 64 replies", [&] {
    for (std::size_t i = 0; i < frames; ++i) {
      const auto slot = output->reserve_reply();
      check(slot.has_value(), "reservation");
      // NOLINTNEXTLINE(bugprone-unchecked-optional-access): check ends the run when slot is empty
      check(output->reply(*slot, reply), "reply");
    }
    drain(*output, sink);
    check(output->reply_reservations() == 0, "released slots");
  });

  for (const std::size_t size : {20U, 512U}) {
    std::vector<EncodedFrame> reports;
    reports.reserve(frames);
    for (std::size_t i = 0; i < frames; ++i)
      reports.push_back(EncodedFrame::from(report(size, i + 1)));
    bench.batch(frames).run("admit and flush 64 reports, " + std::to_string(size) + " B value",
                            [&] {
      for (const EncodedFrame &frame : reports)
        check(output->report(frame, ++sequence), "report admission");
      drain(*output, sink);
      check(output->transmitted_report_sequence() == sequence && output->report_bytes() == 0,
            "report transmission");
    });
  }

  ::close(sink);
  return 0;
}
