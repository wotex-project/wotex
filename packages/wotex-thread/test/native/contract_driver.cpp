// Native contract driver. It receives corpus inputs only and prints observed
// results from the shared production parser and report-flow code; ExUnit owns
// every expected projection.
#include "flow.hpp"
#include "protocol.hpp"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <string>

using namespace wotex::thread;

namespace {
constexpr std::size_t kMaximumCommands = 1024;

bool unsigned_value(const Json &value, std::uint64_t maximum) {
  return value.is_number_unsigned() && value.get<std::uint64_t>() <= maximum;
}

bool exact(const Json &value, const std::set<std::string> &keys) {
  return exact_keys(value, keys);
}

// Trace reports are JSON lines padded to the exact requested encoded length,
// including the newline, for the assigned sequence.
ReportFlow::Encoder trace_report(const std::string &stream, std::size_t bytes) {
  return [stream, bytes](std::uint64_t sequence) {
    Json report = {{"event", "trace_report"}, {"stream", stream}, {"report_sequence", sequence}, {"body", ""}};
    const std::size_t prefix = report.dump().size() + 1;
    if (prefix > bytes) return std::string();
    report["body"] = std::string(bytes - prefix, 'x');
    return report.dump();
  };
}

bool admit_transmit(ReportFlow &flow, const Json &event, std::size_t queue_limit, bool repeated_allowed,
                    std::size_t &count) {
  const bool repeated = event.contains("count");
  if ((repeated && !repeated_allowed) || !exact(event, repeated ? std::set<std::string>{"event", "stream", "bytes", "count"}
                                                                : std::set<std::string>{"event", "stream", "bytes"}) ||
      !event.at("stream").is_string() || !unsigned_value(event.at("bytes"), kMaximumReportLine) ||
      (repeated && (!unsigned_value(event.at("count"), 10000) || event.at("count") == 0))) return false;
  const std::string stream = event.at("stream").get<std::string>();
  count = repeated ? event.at("count").get<std::size_t>() : 1;
  return flow.live(stream, 1) || flow.add_stream(stream, 1, queue_limit);
}

std::optional<std::pair<std::string, std::size_t>> configuration(const Json &input, bool events) {
  if (!exact(input, events ? std::set<std::string>{"session_generation", "queue_limit", "events"}
                           : std::set<std::string>{"session_generation", "queue_limit"}) ||
      !input.at("session_generation").is_string() ||
      !session_generation(input.at("session_generation").get<std::string>()) ||
      !unsigned_value(input.at("queue_limit"), kMaximumQueueLimit) || input.at("queue_limit") == 0 ||
      (events && (!input.at("events").is_array() || input.at("events").size() > kMaximumCommands))) {
    return std::nullopt;
  }
  return std::make_pair(input.at("session_generation").get<std::string>(), input.at("queue_limit").get<std::size_t>());
}

Json projection(const ReportFlow &flow, std::size_t transmitted, const Json &terminal) {
  const auto snapshot = flow.snapshot();
  return {{"transmitted", transmitted}, {"queued", snapshot.queued}, {"terminal", terminal},
          {"frame_credit", snapshot.frame_credit}, {"byte_credit", snapshot.byte_credit}};
}

bool acknowledge(ReportFlow &flow, const Json &event) {
  return exact(event, {"event", "session_generation", "report_sequence", "acknowledged_bytes"}) &&
         event.at("session_generation").is_string() && unsigned_value(event.at("report_sequence"), UINT64_MAX) &&
         unsigned_value(event.at("acknowledged_bytes"), UINT64_MAX) &&
         flow.acknowledge(event.at("session_generation").get<std::string>(),
                          event.at("report_sequence").get<std::uint64_t>(),
                          event.at("acknowledged_bytes").get<std::uint64_t>());
}

int flow_trace(const Json &input) {
  const auto config = configuration(input, true);
  if (!config) return 2;
  std::size_t transmitted = 0;
  auto write = [&transmitted](const std::string &frame) {
    std::cout << frame << '\n';
    ++transmitted;
    return static_cast<bool>(std::cout);
  };
  ReportFlow flow(config->first, write, [](const std::string &) { return false; });
  Json terminal = nullptr;
  for (const Json &event : input.at("events")) {
    if (!event.is_object() || !event.contains("event") || !event.at("event").is_string()) return 2;
    if (event.at("event") == "transmit") {
      std::size_t count = 0;
      if (!admit_transmit(flow, event, config->second, true, count)) return 2;
      const auto encode = trace_report(event.at("stream").get<std::string>(), event.at("bytes").get<std::size_t>());
      for (std::size_t index = 0; index < count; ++index) {
        const auto result = flow.submit(event.at("stream").get<std::string>(), 1, encode);
        if (result == ReportFlow::Submission::failed) return 2;
        if (result == ReportFlow::Submission::overflow) { terminal = "queue_overflow"; break; }
      }
    } else if (event.at("event") == "ack") {
      if (!acknowledge(flow, event)) terminal = "invalid_frame";
    } else {
      return 2;
    }
    if (!terminal.is_null()) break;
  }
  std::cout << projection(flow, transmitted, terminal).dump() << '\n';
  return std::cout ? 0 : 2;
}

// Interactive trace: every command line yields its emitted frames followed by one
// snapshot, so ExUnit can register reports in the production BEAM ledger and
// send the acknowledgements that ledger proposes.
int flow_session(const Json &input) {
  const auto config = configuration(input, false);
  if (!config) return 2;
  std::size_t transmitted = 0;
  auto emit = [](const std::string &frame) {
    std::cout << frame << '\n';
    return static_cast<bool>(std::cout);
  };
  ReportFlow flow(config->first, [&](const std::string &frame) { ++transmitted; return emit(frame); }, emit);
  Json terminal = nullptr;
  std::string line;
  for (std::size_t commands = 0; commands < kMaximumCommands && std::getline(std::cin, line); ++commands) {
    Json event;
    try { event = parse_line(line + "\n"); } catch (const ProtocolError &) { return 2; }
    if (!event.is_object() || !event.contains("event") || !event.at("event").is_string()) return 2;
    const bool close = exact(event, {"event"}) && event.at("event") == "close";
    if (close) {
      // The final snapshot precedes cooperative exit and sanitizer teardown.
    } else if (!terminal.is_null()) {
      return 2;
    } else if (event.at("event") == "transmit") {
      std::size_t count = 0;
      if (!admit_transmit(flow, event, config->second, false, count)) return 2;
      const auto result = flow.submit(event.at("stream").get<std::string>(), 1,
                                      trace_report(event.at("stream").get<std::string>(), event.at("bytes").get<std::size_t>()));
      if (result == ReportFlow::Submission::failed) return 2;
      if (result == ReportFlow::Submission::overflow) terminal = "queue_overflow";
    } else if (event.at("event") == "retire") {
      if (!exact(event, {"event", "stream", "last_report_sequence"}) || !event.at("stream").is_string() ||
          !unsigned_value(event.at("last_report_sequence"), UINT64_MAX)) return 2;
      // The supplied barrier sequence may be deliberately false. The production
      // BEAM ledger, not this driver, decides whether that barrier is valid.
      const Json barrier = {{"event", "trace_retired"}, {"stream", event.at("stream")},
                            {"last_report_sequence", event.at("last_report_sequence")}};
      if (!flow.retire(event.at("stream").get<std::string>(), 1,
                       [&barrier](std::uint64_t) { return barrier.dump(); })) return 2;
    } else if (event.at("event") == "ack") {
      if (!acknowledge(flow, event)) terminal = "invalid_frame";
    } else {
      return 2;
    }
    Json snapshot = projection(flow, transmitted, terminal);
    snapshot["event"] = "trace_snapshot";
    std::cout << snapshot.dump() << '\n' << std::flush;
    if (!std::cout) return 2;
    if (close) return 0;
  }
  return 2;
}
}  // namespace

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  const std::string operation(argv[1]);
  std::ifstream file(argv[2], std::ios::binary);
  if (!file) return 2;
  std::string bytes;
  char byte = 0;
  while (bytes.size() <= kMaximumLine && file.get(byte)) bytes.push_back(byte);
  if (operation == "parse_request") {
    bool accepted = false;
    try {
      (void)request(parse_line(bytes));
      accepted = true;
    } catch (const ProtocolError &) {}
    std::cout << (accepted ? "{\"accepted\":true}\n" : "{\"accepted\":false}\n");
    return std::cout ? 0 : 2;
  }
  if (operation != "flow_trace" && operation != "flow_session") return 2;
  try {
    const Json input = parse_line(bytes);
    return operation == "flow_trace" ? flow_trace(input) : flow_session(input);
  } catch (const ProtocolError &) {
    return 2;
  }
}
