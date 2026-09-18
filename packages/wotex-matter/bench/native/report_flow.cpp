// SPDX-License-Identifier: Apache-2.0
// Subscription report flow of the Matter controller host: report assembly by
// SubscriptionBuffer and credited transmission by ReportCreditManager
// (native/src/subscription.cpp), and a report's full path through
// HostProtocol (native/src/protocol.cpp): the backend's report callback, the
// subscription_report frame, session and stream credit, and the BEAM's
// report_ack that returns the credit. The host grants 64 reports and 1 MiB of
// session credit and 16 reports of credit per stream. Each operation is one
// report.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include <nanobench.h>

#include "scripted_backend.hpp"
#include "wotex_matter/protocol.hpp"
#include "wotex_matter/subscription.hpp"

namespace {

using namespace wotex::matter;
using namespace wotex::matter::bench;

constexpr char kSubscriptionId[] = "abcdef0123456789abcdef0123456789";
constexpr std::size_t kStreamCredit = 16;
constexpr std::size_t kSessionCredit = 64;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "report_flow: " << what << " failed\n";
  std::exit(1);
}

// The four attribute recipes a subscription admits, on endpoint 1:
// LocalTemperature, OnOff, Reachable and MeasuredValue.
const std::pair<std::uint32_t, std::uint32_t> kRecipes[] = {
    {0x0201, 0x0000}, {0x0006, 0x0000}, {0x0039, 0x0011}, {0x0402, 0x0000}};

SubscriptionRequest subscription_request() {
  SubscriptionRequest request;
  request.subscription_id = kSubscriptionId;
  request.kind = SubscriptionKind::Attribute;
  request.fabric_id = kFabric;
  request.node_id = kNode;
  for (const auto &recipe : kRecipes)
    request.paths.push_back({kFabric, kNode, std::uint16_t{1}, recipe.first, recipe.second});
  request.min_interval_s = 1;
  request.max_interval_s = 60;
  request.queue_limit = 64;
  request.timeout_ms = 30000;
  return request;
}

PathResult attribute(std::size_t recipe, std::uint32_t version) {
  const auto &[cluster, member] = kRecipes[recipe];
  PathResult result;
  result.path = {kFabric, kNode, 1, cluster, member};
  Element value = typed(cluster == 0x0006 || cluster == 0x0039 ? ElementType::Boolean
                                                               : ElementType::I16);
  value.boolean_value = true;
  value.signed_value = 2150;
  result.attribute = AttributeData{result.path, std::move(value), version};
  return result;
}

// A subscription_report frame of the size the host encodes for a
// LocalTemperature report, numbered by `sequence`.
std::string report_frame(std::uint64_t sequence) {
  return std::string(R"({"version":1,"event":"subscription_report","session_generation":")") +
      kSessionGeneration + R"(","subscription_id":")" + kSubscriptionId +
      R"(","generation":1,"report_sequence":)" + std::to_string(sequence) +
      R"(,"kind":"attribute","value":{"tag":"anonymous","type":"i16","value":2150},)"
      R"("metadata":{"path":{"fabric_id":1,"node_id":4660,"endpoint":1,"cluster":513,)"
      R"("member":0},"initial":false,"report_id":7,"min_interval_s":1,)"
      R"("max_interval_s":60,"sdk_subscription_id":1,"data_version":4096}})";
}

// The BEAM's side of the credit: every transmitted frame and its cumulative bytes.
struct Receiver {
  std::uint64_t sequence{0};
  std::uint64_t bytes{0};

  bool receive(const std::string &frame) {
    ++sequence;
    bytes += frame.size() + 1;
    return true;
  }
};

// Submits one session window of reports over four streams (the stream credit
// each), then acknowledges the window.
void credited_window(ReportCreditManager &manager, Receiver &receiver,
                     const std::vector<std::string> &streams) {
  for (std::size_t report = 0; report < kSessionCredit; ++report) {
    check(manager.Submit(streams[report % streams.size()], 1, report_frame) ==
              ReportCreditManager::SubmitResult::Transmitted,
          "credited submit");
  }
  check(manager.Acknowledge(receiver.sequence, receiver.bytes), "window acknowledgement");
}

// Submits the stream's queue limit of reports to one stream: the first 16 are
// transmitted and the rest wait; each acknowledgement of the transmitted
// reports lets the next 16 through.
void queued_stream(ReportCreditManager &manager, Receiver &receiver, const std::string &stream) {
  std::size_t transmitted = 0;
  for (std::size_t report = 0; report < kSessionCredit; ++report) {
    const auto result = manager.Submit(stream, 1, report_frame);
    if (result == ReportCreditManager::SubmitResult::Transmitted) ++transmitted;
    check(result ==
              (report < kStreamCredit ? ReportCreditManager::SubmitResult::Transmitted
                                      : ReportCreditManager::SubmitResult::Queued),
          "queued submit");
  }
  while (manager.snapshot().queued > 0) {
    const std::uint64_t before = receiver.sequence;
    check(manager.Acknowledge(receiver.sequence, receiver.bytes), "drain acknowledgement");
    transmitted += receiver.sequence - before;
  }
  check(manager.Acknowledge(receiver.sequence, receiver.bytes), "final acknowledgement");
  check(transmitted == kSessionCredit, "drained reports");
}

// One subscription's reports as the controller assembles them: the initial
// report of all four paths, establishment and activation, then 60 reports of
// one changed path each.
std::size_t assemble(const SubscriptionRequest &request) {
  SubscriptionBuffer buffer(request);
  std::size_t reports = 0;
  buffer.BeginReport();
  for (std::size_t recipe = 0; recipe < 4; ++recipe)
    check(buffer.Add(attribute(recipe, 4096)), "initial report");
  buffer.EndReport();
  check(buffer.Establish(1, 1, 60), "establish");
  buffer.Activate();
  reports += buffer.TakeReady().size();
  for (std::uint32_t change = 0; change < 60; ++change) {
    buffer.BeginReport();
    check(buffer.Add(attribute(change % 4, 4097 + change)), "delta report");
    buffer.EndReport();
    reports += buffer.TakeReady().size();
  }
  return reports;
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.title("report flow").unit("report").warmup(10).minEpochTime(std::chrono::milliseconds(20));

  Receiver window_receiver;
  ReportCreditManager window(kSessionGeneration, [&window_receiver](const std::string &frame) {
    return window_receiver.receive(frame);
  });
  std::vector<std::string> streams;
  for (const char *id : {"00000000000000000000000000000001", "00000000000000000000000000000002",
                         "00000000000000000000000000000003", "00000000000000000000000000000004"}) {
    streams.emplace_back(id);
    check(window.AddStream(streams.back(), 1, 64), "add stream");
  }
  bench.batch(kSessionCredit).run("credit window: 64 reports over 4 streams, one ack", [&] {
    credited_window(window, window_receiver, streams);
  });

  Receiver queue_receiver;
  ReportCreditManager queue(kSessionGeneration, [&queue_receiver](const std::string &frame) {
    return queue_receiver.receive(frame);
  });
  check(queue.AddStream(kSubscriptionId, 1, 64), "add queued stream");
  bench.batch(kSessionCredit).run("stream credit: 64 reports, 48 queued, drained by acks", [&] {
    queued_stream(queue, queue_receiver, kSubscriptionId);
  });

  const SubscriptionRequest request = subscription_request();
  check(valid_subscription_request(request), "subscription request");
  bench.batch(64).run("assemble initial report of 4 paths and 60 changes",
                      [&] { check(assemble(request) == 64, "assembled reports"); });

  // The full path through the host: the backend's report callback, the frame,
  // credit, and the report_ack line every stream-credit window.
  ScriptedBackend backend;
  HostProtocol protocol(backend);
  Receiver host_receiver;
  protocol.SetOutputSink([&host_receiver](const std::string &frame) {
    return frame.find(R"("event":"subscription_report")") == std::string::npos ||
        host_receiver.receive(frame);
  });
  check(protocol.ProcessLine(flow_open_line()).keep_running, "flow_open");
  check(succeeded(protocol.ProcessLine(open_line())), "open");
  const ProcessResult subscribed = protocol.ProcessLine(
      request_line("subscribe",
                   std::string(R"("subscription_id":")") + kSubscriptionId +
                       R"(","kind":"attribute","paths":[{)" + path_members(1, 0x0201, 0x0000) +
                       R"(}],"min_interval_s":1,"max_interval_s":60,)"
                       R"("resubscribe":false,"queue_limit":64)")
          .with_id(2));
  check(succeeded(subscribed) && subscribed.activate_subscription.has_value(), "subscribe");
  check(protocol.ActivateSubscription(kSubscriptionId, 1), "activate");
  check(static_cast<bool>(backend.report_sink), "report sink");

  SubscriptionReport report;
  report.subscription_id = kSubscriptionId;
  report.generation = 1;
  report.kind = SubscriptionKind::Attribute;
  report.result = attribute(0, 4096);
  report.min_interval_s = 1;
  report.max_interval_s = 60;
  report.sdk_subscription_id = 1;
  const std::string ack_head = std::string(R"({"version":1,"event":"report_ack",)"
                                           R"("session_generation":")") +
      kSessionGeneration + R"(","report_sequence":)";
  bench.batch(kStreamCredit).run("host report: 16 callbacks, frames and one report_ack", [&] {
    for (std::size_t index = 0; index < kStreamCredit; ++index) {
      ++report.report_id;
      check(backend.report_sink(report), "report callback");
    }
    const ProcessResult acknowledged = protocol.ProcessLine(
        ack_head + std::to_string(host_receiver.sequence) + R"(,"acknowledged_bytes":)" +
        std::to_string(host_receiver.bytes) + "}");
    check(acknowledged.keep_running && !acknowledged.frame, "report_ack");
  });

  check(protocol.healthy(), "host session");
  return 0;
}
