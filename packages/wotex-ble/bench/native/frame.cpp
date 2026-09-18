// SPDX-License-Identifier: Apache-2.0
// Protocol-v1 framing of the BLE native host (priv/bluez/native/frame.hpp):
// bounded parsing of one request line (health, read, a write carrying a
// 512-byte value, and a line of the 131,072-byte maximum), rejection of an
// array beyond the 1,024-entry bound, and the host's admission path for
// pipelined requests: 8 KiB reads through the incremental line decoder, the
// bounded parse and the dispatch-sequence check. Each operation is one line.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <string_view>
#include <utility>
#include <nanobench.h>

#include "bytes.hpp"
#include "frame.hpp"

namespace {
using wotex::ble::AttributeBytes;
using wotex::ble::InvalidFrame;
using wotex::ble::Json;
using wotex::ble::Lines;
using wotex::ble::max_line;
using wotex::ble::Sequence;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "frame: " << what << " failed\n";
  std::exit(1);
}

// A characteristic address of a validated discovery snapshot.
Json address() {
  return {{"service", "0000181a-0000-1000-8000-00805f9b34fb"},
          {"characteristic", "00002a6e-0000-1000-8000-00805f9b34fb"},
          {"object_path", "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service000e/char000f"},
          {"handle", 15},
          {"generation", 3}};
}

std::string request(const std::string &id, const std::string &operation, Json parameters) {
  return Json{{"version", 1},
              {"id", id},
              {"operation", operation},
              {"parameters", std::move(parameters)},
              {"timeout_ms", 5000}}
             .dump() +
      "\n";
}

std::string labelled(const std::string &name, const std::string &line) {
  return name + " (" + std::to_string(line.size()) + " B)";
}

// `open`, then `count - 1` read requests with increasing IDs.
std::string pipelined(std::size_t count) {
  std::string bytes = request("open", "open", Json::object());
  for (std::size_t id = 1; id < count; ++id)
    bytes += request(std::to_string(id), "read", {{"address", address()}});
  return bytes;
}

// The host's read loop: 8 KiB reads, each complete line parsed and admitted.
std::size_t admit(std::string_view bytes) {
  Sequence sequence;
  Lines lines;
  std::size_t admitted = 0;
  for (std::size_t offset = 0; offset < bytes.size(); offset += 8192) {
    lines.feed(bytes.substr(offset, 8192), [&](std::string_view line) {
      if (sequence.accept(wotex::ble::parse_line(line))) ++admitted;
    });
  }
  lines.eof();
  return admitted;
}

bool rejected(const std::string &line) {
  try {
    wotex::ble::parse_line(line);
  } catch (const InvalidFrame &) {
    return true;
  }
  return false;
}

} // namespace

int main() {
  const std::string value(512, '\x5a');
  const std::string health = request("1", "health", Json::object());
  const std::string read = request("42", "read", {{"address", address()}});
  const std::string write = request(
      "43", "write",
      {{"address", address()}, {"value", AttributeBytes::from_bytes(value).envelope()}});
  const std::string maximal = "\"" + std::string(max_line - 3, 'a') + "\"\n";
  Json wide = Json::array();
  for (int i = 0; i < 1025; ++i) wide.push_back(i);
  const std::string over_bound = wide.dump() + "\n";
  constexpr std::size_t count = 256;
  const std::string requests = pipelined(count);

  for (const std::string *line : {&health, &read, &write})
    check(wotex::ble::request(wotex::ble::parse_line(*line)), "request shape");
  check(maximal.size() == max_line && wotex::ble::parse_line(maximal).is_string(), "maximal line");
  check(rejected(over_bound), "entry bound");
  check(admit(requests) == count, "pipelined admission");

  ankerl::nanobench::Bench bench;
  bench.title("protocol-v1 framing")
      .unit("line")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  for (const auto &row :
       {std::pair<const char *, const std::string *>{"parse health request", &health},
        {"parse read request", &read},
        {"parse write request, 512 B value", &write},
        {"parse maximal string line", &maximal}}) {
    const std::string &line = *row.second;
    bench.run(labelled(row.first, line), [&] {
      const Json parsed = wotex::ble::parse_line(line);
      check(!parsed.is_null(), "parse");
      ankerl::nanobench::doNotOptimizeAway(parsed);
    });
  }
  bench.run(labelled("reject 1,025-entry array", over_bound),
            [&] { check(rejected(over_bound), "rejection"); });
  bench.batch(count).run("admit 256 pipelined requests from 8 KiB reads",
                         [&] { check(admit(requests) == count, "admission"); });
  return 0;
}
