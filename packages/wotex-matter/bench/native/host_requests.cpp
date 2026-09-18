// SPDX-License-Identifier: Apache-2.0
// Request dispatch of the Matter controller host (native/src/protocol.cpp):
// HostProtocol::ProcessLine takes one request line from the BEAM, parses it
// under the frame bounds, validates the envelope, the request id order and the
// parameters, calls the controller backend and encodes the reply frame. The
// scripted backend (scripted_backend.hpp) answers each interaction with the
// values a node returns, so the rows measure the host's own JSON and TLV
// handling around the SDK. Each operation is one request.
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <utility>

#include <nanobench.h>

#include "scripted_backend.hpp"
#include "wotex_matter/protocol.hpp"

namespace {

using namespace wotex::matter;
using namespace wotex::matter::bench;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "host_requests: " << what << " failed\n";
  std::exit(1);
}

std::string subjects(std::uint64_t first) {
  std::string list;
  for (std::uint64_t subject = first; subject < first + 4; ++subject) {
    if (!list.empty()) list += ',';
    list += R"({"tag":"anonymous","type":"u64","value":)" + std::to_string(subject) + "}";
  }
  return list;
}

// An Access Control List of four entries with four subjects and two targets each.
std::string access_control_list() {
  std::string entries;
  for (std::uint64_t entry = 0; entry < 4; ++entry) {
    if (!entries.empty()) entries += ',';
    entries += R"({"tag":"anonymous","type":"structure","value":[)"
               R"({"tag":["context",1],"type":"u8","value":)" +
        std::to_string(entry == 0 ? 5 : 3) +
        R"(},{"tag":["context",2],"type":"u8","value":2},)"
        R"({"tag":["context",3],"type":"array","value":[)" +
        subjects(0x770000 + (entry * 4)) + R"(]},{"tag":["context",4],"type":"array","value":[)";
    for (const std::uint32_t cluster : {0x0006U, 0x0201U}) {
      if (cluster != 0x0006U) entries += ',';
      entries += R"({"tag":"anonymous","type":"structure","value":[)"
                 R"({"tag":["context",0],"type":"u32","value":)" +
          std::to_string(cluster) +
          R"(},{"tag":["context",1],"type":"u16","value":1},)"
          R"({"tag":["context",2],"type":"null","value":null}]})";
    }
    entries += "]}]}";
  }
  return R"({"tag":"anonymous","type":"array","value":[)" + entries + "]}";
}

} // namespace

int main() {
  ScriptedBackend backend;
  HostProtocol protocol(backend);
  check(protocol.ProcessLine(flow_open_line()).keep_running, "flow_open");
  check(succeeded(protocol.ProcessLine(open_line())), "open");

  std::string descriptor_paths;
  for (std::uint16_t endpoint = 0; endpoint < kEndpoints; ++endpoint) {
    for (std::uint32_t member = 0; member < 4; ++member) {
      if (!descriptor_paths.empty()) descriptor_paths += ',';
      descriptor_paths += "{" + path_members(endpoint, 0x001D, member) + "}";
    }
  }

  const std::pair<const char *, RequestLine> requests[] = {
      {"health", request_line("health", "")},
      {"read OnOff", request_line("read", path_members(1, 0x0006, 0x0000))},
      {"read_paths Descriptor 4 endpoints x 4 attributes",
       request_line("read_paths", R"("paths":[)" + descriptor_paths + "]")},
      {"write Thermostat setpoint",
       request_line("write",
                    path_members(1, 0x0201, 0x0012) +
                        R"(,"value":{"tag":"anonymous","type":"i16","value":2150})")},
      {"write ACL 4 entries x 4 subjects",
       request_line("write",
                    path_members(0, 0x001F, 0x0000) + R"(,"value":)" + access_control_list())},
      {"invoke OnOff Toggle",
       request_line("invoke",
                    path_members(1, 0x0006, 0x0002) +
                        R"(,"value":{"tag":"anonymous","type":"structure","value":[]})")},
  };

  ankerl::nanobench::Bench bench;
  bench.title("host request")
      .unit("request")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  std::uint64_t id = 1;
  for (const auto &entry : requests) {
    const RequestLine &line = entry.second;
    bench.run(entry.first,
              [&] { check(succeeded(protocol.ProcessLine(line.with_id(++id))), entry.first); });
  }

  check(backend.interactions > 0 && protocol.healthy(), "session");
  return 0;
}
