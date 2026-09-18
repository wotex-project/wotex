// SPDX-License-Identifier: Apache-2.0
// The command input path of the native OSCORE helper, as the worker's consume()
// runs it for every line from its owner: LF framing (native/oscore/frame.c),
// bounded JSON parsing into the fixed parser pool (json.c), command decoding
// with its per-operation allowlists (command.c, with body.c for byte values),
// then command and pool erasure. Each operation is one command line.
#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <nanobench.h>

extern "C" {
#include "command.h"
#include "frame.h"
#include "json.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "oscore_command: " << what << " failed\n";
  std::exit(1);
}

// The worker's per-line callback, with the operation recorded instead of executed.
struct Input {
  wco_json *json = nullptr;
  std::size_t delivered = 0;
  wco_operation last = WCO_CLOSE;
};

int consume(const char *line, std::size_t length, void *argument) {
  auto *input = static_cast<Input *>(argument);
  wco_command command{};
  const int valid = wco_json_parse(input->json, line, length) == WCO_JSON_OK &&
      wco_command_decode(input->json, &command);
  if (valid) {
    input->last = command.operation;
    ++input->delivered;
  }
  wco_command_clear(&command);
  wco_json_reset(input->json);
  return valid;
}

// Canonical padded base64 of `size` pattern bytes.
std::string base64(std::size_t size) {
  static const char digits[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::vector<unsigned char> bytes(size);
  for (std::size_t index = 0; index < size; ++index)
    bytes[index] = static_cast<unsigned char>((index * 31U + 7U) & 0xffU);
  std::string encoded;
  encoded.reserve(4 * ((size + 2) / 3));
  for (std::size_t offset = 0; offset < size; offset += 3) {
    const std::size_t left = size - offset;
    const unsigned value = (bytes[offset] << 16U) | (left > 1 ? bytes[offset + 1] << 8U : 0U) |
        (left > 2 ? bytes[offset + 2] : 0U);
    encoded += digits[(value >> 18U) & 63U];
    encoded += digits[(value >> 12U) & 63U];
    encoded += left > 1 ? digits[(value >> 6U) & 63U] : '=';
    encoded += left > 2 ? digits[value & 63U] : '=';
  }
  return encoded;
}

std::string line(const std::string &id, const std::string &operation,
                 const std::string &parameters) {
  return R"({"id":")" + id + R"(","operation":")" + operation + R"(","parameters":)" + parameters +
      R"(,"timeout_ms":5000,"version":1})" + "\n";
}

std::string bytes(const std::string &encoded) {
  return R"({"base64":")" + encoded + R"(","type":"bytes"})";
}

struct Case {
  const char *name;
  std::string line;
  wco_operation operation;
};

// One command of each operation, shaped as the Elixir owner encodes them.
std::vector<Case> cases() {
  const std::string path = R"("path":"/things/example/properties/temperature")";
  const std::string security =
      R"({"context_store":"/srv/example/oscore/context","id_context":null,"master_salt":)" +
      bytes("nnypIiN4Y0A=") + R"(,"master_secret":)" + bytes("AQIDBAUGBwgJCgsMDQ4PEA==") +
      R"(,"mode":"oscore","recipient_id":)" + bytes("AQ==") + R"(,"sender_id":)" + bytes("") + "}";
  const std::string hash(64, 'a');
  return {
      {"open with OSCORE credentials",
       line("1", "open",
            R"({"generation":1,"host":"192.0.2.10","port":5683,"security":)" + security + "}"),
       WCO_OPEN},
      {"request GET",
       line("2", "request", R"({"accept":50,"confirmable":true,"method":"GET",)" + path + "}"),
       WCO_REQUEST},
      {"request PUT with body",
       line(
           "3", "request",
           R"({"body_id":"4","confirmable":true,"content_format":50,"method":"PUT",)" + path + "}"),
       WCO_REQUEST},
      {"body_begin",
       line("4", "body_begin", R"({"body_id":"4","length":32768,"sha256":")" + hash + R"("})"),
       WCO_BODY_BEGIN},
      {"body_chunk 1 KiB",
       line("5", "body_chunk",
            R"({"body_id":"4","data":)" + bytes(base64(1024)) + R"(,"offset":0})"),
       WCO_BODY_CHUNK},
      {"body_chunk 32 KiB",
       line("6", "body_chunk",
            R"({"body_id":"4","data":)" + bytes(base64(32768)) + R"(,"offset":0})"),
       WCO_BODY_CHUNK},
      {"body_end", line("7", "body_end", R"({"body_id":"4"})"), WCO_BODY_END},
      {"observe",
       line("8", "observe",
            R"({"accept":50,"confirmable":true,"observation_kind":"property",)" + path +
                R"(,"renew":true})"),
       WCO_OBSERVE},
      {"credit", line("9", "credit", R"({"ack_seq":8,"generation":1})"), WCO_CREDIT},
      {"cancel", line("10", "cancel", R"({"generation":1,"subscription_id":"8"})"), WCO_CANCEL},
      {"close", line("11", "close", "{}"), WCO_CLOSE},
  };
}

} // namespace

int main() {
  Input input;
  input.json = wco_json_new();
  check(input.json != nullptr, "wco_json_new");
  auto frame = std::make_unique<wco_frame>();
  wco_frame_init(frame.get());

  ankerl::nanobench::Bench bench;
  bench.title("command line").unit("line").warmup(10).minEpochTime(std::chrono::milliseconds(20));

  for (const Case &entry : cases()) {
    bench.run(entry.name, [&] {
      const std::size_t delivered = input.delivered;
      check(wco_frame_feed(frame.get(), entry.line.data(), entry.line.size(), consume, &input) == 1,
            entry.name);
      check(input.delivered == delivered + 1 && input.last == entry.operation, entry.name);
    });
  }

  // Sixteen coalesced request and credit lines arriving in 4 KiB reads.
  std::string stream;
  for (int index = 0; index < 8; ++index) {
    stream += line(
        std::to_string(100 + 2 * index), "request",
        R"({"accept":50,"confirmable":true,"method":"GET","path":"/things/example/properties/p)" +
            std::to_string(index) + R"("})");
    stream += line(std::to_string(101 + 2 * index), "credit",
                   R"({"ack_seq":)" + std::to_string(index) + R"(,"generation":1})");
  }
  bench.batch(16).run("16 coalesced lines in 4 KiB reads", [&] {
    const std::size_t delivered = input.delivered;
    for (std::size_t offset = 0; offset < stream.size(); offset += 4096) {
      const std::size_t length = std::min<std::size_t>(4096, stream.size() - offset);
      check(wco_frame_feed(frame.get(), stream.data() + offset, length, consume, &input) == 1,
            "coalesced stream");
    }
    check(input.delivered == delivered + 16, "coalesced stream");
  });

  // A duplicate member fails closed; the worker then ends the generation, so
  // this parses and erases directly instead of poisoning the shared frame.
  const std::string duplicate =
      R"({"id":"12","id":"13","operation":"close","parameters":{},"timeout_ms":5000,"version":1})"
      "\n";
  bench.batch(1).run("reject a duplicate member", [&] {
    check(wco_json_parse(input.json, duplicate.data(), duplicate.size()) == WCO_JSON_DUPLICATE,
          "duplicate rejection");
    wco_json_reset(input.json);
  });
  bench.run("erase the 2 MiB parser pool", [&] { wco_json_reset(input.json); });

  check(wco_frame_eof(frame.get()) == 1, "clean end of input");
  wco_json_free(input.json);
  return 0;
}
