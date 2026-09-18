// SPDX-License-Identifier: Apache-2.0
// Report admission in the native OSCORE helper: the cumulative report credit of
// one generation (native/oscore/credit.c), assigned, written and acknowledged
// across its window of eight, and the RFC 7641 freshness decision for each
// protected notification (observation.c). Each operation is one report.
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <nanobench.h>

extern "C" {
#include "credit.h"
#include "observation.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "oscore_report: " << what << " failed\n";
  std::exit(1);
}

constexpr std::uint16_t json_format = 50;

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.title("report").unit("report").warmup(100).minEpochTime(std::chrono::milliseconds(20));

  // Credit: the owner opens the window once, then each report is assigned a
  // sequence, written, and the whole window is acknowledged cumulatively.
  wco_credit credit;
  wco_credit_init(&credit, 1);
  check(wco_credit_ack(&credit, 1, 0) == WCO_CREDIT_OK, "credit start");
  bench.batch(WCO_REPORT_WINDOW).run("credit: assign, write and acknowledge a window of 8", [&] {
    std::uint64_t sequence = 0;
    for (unsigned index = 0; index < WCO_REPORT_WINDOW; ++index) {
      check(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_OK, "credit assign");
      check(wco_credit_written(&credit, sequence) == WCO_CREDIT_OK, "credit written");
    }
    check(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_WAIT, "credit exhausted window");
    check(wco_credit_ack(&credit, 1, credit.written) == WCO_CREDIT_OK, "credit acknowledge");
  });

  // Freshness: a notification one second after the last, in order.
  wco_observation_freshness freshness{};
  std::uint32_t observe = 1;
  std::int64_t received = 0;
  check(wco_observation_admit(&freshness, observe, received, 1, json_format, 0) ==
            WCO_OBSERVATION_FRESH,
        "initial report");
  bench.batch(1).run("freshness: admit the next notification", [&] {
    observe = (observe + 1) & 0xffffffU;
    received += 1000;
    check(wco_observation_admit(&freshness, observe, received, 1, json_format, 0) ==
              WCO_OBSERVATION_FRESH,
          "fresh notification");
  });

  // A replay of the last admitted notification within 128 seconds.
  bench.run("freshness: reject a replayed notification", [&] {
    check(wco_observation_admit(&freshness, observe, received + 10, 1, json_format, 0) ==
              WCO_OBSERVATION_STALE,
          "replayed notification");
  });

  // The 24-bit serial number wrapping from 0xffffff to 0.
  bench.run("freshness: admit across the 24-bit wraparound", [&] {
    wco_observation_freshness wrapped{received, 0xffffffU, json_format, 1, 1};
    check(wco_observation_admit(&wrapped, 0, received + 10, 1, json_format, 0) ==
              WCO_OBSERVATION_FRESH,
          "wrapped notification");
    ankerl::nanobench::doNotOptimizeAway(wrapped);
  });

  // A notification whose Content-Format differs from the registration's.
  bench.run("freshness: detect a changed Content-Format", [&] {
    check(wco_observation_admit(&freshness, (observe + 1) & 0xffffffU, received + 1000, 1, 0, 0) ==
              WCO_OBSERVATION_CHANGED,
          "changed Content-Format");
  });

  return 0;
}
