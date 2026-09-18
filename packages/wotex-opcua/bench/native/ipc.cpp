// SPDX-License-Identifier: Apache-2.0
// Input framing and envelope admission of the OPC UA host (priv/native/ipc.c):
// wop_ipc_feed assembling LF-terminated request lines from whole, chunked and
// coalesced pipe reads, and the closed shape checks applied to a parsed line:
// the request envelope, the credit control and the open parameters.
#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <nanobench.h>

extern "C" {
#include "ipc.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "ipc: " << what << " failed\n";
  std::exit(1);
}

// The request envelope the BEAM host writes (Wotex.OPCUA.Native.Frame).
std::string request(const std::string &id, const std::string &operation,
                    const std::string &parameters) {
  return R"({"version":1,"generation":1,"id":")" + id + R"(","operation":")" + operation +
      R"(","parameters":)" + parameters + R"(,"timeout_ms":5000,"deadline_ms":86400000})" + "\n";
}

std::string read_line(unsigned index) {
  return request("read-" + std::to_string(100000 + index), "read",
                 R"({"node_id":"ns=2;s=plant/line-4/oven-2/temperature","index_range":null})");
}

// A deterministic base64 text of the standard alphabet for `bytes` decoded bytes.
std::string base64(std::size_t bytes) {
  static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string text;
  for (std::size_t i = 0; i < bytes / 3 * 4; ++i) text.push_back(alphabet[(i * 7U) % 64U]);
  if (bytes % 3 == 1) text += "AA==";
  if (bytes % 3 == 2) text += "AAA=";
  return text;
}

std::string envelope(std::size_t bytes) {
  return R"({"type":"bytes","base64":")" + base64(bytes) + R"("})";
}

// Open with the credential sizes of 2048-bit RSA application certificates.
std::string open_line() {
  return request("open-1", "open",
                 R"({"endpoint":"opc.tcp://plc.example:4840",)"
                 R"("security_policy":"http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",)"
                 R"("security_mode":"SignAndEncrypt","client_uri":"urn:example:opcua:client",)"
                 R"("server_uri":"urn:example:opcua:server","certificate":)" +
                     envelope(1024) + R"(,"private_key":)" + envelope(1218) +
                     R"(,"server_certificate":)" + envelope(1024) + R"(,"trust_certificate":)" +
                     envelope(812) + R"(,"crl":)" + envelope(461) +
                     R"(,"authentication":{"type":"anonymous"},"session_timeout_ms":60000})");
}

const char credit_line[] = R"({"version":1,"generation":1,"event":"credit","sequence":2,)"
                           R"("messages":1,"bytes":212})"
                           "\n";

// Feeds `bytes` in reads of at most `chunk` bytes and returns the completed lines.
std::size_t frame_lines(WopIpcInput *input, const std::string &bytes, std::size_t chunk) {
  std::size_t lines = 0;
  for (std::size_t offset = 0; offset < bytes.size();) {
    const std::size_t size = std::min(chunk, bytes.size() - offset);
    std::size_t used = 0;
    while (used < size) {
      std::size_t consumed = 0;
      const WopIpcFrameStatus status = wop_ipc_feed(input, bytes.data() + offset + used,
                                                    size - used, &consumed);
      used += consumed;
      if (status == WOP_IPC_FRAME) {
        ++lines;
        input->used = 0;
      } else {
        check(status == WOP_IPC_MORE && used == size, "wop_ipc_feed");
      }
    }
    offset += size;
  }
  return lines;
}

// A parsed line that keeps its pool.
struct Parsed {
  std::unique_ptr<unsigned char[]> pool{new unsigned char[WOP_JSON_POOL_BYTES]};
  WopJson json{};

  explicit Parsed(const std::string &line) {
    check(wop_json_read(line.data(), line.size(), pool.get(), WOP_JSON_POOL_BYTES, &json) ==
              WOP_JSON_OK,
          "wop_json_read");
  }
  ~Parsed() { wop_json_clear(&json); }
  Parsed(const Parsed &) = delete;
  Parsed &operator=(const Parsed &) = delete;
  Parsed(Parsed &&) = delete;
  Parsed &operator=(Parsed &&) = delete;

  yyjson_val *root() const { return yyjson_doc_get_root(json.document); }
};

} // namespace

int main() {
  auto input = std::make_unique<WopIpcInput>();
  const std::string read = read_line(0);
  std::string coalesced;
  for (unsigned i = 0; i < 16; ++i) coalesced += read_line(i);
  std::string values;
  for (unsigned i = 0; i < 1024; ++i) values += (i ? ",21.625" : "21.625");
  const std::string write = request("write-1", "write",
                                    R"({"node_id":"ns=2;s=plant/line-4/oven-2/profile",)"
                                    R"("index_range":null,"value":{"type":"Double",)"
                                    R"("array":true,"value":[)" +
                                        values + "]}}");
  const std::string open = open_line();

  ankerl::nanobench::Bench framing;
  framing.title("wop_ipc_feed").unit("line").warmup(100).minEpochTime(std::chrono::milliseconds(20));
  framing.run("read request, " + std::to_string(read.size()) + " B in one read", [&] {
    input->used = 0;
    check(frame_lines(input.get(), read, read.size()) == 1, "one line");
  });
  framing.run("read request in 64-byte reads", [&] {
    input->used = 0;
    check(frame_lines(input.get(), read, 64) == 1, "one chunked line");
  });
  framing.batch(16).run("16 coalesced read requests in one read", [&] {
    input->used = 0;
    check(frame_lines(input.get(), coalesced, coalesced.size()) == 16, "16 lines");
  });
  framing.batch(1).run(
      "write request, 1024 Doubles, " + std::to_string(write.size()) + " B in one read", [&] {
    input->used = 0;
    check(frame_lines(input.get(), write, write.size()) == 1, "write line");
  });

  const Parsed request_document(read);
  const Parsed credit_document(credit_line);
  const Parsed open_document(open);
  yyjson_val *parameters = yyjson_obj_get(open_document.root(), "parameters");

  ankerl::nanobench::Bench admission;
  admission.title("envelope admission")
      .unit("check")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));
  admission.run("wop_ipc_request, read envelope", [&] {
    WopIpcRequest parsed;
    check(wop_ipc_request(request_document.root(), &parsed) && parsed.generation == 1 &&
              parsed.timeout_ms == 5000,
          "wop_ipc_request");
  });
  admission.run("wop_ipc_credit, credit control", [&] {
    WopIpcCredit credit;
    check(wop_ipc_credit(credit_document.root(), &credit) && credit.sequence == 2 &&
              credit.bytes == 212,
          "wop_ipc_credit");
  });
  admission.run("wop_ipc_open, 2048-bit RSA credential envelopes",
                [&] { check(wop_ipc_open(parameters), "wop_ipc_open"); });
  return 0;
}
