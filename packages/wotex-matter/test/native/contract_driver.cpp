#include "wotex_matter/protocol.hpp"

#include <charconv>
#include <algorithm>
#include <fstream>
#include <iostream>
#include <string>
#include <nlohmann/json.hpp>

namespace {
using Json = nlohmann::json;
using Credit = wotex::matter::ReportCreditManager;

bool Unsigned(const Json &value, std::uint64_t maximum) {
  return value.is_number_unsigned() && value.get<std::uint64_t>() <= maximum;
}

std::optional<Json> FlowTrace(const std::string &line) {
  if (!wotex::matter::HostProtocol::ParseDocumentAccepted(line)) {
    return std::nullopt;
  }
  const Json input = Json::parse(line);
  if (!input.is_object() || input.size() != 3 ||
      !input.contains("session_generation") || !input["session_generation"].is_string() ||
      !input.contains("queue_limit") || !Unsigned(input["queue_limit"], 10000) ||
      input["queue_limit"] == 0 || !input.contains("events") ||
      !input["events"].is_array() || input["events"].size() > 1024) {
    return std::nullopt;
  }
  const std::string generation = input["session_generation"];
  if (generation.size() != 32 || !std::all_of(generation.begin(), generation.end(),
      [](char byte) { return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f'); })) {
    return std::nullopt;
  }
  std::size_t transmitted = 0;
  Credit flow(generation, [&transmitted](const std::string &frame) {
    std::cout << frame << '\n';
    std::cout.flush();
    if (!std::cout.good()) {
      return false;
    }
    ++transmitted;
    return true;
  });
  Json terminal = nullptr;
  for (const Json &event : input["events"]) {
    if (!event.is_object() || !event.contains("event")) {
      return std::nullopt;
    }
    if (event["event"] == "transmit") {
      const bool repeated = event.contains("count");
      if (event.size() != (repeated ? 4U : 3U) || !event.contains("stream") ||
          !event["stream"].is_string() || !event.contains("bytes") ||
          !Unsigned(event["bytes"], wotex::matter::kMaximumFrameBytes) ||
          event["bytes"].get<std::size_t>() < 2 ||
          (repeated && (!Unsigned(event["count"], 10000) || event["count"] == 0))) {
        return std::nullopt;
      }
      const std::string stream = event["stream"];
      if (stream.empty() || stream.size() > 64 ||
          (!flow.IsLive(stream, 1) && !flow.AddStream(stream, 1, input["queue_limit"]))) {
        return std::nullopt;
      }
      const std::size_t bytes = event["bytes"];
      const std::size_t count = repeated ? event["count"].get<std::size_t>() : 1;
      for (std::size_t index = 0; index < count; ++index) {
        const auto result = flow.Submit(stream, 1, [bytes](std::uint64_t) {
          return std::string(bytes - 1, 'x');
        });
        if (result != Credit::SubmitResult::Transmitted && result != Credit::SubmitResult::Queued) {
          return std::nullopt;
        }
      }
    } else if (event["event"] == "ack") {
      if (event.size() != 4 || !event.contains("session_generation") ||
          !event.contains("report_sequence") || !event.contains("acknowledged_bytes") ||
          !event["report_sequence"].is_number_unsigned() ||
          !event["acknowledged_bytes"].is_number_unsigned()) {
        return std::nullopt;
      }
      if (event["session_generation"] != generation ||
          !flow.Acknowledge(event["report_sequence"], event["acknowledged_bytes"])) {
        terminal = "invalid_frame";
        break;
      }
    } else {
      return std::nullopt;
    }
  }
  const auto snapshot = flow.snapshot();
  return Json{{"transmitted", transmitted}, {"queued", snapshot.queued},
              {"terminal", terminal}, {"frame_credit", snapshot.frame_credit},
              {"byte_credit", snapshot.byte_credit}};
}
} // namespace

// Inputs select shared production validators; expectations stay in ExUnit.
int main(int argc, char **argv) {
  if (argc != 3) {
    return 2;
  }
  const std::string operation(argv[1]);
  if (operation != "parse_request" && operation != "result_budget" && operation != "flow_trace") {
    return 2;
  }
  std::ifstream input(argv[2], std::ios::binary);
  if (!input) {
    return 2;
  }
  std::string line;
  char byte = 0;
  bool complete = false;
  while (input.get(byte)) {
    if (line.size() + 1 > wotex::matter::kMaximumFrameBytes) {
      break;
    }
    if (byte == '\n') {
      complete = input.peek() == std::char_traits<char>::eof();
      break;
    }
    line.push_back(byte);
  }
  if (operation == "parse_request") {
    const bool accepted = complete &&
        wotex::matter::HostProtocol::ParseRequestAccepted(line);
    std::cout << (accepted ? "{\"accepted\":true}\n" : "{\"accepted\":false}\n");
  } else if (operation == "flow_trace") {
    const auto result = complete ? FlowTrace(line) : std::nullopt;
    if (!result.has_value()) {
      return 2;
    }
    std::cout << result->dump() << '\n';
  } else {
    std::size_t bytes = 0;
    const auto parsed = std::from_chars(line.data(), line.data() + line.size(), bytes);
    if (!complete || parsed.ec != std::errc{} || parsed.ptr != line.data() + line.size()) {
      return 2;
    }
    const bool accepted = wotex::matter::valid_encoded_result_size(bytes);
    std::cout << (accepted ? "{\"accepted\":true}\n"
                          : "{\"accepted\":false,\"code\":\"response_limit\"}\n");
  }
  return 0;
}
