// SPDX-License-Identifier: Apache-2.0
// The native report path of the BLE host (priv/bluez/native/reports.hpp with
// credit.hpp, report_queue.hpp, output.hpp, bytes.hpp and error_value.hpp):
// publication of value callbacks (envelope validation, base64 decoding,
// report encoding, credit reservation and output admission), a flush through
// write(2) to /dev/null and the owner's cumulative acknowledgement. 16
// reports fill one stream's credit window; 64 reports exceed it, so 48 wait in
// the queue and drain as acknowledgements return credit. The subscription
// rows open a stream (metadata validation and its worst-case report bound)
// and retire it with its barrier, with or without a terminal error control.
// The unit is one report, or one subscription.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <fcntl.h>
#include <unistd.h>
#include <nanobench.h>

#include "reports.hpp"

namespace {
using wotex::ble::AttributeBytes;
using wotex::ble::Json;
using wotex::ble::NativeOutput;
using wotex::ble::NativeReports;

const std::string generation = "0123456789abcdef0123456789abcdef";

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "reports: " << what << " failed\n";
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

// The value callback NativeNotifications passes to NativeReports::publish.
Json callback(std::uint64_t stream, std::size_t size) {
  return {{"version", 1},
          {"subscription_id", std::to_string(stream)},
          {"generation", 1},
          {"event", "value"},
          {"value", AttributeBytes::from_bytes(std::string(size, '\x5a')).envelope()},
          {"metadata", metadata()}};
}

// The host's output and report owners, and the BEAM owner's side: every
// flushed report is received, and acknowledgements are cumulative.
class Session {
  int sink_;
  NativeOutput output_;
  NativeReports reports_{output_, generation};
  std::uint64_t received_ = 0;
  Json ack_{{"version", 1},
            {"event", "report_ack"},
            {"session_generation", generation},
            {"report_sequence", 1},
            {"acknowledged_bytes", 1}};

 public:
  explicit Session(int sink) : sink_(sink) {}
  NativeReports &reports() { return reports_; }
  void flush() {
    received_ += output_.report_bytes();
    for (unsigned turn = 0; output_.pending_frames() != 0; ++turn) {
      check(turn < 1024, "flush");
      output_.flush(sink_);
    }
  }
  void acknowledge() {
    ack_["report_sequence"] = output_.transmitted_report_sequence();
    ack_["acknowledged_bytes"] = received_;
    reports_.acknowledge(ack_);
  }
  // Flushes and acknowledges until no report is queued or unacknowledged.
  unsigned settle() {
    unsigned rounds = 0;
    do {
      flush();
      acknowledge();
      ++rounds;
    } while (reports_.queued_reports() != 0 || output_.pending_frames() != 0);
    check(reports_.available_frames() == 64 && reports_.queued_bytes() == 0, "settled");
    return rounds;
  }
};

} // namespace

int main() {
  const int sink = ::open("/dev/null", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
  check(sink >= 0, "open /dev/null");
  auto session = std::make_unique<Session>(sink);
  NativeReports &reports = session->reports();
  const Json bound = metadata();
  std::uint64_t stream = 0;

  ankerl::nanobench::Bench bench;
  bench.title("native report path")
      .unit("report")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  for (const std::size_t size : {20U, 512U}) {
    check(reports.open(++stream, bound, 64), "open");
    const Json value = callback(stream, size);
    bench.batch(16).run("publish, flush and acknowledge 16 x " + std::to_string(size) + " B", [&] {
      for (int i = 0; i < 16; ++i) check(reports.publish(value), "publish");
      check(reports.queued_reports() == 0, "within the window");
      check(session->settle() == 1, "one acknowledgement");
    });
  }

  check(reports.open(++stream, bound, 64), "open");
  const Json queued = callback(stream, 20);
  bench.batch(64).run("publish 64 x 20 B beyond the 16-report window, drain by acknowledgement",
                      [&] {
    for (int i = 0; i < 64; ++i) check(reports.publish(queued), "publish");
    check(reports.queued_reports() == 48, "queued beyond the window");
    check(session->settle() == 4, "four acknowledgements");
  });

  const std::optional<Json> failure = Json{{"code", "subscription_lost"}};
  bench.title("native report subscriptions").unit("subscription").batch(1);
  for (const bool terminal : {false, true}) {
    bench.run(terminal ? "open and retire with a terminal error" : "open and retire", [&] {
      check(reports.open(++stream, bound, 16), "open");
      check(reports.retire(stream, terminal ? failure : std::nullopt), "retire");
      session->flush();
      check(reports.active_streams() == 3 && reports.credit_records() == 3, "retired");
    });
  }

  ::close(sink);
  return 0;
}
