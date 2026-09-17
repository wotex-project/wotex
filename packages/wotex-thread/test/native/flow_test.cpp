#define WOTEX_THREAD_FLOW_TESTING 1
#include "flow.hpp"
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

using namespace wotex::thread;
using Submission = ReportFlow::Submission;

namespace {
const std::string kSession = "0123456789abcdef0123456789abcdef";

void check(bool value) {
  if (!value) std::abort();
}

struct Channel {
  std::vector<std::string> reports, controls;
  bool report_open = true, control_open = true;
  ReportFlow flow() {
    return ReportFlow(
        kSession,
        [this](const std::string &frame) { if (report_open) reports.push_back(frame); return report_open; },
        [this](const std::string &frame) { if (control_open) controls.push_back(frame); return control_open; });
  }
};

// Every report encodes its sequence so a queued report proves re-encoding.
ReportFlow::Encoder sized(std::size_t bytes) {
  return [bytes](std::uint64_t sequence) {
    std::string frame = std::to_string(sequence) + ":";
    if (frame.size() + 1 > bytes) return std::string();
    frame.append(bytes - frame.size() - 1, 'x');
    return frame;
  };
}

ReportFlow::BarrierEncoder barrier() {
  return [](std::uint64_t last) { return "retired:" + std::to_string(last); };
}

std::uint64_t sequence(const std::string &frame) { return std::stoull(frame.substr(0, frame.find(':'))); }
}  // namespace

int main() {
  // WTH-B02: session identity is exactly 32 lowercase hexadecimal characters.
  check(session_generation(kSession));
  for (const auto &value : std::vector<std::string>{"", "0123456789ABCDEF0123456789abcdef", kSession + "0",
                                                   "0123456789abcdef0123456789abcdeg"}) {
    check(!session_generation(value));
  }

  {
    // WTH-B02: per-stream credit is min(16, queue_limit); byte and frame credit return only on ACK.
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("s1", 1, 4) && !flow.add_stream("s1", 1, 4));
    check(!flow.add_stream("", 1, 4) && !flow.add_stream("s0", 0, 4) && !flow.add_stream("s0", 1, 0) &&
          !flow.add_stream("s0", 1, 10001) && !flow.add_stream(std::string(65, 's'), 1, 1));
    for (int index = 0; index < 4; ++index) check(flow.submit("s1", 1, sized(128)) == Submission::transmitted);
    check(flow.submit("s1", 1, sized(128)) == Submission::queued);
    auto snapshot = flow.snapshot();
    check(snapshot.frame_credit == 60 && snapshot.byte_credit == kSessionReportBytes - 512 && snapshot.queued == 1);
    check(snapshot.queued_bytes == sized(128)(UINT64_MAX).size() + 1);
    // Wrong session, zero, skipped untransmitted and wrong cumulative bytes fail without mutation.
    check(!flow.acknowledge("fedcba9876543210fedcba9876543210", 1, 128));
    check(!flow.acknowledge(kSession, 0, 0) && !flow.acknowledge(kSession, 5, 640));
    check(!flow.acknowledge(kSession, 2, 255) && !flow.acknowledge(kSession, 2, 128));
    check(flow.snapshot().frame_credit == 60 && channel.reports.size() == 4);
    // A cumulative prefix releases two records and drains the queued report with sequence five.
    check(flow.acknowledge(kSession, 2, 256));
    check(channel.reports.size() == 5 && sequence(channel.reports.back()) == 5 && channel.reports.back().size() == 127);
    snapshot = flow.snapshot();
    check(snapshot.queued == 0 && snapshot.queued_bytes == 0 && snapshot.frame_credit == 61 &&
          snapshot.acknowledged_sequence == 2 && snapshot.last_sequence == 5);
    // Repeated and decreased acknowledgements are invalid frames.
    check(!flow.acknowledge(kSession, 2, 256) && !flow.acknowledge(kSession, 1, 128));
    check(flow.acknowledge(kSession, 5, 640) && flow.snapshot().frame_credit == 64);
  }

  {
    // WTH-B02: session frame credit is 64 and a blocked stream does not block another.
    Channel channel; auto flow = channel.flow();
    for (int stream = 0; stream < 4; ++stream) check(flow.add_stream("s" + std::to_string(stream), 1, 100));
    for (int stream = 0; stream < 4; ++stream) {
      for (int index = 0; index < 16; ++index) check(flow.submit("s" + std::to_string(stream), 1, sized(64)) == Submission::transmitted);
    }
    check(flow.snapshot().frame_credit == 0 && flow.submit("s0", 1, sized(64)) == Submission::queued);
    check(flow.submit("s1", 1, sized(64)) == Submission::queued);
    check(flow.acknowledge(kSession, 16, 16 * 64));
    // The released s0 credit drains s0; s1 remains at its own 16-report limit.
    check(channel.reports.size() == 65 && flow.snapshot().queued == 1 && flow.snapshot().frame_credit == 15);
  }

  {
    // WTH-B02: byte credit, shared 64-report queue and per-stream queue_limit overflow.
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("large", 1, 10000) && flow.add_stream("small", 1, 2) && flow.add_stream("other", 1, 10000));
    for (int index = 0; index < 8; ++index) check(flow.submit("large", 1, sized(kMaximumReportLine)) == Submission::transmitted);
    check(flow.snapshot().byte_credit == 0 && flow.submit("large", 1, sized(1)) == Submission::overflow);
    check(flow.submit("small", 1, sized(64)) == Submission::queued && flow.submit("small", 1, sized(64)) == Submission::queued);
    check(flow.submit("small", 1, sized(64)) == Submission::overflow);
    for (int index = 0; index < 62; ++index) check(flow.submit("other", 1, sized(64)) == Submission::queued);
    check(flow.submit("other", 1, sized(64)) == Submission::overflow && flow.snapshot().queued == 64);
    check(flow.submit("large", 1, sized(kMaximumReportLine + 1)) == Submission::overflow);
  }

  {
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("wide", 1, 10000));
    for (int index = 0; index < 16; ++index) check(flow.submit("wide", 1, sized(64)) == Submission::transmitted);
    for (int index = 0; index < 8; ++index) check(flow.submit("wide", 1, sized(kMaximumReportLine)) == Submission::queued);
    check(flow.snapshot().queued_bytes == 8 * kMaximumReportLine);
    check(flow.submit("wide", 1, sized(kMaximumReportLine)) == Submission::overflow);
  }

  {
    // WTH-B02: retirement discards unsent reports, emits one barrier after the
    // stream's transmitted frames and retains outstanding credit until ACK.
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("s1", 7, 1) && flow.add_stream("s2", 1, 16));
    check(flow.submit("s1", 7, sized(100)) == Submission::transmitted);
    check(flow.submit("s1", 7, sized(100)) == Submission::queued);
    check(flow.submit("s2", 1, sized(100)) == Submission::transmitted);
    check(flow.retire("s1", 7, barrier()) && channel.controls == std::vector<std::string>{"retired:1"});
    check(!flow.live("s1", 7) && !flow.retire("s1", 7, barrier()) && flow.submit("s1", 7, sized(100)) == Submission::failed);
    auto snapshot = flow.snapshot();
    check(snapshot.queued == 0 && snapshot.queued_bytes == 0 && snapshot.frame_credit == 62 && flow.retained_streams() == 2);
    check(flow.acknowledge(kSession, 2, 200) && flow.retained_streams() == 1 && flow.snapshot().frame_credit == 64);
    // A never-transmitted stream retires with sequence zero and releases its record immediately.
    check(flow.add_stream("empty", 1, 1) && flow.retire("empty", 1, barrier()));
    check(channel.controls.back() == "retired:0" && flow.retained_streams() == 1);
    check(flow.add_stream("empty", 2, 1));
  }

  {
    // WTH-B02: at most 64 live streams; retired streams do not consume live capacity.
    Channel channel; auto flow = channel.flow();
    for (int stream = 0; stream < 64; ++stream) check(flow.add_stream("s" + std::to_string(stream), 1, 1));
    check(!flow.add_stream("s64", 1, 1) && flow.retire("s0", 1, barrier()) && flow.add_stream("s64", 1, 1));
  }

  {
    // WTH-B02: writer failures and counter exhaustion terminate the generation.
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("s1", 1, 16));
    channel.report_open = false;
    check(flow.submit("s1", 1, sized(64)) == Submission::failed && flow.failed());
    check(!flow.add_stream("s2", 1, 1) && !flow.acknowledge(kSession, 1, 64));
  }
  {
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("s1", 1, 16));
    channel.control_open = false;
    check(!flow.retire("s1", 1, barrier()) && flow.failed());
  }
  {
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("s1", 1, 16) && flow.seed_counters_for_testing(UINT64_MAX - 1, 0));
    check(flow.submit("s1", 1, sized(64)) == Submission::transmitted && sequence(channel.reports.back()) == UINT64_MAX - 1);
    check(flow.submit("s1", 1, sized(64)) == Submission::failed && flow.failed());
  }
  {
    Channel channel; auto flow = channel.flow();
    check(flow.add_stream("s1", 1, 16) && flow.seed_counters_for_testing(1, UINT64_MAX - 63));
    check(flow.submit("s1", 1, sized(63)) == Submission::transmitted);
    check(flow.submit("s1", 1, sized(64)) == Submission::failed && flow.failed());
  }
  return 0;
}
