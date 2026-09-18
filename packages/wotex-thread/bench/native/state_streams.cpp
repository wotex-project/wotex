// SPDX-License-Identifier: Apache-2.0
// The State report streams of the Thread host (priv/openthread/streams.hpp over
// priv/openthread/flow.hpp): coalesced snapshot flushes to one and to 64
// streams with acknowledgement, queueing and draining beyond the per-stream
// credit, and the lifecycle of one subscription from registration to
// cancellation or to terminal queue overflow.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include <nanobench.h>

#include "streams.hpp"

namespace {

using namespace wotex::thread;

static_assert(kStreamReportFrames == 16 && kMaximumLiveStreams == 64,
              "the native_bench description of state_streams names these limits");

const std::string kSession = "0123456789abcdef0123456789abcdef";
// OT_CHANGED_THREAD_ROLE, the flag of a role change.
constexpr std::uint32_t kRoleChanged = 1U << 2;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "state_streams: " << what << " failed\n";
  std::exit(1);
}

// The State snapshot the SDK host builds for each flush (sdk.hpp, Sdk::snapshot).
Json snapshot() {
  return {{"role", "router"},     {"network_name", "fixture"}, {"rloc16", 1024},
          {"ipv6_enabled", true}, {"thread_enabled", true},    {"generation", 1}};
}

// One report-flow owner and its State streams. The writers count frames and
// copy the last report, as the host's writers copy each frame onto a lane.
struct Harness {
  std::uint64_t reports = 0;
  std::uint64_t report_bytes = 0; // cumulative, newline included
  std::uint64_t controls = 0;
  std::string last;
  ReportFlow flow{kSession, [this](const std::string &frame) {
    ++reports;
    report_bytes += frame.size() + 1;
    last.assign(frame);
    return true;
  }, [this](const std::string &) {
    ++controls;
    return true;
  }};
  StateStreams streams{flow, [this](const std::string &) {
    ++controls;
    return true;
  }};

  Harness() = default;
  Harness(const Harness &) = delete;
  Harness &operator=(const Harness &) = delete;

  void acknowledge() {
    check(flow.acknowledge(kSession, flow.snapshot().last_sequence, report_bytes),
          "acknowledgement");
  }

  // Every report acknowledged, nothing queued, the last report a well-formed State report.
  void settled(std::size_t listeners, const char *what) const {
    const ReportFlow::Snapshot credit = flow.snapshot();
    check(!streams.failed() && streams.size() == listeners && credit.queued == 0 &&
              credit.frame_credit == kSessionReportFrames &&
              credit.acknowledged_sequence == credit.last_sequence &&
              credit.last_sequence == reports,
          what);
    const Json report = Json::parse(last);
    check(report.at("event") == "state" && report.at("report_sequence") == credit.last_sequence &&
              report.at("value") == snapshot(),
          what);
  }
};

std::string subscription(std::uint64_t index) { return std::to_string(17 + index); }

void flushes(ankerl::nanobench::Bench &bench) {
  bench.title("State reports").unit("report");

  {
    Harness harness;
    const std::uint64_t generation = harness.streams.open("17", 64);
    check(generation != 0, "open");
    harness.streams.initial("17", generation, snapshot());
    harness.acknowledge();
    bench.batch(1).run("1 flush to 1 stream, acknowledged", [&] {
      const std::uint64_t before = harness.reports;
      harness.streams.changed(kRoleChanged);
      harness.streams.flush(snapshot);
      check(harness.reports == before + 1, "report");
      harness.acknowledge();
    });
    harness.settled(1, "1 flush to 1 stream");
  }

  {
    Harness harness;
    for (std::uint64_t index = 0; index < kMaximumLiveStreams; ++index) {
      const std::uint64_t generation = harness.streams.open(subscription(index), 64);
      check(generation != 0, "open");
      harness.streams.initial(subscription(index), generation, snapshot());
    }
    harness.acknowledge();
    bench.batch(kMaximumLiveStreams).run("1 flush to 64 streams, acknowledged", [&] {
      const std::uint64_t before = harness.reports;
      harness.streams.changed(kRoleChanged);
      harness.streams.flush(snapshot);
      check(harness.reports == before + kMaximumLiveStreams, "reports");
      harness.acknowledge();
    });
    harness.settled(kMaximumLiveStreams, "1 flush to 64 streams");
  }

  {
    // 16 reports use the stream's credit and 48 wait with their own snapshot;
    // each acknowledgement drains the next 16 with newly assigned sequences.
    Harness harness;
    const std::uint64_t generation = harness.streams.open("17", 64);
    check(generation != 0, "open");
    harness.streams.initial("17", generation, snapshot());
    harness.acknowledge();
    bench.batch(64).run("64 flushes to 1 stream, 48 queued, drained by 4 acknowledgements", [&] {
      const std::uint64_t before = harness.reports;
      for (int iteration = 0; iteration < 64; ++iteration) {
        harness.streams.changed(kRoleChanged);
        harness.streams.flush(snapshot);
      }
      check(harness.reports == before + kStreamReportFrames && harness.flow.snapshot().queued == 48,
            "queue");
      for (int round = 0; round < 4; ++round) harness.acknowledge();
      check(harness.reports == before + 64, "drain");
    });
    harness.settled(1, "64 flushes to 1 stream");
  }
}

void lifecycle(ankerl::nanobench::Bench &bench) {
  bench.title("State subscriptions").unit("subscription").batch(1);

  {
    Harness harness;
    std::uint64_t index = 0;
    bench.run("open, initial report, remove, acknowledged", [&] {
      const std::string id = subscription(index++);
      const std::uint64_t controls = harness.controls;
      const std::uint64_t generation = harness.streams.open(id, 64);
      check(generation != 0, "open");
      harness.streams.initial(id, generation, snapshot());
      check(harness.streams.remove(id, generation), "remove");
      check(harness.controls == controls + 1, "retirement barrier");
      harness.acknowledge();
      check(harness.flow.retained_streams() == 0, "release");
    });
    harness.settled(0, "subscription removal");
  }

  {
    // A queue_limit of 2 allows 2 transmitted and 2 queued reports; the fifth
    // report overflows into one stream_error frame and the retirement barrier.
    Harness harness;
    std::uint64_t index = 0;
    bench.run("open, 5 reports with queue_limit 2, overflow, acknowledged", [&] {
      const std::string id = subscription(index++);
      const std::uint64_t controls = harness.controls;
      const std::size_t errors = harness.streams.stream_errors();
      const std::uint64_t generation = harness.streams.open(id, 2);
      check(generation != 0, "open");
      harness.streams.initial(id, generation, snapshot());
      for (int iteration = 0; iteration < 4; ++iteration) {
        harness.streams.changed(kRoleChanged);
        harness.streams.flush(snapshot);
      }
      check(harness.streams.stream_errors() == errors + 1 && harness.controls == controls + 2 &&
                harness.streams.size() == 0,
            "overflow");
      harness.acknowledge();
      check(harness.flow.retained_streams() == 0, "release");
    });
    harness.settled(0, "subscription overflow");
  }
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.warmup(100).minEpochTime(std::chrono::milliseconds(20));
  flushes(bench);
  lifecycle(bench);
  return 0;
}
