// SPDX-License-Identifier: Apache-2.0
// The report credit of the Thread host (priv/openthread/flow.hpp): credited
// submission and exact cumulative acknowledgement of reports on one and four
// streams, queueing beyond the per-stream credit with draining on
// acknowledgement, and retirement of streams with outstanding and queued
// reports. Reports are 212 encoded bytes, newline included, as in the
// BEAM-side ledger benchmark (bench/report_ledger_bench.exs).
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include <nanobench.h>

#include "flow.hpp"

namespace {

using namespace wotex::thread;
using Submission = ReportFlow::Submission;

static_assert(kSessionReportFrames == 64 && kStreamReportFrames == 16 && kMaximumLiveStreams == 64,
              "the native_bench description of report_flow names these limits");

const std::string kSession = "0123456789abcdef0123456789abcdef";
constexpr std::size_t kReportBytes = 212;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "report_flow: " << what << " failed\n";
  std::exit(1);
}

// What the flow wrote; the host's writers push the same frames onto its output lanes.
struct Sink {
  std::uint64_t reports = 0;
  std::uint64_t bytes = 0; // cumulative encoded report bytes, newline included
  std::uint64_t barriers = 0;
};

ReportFlow counted(Sink &sink) {
  return ReportFlow(kSession, [&sink](const std::string &frame) {
    ++sink.reports;
    sink.bytes += frame.size() + 1;
    return true;
  }, [&sink](const std::string &) {
    ++sink.barriers;
    return true;
  });
}

// A report naming its assigned sequence, padded to kReportBytes with its newline.
std::string encode(std::uint64_t sequence) {
  std::string frame = "{\"report_sequence\":" + std::to_string(sequence) + ",\"value\":\"";
  frame.append(kReportBytes - frame.size() - 3, 'x');
  frame.append("\"}");
  return frame;
}

std::string barrier(std::uint64_t last) {
  return "{\"event\":\"stream_retired\",\"last_report_sequence\":" + std::to_string(last) + "}";
}

// Acknowledges every transmitted report with the exact cumulative byte count.
void acknowledge(ReportFlow &flow, const Sink &sink) {
  check(flow.acknowledge(kSession, flow.snapshot().last_sequence, sink.bytes), "acknowledgement");
}

void drained(const ReportFlow &flow, const char *what) {
  const ReportFlow::Snapshot snapshot = flow.snapshot();
  check(!flow.failed() && snapshot.queued == 0 && snapshot.queued_bytes == 0 &&
            snapshot.frame_credit == kSessionReportFrames &&
            snapshot.byte_credit == kSessionReportBytes &&
            snapshot.acknowledged_sequence == snapshot.last_sequence,
        what);
}

std::vector<std::string> subscriptions(std::size_t count) {
  std::vector<std::string> ids;
  ids.reserve(count);
  for (std::size_t index = 0; index < count; ++index) ids.push_back(std::to_string(17 + index));
  return ids;
}

void credit(ankerl::nanobench::Bench &bench, const ReportFlow::Encoder &report) {
  bench.title("report credit").unit("report");

  {
    Sink sink;
    ReportFlow flow = counted(sink);
    const std::string id = "17";
    check(flow.add_stream(id, 1, 64), "add stream");
    bench.batch(kStreamReportFrames).run("16 reports on 1 stream, acknowledged", [&] {
      for (std::size_t index = 0; index < kStreamReportFrames; ++index)
        check(flow.submit(id, 1, report) == Submission::transmitted, "transmission");
      acknowledge(flow, sink);
    });
    drained(flow, "16 reports on 1 stream");
  }

  {
    Sink sink;
    ReportFlow flow = counted(sink);
    const std::vector<std::string> ids = subscriptions(4);
    for (const std::string &id : ids) check(flow.add_stream(id, 1, 64), "add stream");
    bench.batch(kSessionReportFrames).run("64 reports on 4 streams, acknowledged", [&] {
      for (std::size_t index = 0; index < kSessionReportFrames; ++index)
        check(flow.submit(ids[index % ids.size()], 1, report) == Submission::transmitted,
              "transmission");
      acknowledge(flow, sink);
    });
    drained(flow, "64 reports on 4 streams");
  }

  {
    // 16 reports use the stream's credit and 48 wait; each acknowledgement
    // releases 16 and drains the next 16 with their assigned sequences.
    Sink sink;
    ReportFlow flow = counted(sink);
    const std::string id = "17";
    check(flow.add_stream(id, 1, 64), "add stream");
    bench.batch(64).run("64 reports on 1 stream, 48 queued, drained by 4 acknowledgements", [&] {
      const std::uint64_t before = sink.reports;
      for (std::size_t index = 0; index < 64; ++index) {
        const Submission expected = index < kStreamReportFrames ? Submission::transmitted
                                                                : Submission::queued;
        check(flow.submit(id, 1, report) == expected, "submission");
      }
      for (int round = 0; round < 4; ++round) acknowledge(flow, sink);
      check(sink.reports - before == 64, "drain");
    });
    drained(flow, "64 reports on 1 stream");
  }
}

void retirement(ankerl::nanobench::Bench &bench, const ReportFlow::Encoder &report) {
  bench.title("stream retirement").unit("stream");
  const ReportFlow::BarrierEncoder encode_barrier = barrier;

  {
    Sink sink;
    ReportFlow flow = counted(sink);
    const std::string id = "17";
    std::uint64_t generation = 0;
    bench.batch(1).run("16 outstanding and 16 queued reports, retired, acknowledged", [&] {
      check(flow.add_stream(id, ++generation, 64), "add stream");
      for (std::size_t index = 0; index < 2 * kStreamReportFrames; ++index) {
        const Submission expected = index < kStreamReportFrames ? Submission::transmitted
                                                                : Submission::queued;
        check(flow.submit(id, generation, report) == expected, "submission");
      }
      check(flow.retire(id, generation, encode_barrier), "retirement");
      acknowledge(flow, sink);
      check(flow.retained_streams() == 0, "release");
    });
    drained(flow, "retirement of 1 stream");
    check(sink.barriers == generation, "barriers");
  }

  {
    Sink sink;
    ReportFlow flow = counted(sink);
    const std::vector<std::string> ids = subscriptions(kMaximumLiveStreams);
    std::uint64_t generation = 0;
    bench.batch(kMaximumLiveStreams).run("64 streams of 1 report, retired, acknowledged", [&] {
      ++generation;
      for (const std::string &id : ids) check(flow.add_stream(id, generation, 64), "add stream");
      for (const std::string &id : ids)
        check(flow.submit(id, generation, report) == Submission::transmitted, "transmission");
      for (const std::string &id : ids)
        check(flow.retire(id, generation, encode_barrier), "retirement");
      acknowledge(flow, sink);
      check(flow.retained_streams() == 0, "release");
    });
    drained(flow, "retirement of 64 streams");
    check(sink.barriers == generation * kMaximumLiveStreams, "barriers");
  }
}

} // namespace

int main() {
  check(encode(1).size() + 1 == kReportBytes && encode(UINT64_MAX).size() + 1 == kReportBytes,
        "report size");
  const ReportFlow::Encoder report = encode;

  ankerl::nanobench::Bench bench;
  bench.warmup(100).minEpochTime(std::chrono::milliseconds(20));
  credit(bench, report);
  retirement(bench, report);
  return 0;
}
