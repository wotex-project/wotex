// SPDX-License-Identifier: Apache-2.0
// The bridge frames of the Thread host (priv/openthread/protocol.hpp): bounded
// parsing of the owner's request and flow-control lines with their exact
// envelope checks, rejection of a duplicate key, the parser's node and line
// limits, and encoding of the host's ready, success and failure frames. Each
// operation is one frame.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <utility>

#include <nanobench.h>

#include "protocol.hpp"

namespace {

using namespace wotex::thread;

const char *const kSession = "0123456789abcdef0123456789abcdef";
// The active Operational Dataset of the package's contract fixture
// (priv/fixtures/contract-v1.json), 80 TLV bytes in base64.
const char *const kDataset = "AAMAAA8BAhI0AggAESIzRFVmdwMHZml4dHVyZQUQAAECAwQFBgcICQoLDA0ODwcI/"
                             "REiM0RVZncMBAKg9/gOCAAAAAAAAQAANQYABAAf/+A=";

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "protocol_frames: " << what << " failed\n";
  std::exit(1);
}

// One LF-terminated line, as the owner writes it.
std::string line(const Json &frame) { return frame.dump() + "\n"; }

Json request_frame(const char *operation, Json parameters) {
  return {{"version", 1},
          {"id", "17"},
          {"operation", operation},
          {"parameters", std::move(parameters)},
          {"timeout_ms", 5000}};
}

// A line of exactly kMaximumNodes JSON values: an array of four arrays whose
// elements fill the aggregate node limit.
std::string node_limit_line() {
  std::string text = "[";
  std::size_t elements = kMaximumNodes - 5;
  for (std::size_t array = 0; array < 4; ++array) {
    const std::size_t count = array < 3 ? kMaximumCollection : elements;
    elements -= count;
    text += array == 0 ? "[" : ",[";
    for (std::size_t index = 0; index < count; ++index) text += index == 0 ? "0" : ",0";
    text += ']';
  }
  return text + "]\n";
}

bool rejected(const std::string &bytes) {
  try {
    (void)parse_line(bytes);
  } catch (const ProtocolError &) {
    return true;
  }
  return false;
}

std::string sized(const char *name, const std::string &bytes) {
  return std::string(name) + ", " + std::to_string(bytes.size()) + " B";
}

void inbound(ankerl::nanobench::Bench &bench) {
  bench.title("inbound frames").unit("frame").batch(1);

  const std::string inspect = line(request_frame("inspect", Json::object()));
  bench.run(sized("inspect request", inspect), [&] {
    const Request value = request(parse_line(inspect));
    check(value.operation == "inspect" && value.parameters.empty(), "inspect request");
  });

  const std::string subscribe = line(request_frame("subscribe_state", {{"queue_limit", 64}}));
  bench.run(sized("subscribe_state request", subscribe), [&] {
    const Request value = request(parse_line(subscribe));
    check(value.operation == "subscribe_state" && value.parameters.at("queue_limit") == 64,
          "subscribe_state request");
  });

  const std::string management = line(request_frame(
      "management_active_set", {{"dataset", {{"type", "bytes"}, {"base64", kDataset}}}}));
  bench.run(sized("management_active_set request", management), [&] {
    const Request value = request(parse_line(management));
    check(value.operation == "management_active_set" &&
              value.parameters.at("dataset").at("base64") == kDataset,
          "management_active_set request");
  });

  const std::string open = line(
      {{"version", 1}, {"event", "flow_open"}, {"session_generation", kSession}});
  bench.run(sized("flow_open control", open), [&] {
    const FlowControl frame = flow_control(parse_line(open));
    check(frame.kind == FlowControl::Kind::flow_open && frame.session_generation == kSession,
          "flow_open control");
  });

  const std::string acknowledgement = line({{"version", 1},
                                            {"event", "report_ack"},
                                            {"session_generation", kSession},
                                            {"report_sequence", 64},
                                            {"acknowledged_bytes", 64 * 212}});
  bench.run(sized("report_ack control", acknowledgement), [&] {
    const FlowControl frame = flow_control(parse_line(acknowledgement));
    check(frame.kind == FlowControl::Kind::report_ack && frame.report_sequence == 64 &&
              frame.acknowledged_bytes == 64 * 212,
          "report_ack control");
  });

  // The rejected duplicate-key request of the native-port corpus (WTH-B-F02).
  const std::string duplicate = "{\"version\":1,\"id\":\"1\",\"id\":\"2\",\"operation\":\"health\","
                                "\"parameters\":{},\"timeout_ms\":1000}\n";
  bench.run(sized("duplicate key rejected", duplicate),
            [&] { check(rejected(duplicate), "duplicate key rejection"); });

  const std::string nodes = node_limit_line();
  bench.run(sized("4096 values, node limit", nodes), [&] {
    const Json value = parse_line(nodes);
    check(value.size() == 4 && value.back().size() == kMaximumCollection - 5, "node limit");
  });

  const std::string longest = "\"" + std::string(kMaximumLine - 3, 'x') + "\"\n";
  bench.run(sized("string, line limit", longest), [&] {
    const Json value = parse_line(longest);
    check(value.is_string() && value.get_ref<const std::string &>().size() == kMaximumLine - 3,
          "line limit");
  });
}

void outbound(ankerl::nanobench::Bench &bench) {
  bench.title("outbound frames").unit("frame").batch(1);
  const Request command{"17", "inspect", Json::object(), 5000};
  const Json state = {{"role", "router"},     {"network_name", "fixture"}, {"rloc16", 1024},
                      {"ipv6_enabled", true}, {"thread_enabled", true},    {"generation", 1}};

  const std::size_t ready_bytes = ready().dump().size();
  bench.run("ready, " + std::to_string(ready_bytes) + " B", [&] {
    const std::string frame = ready().dump();
    check(frame.size() == ready_bytes, "ready");
    ankerl::nanobench::doNotOptimizeAway(frame);
  });

  const std::size_t success_bytes = success(command, state).dump().size();
  bench.run("success with a State snapshot, " + std::to_string(success_bytes) + " B", [&] {
    const std::string frame = success(command, state).dump();
    check(frame.size() == success_bytes, "success");
    ankerl::nanobench::doNotOptimizeAway(frame);
  });

  const std::size_t failure_bytes = failure(command, "busy").dump().size();
  bench.run("failure with an error code, " + std::to_string(failure_bytes) + " B", [&] {
    const std::string frame = failure(command, "busy").dump();
    check(frame.size() == failure_bytes, "failure");
    ankerl::nanobench::doNotOptimizeAway(frame);
  });
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.warmup(100).minEpochTime(std::chrono::milliseconds(20));
  inbound(bench);
  outbound(bench);
  return 0;
}
