// SPDX-License-Identifier: Apache-2.0
// The strict JSON reader of the OPC UA host (priv/native/json_codec.c over the
// vendored yyjson 0.12.0): wop_json_read, which parses one LF-terminated frame
// into a caller-owned 2 MiB pool and validates its depth, node, container and
// duplicate-key limits, and the exact number readers the typed value codec
// applies to raw number tokens. A parse is one frame; a number read is one
// token.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <nanobench.h>

extern "C" {
#include "json_codec.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "json_codec: " << what << " failed\n";
  std::exit(1);
}

// The request envelope the BEAM host writes (Wotex.OPCUA.Native.Frame).
std::string request(const std::string &operation, const std::string &parameters) {
  return R"({"version":1,"generation":1,"id":"req-000001","operation":")" + operation +
      R"(","parameters":)" + parameters + R"(,"timeout_ms":5000,"deadline_ms":86400000})" + "\n";
}

// A deterministic base64 text of the standard alphabet for `bytes` decoded bytes.
std::string base64(std::size_t bytes) {
  static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string text;
  const std::size_t groups = bytes / 3;
  for (std::size_t i = 0; i < groups * 4; ++i) text.push_back(alphabet[(i * 7U) % 64U]);
  if (bytes % 3 == 1) text += "AA==";
  if (bytes % 3 == 2) text += "AAA=";
  return text;
}

std::string envelope(std::size_t bytes) {
  return R"({"type":"bytes","base64":")" + base64(bytes) + R"("})";
}

// Read of one Double Variable: 10 value nodes.
std::string read_frame() {
  return request("read",
                 R"({"node_id":"ns=2;s=plant/line-4/oven-2/temperature","index_range":null})");
}

// Write of a flat array of `count` numbers of `type`, each formatted by
// `format` from its index: 14 + count value nodes.
template <typename Format>
std::string write_array(const char *type, std::size_t count, Format format) {
  std::string values;
  for (std::size_t i = 0; i < count; ++i) {
    if (i) values += ',';
    values += format(i);
  }
  return request("write",
                 R"({"node_id":"ns=2;s=plant/line-4/oven-2/profile","index_range":null,)"
                 R"("value":{"type":")" +
                     std::string(type) + R"(","array":true,"value":[)" + values + "]}}");
}

std::string write_doubles(std::size_t count) {
  return write_array("Double", count, [](std::size_t i) {
    char number[32];
    std::snprintf(number, sizeof(number), "%.3f", 21.5 + static_cast<double>(i) * 0.125);
    return std::string(number);
  });
}

// DateTime-sized Int64 values (100 ns ticks).
std::string write_int64s(std::size_t count) {
  return write_array("Int64", count, [](std::size_t i) {
    return std::to_string(133000000000000000LL + static_cast<long long>(i) * 10000000LL);
  });
}

// Write of one 64 KiB ByteString, the largest string the value codec admits: 16 value nodes.
std::string write_bytes() {
  return request("write",
                 R"({"node_id":"ns=2;s=plant/line-4/oven-2/recipe","index_range":null,)"
                 R"("value":{"type":"ByteString","array":false,"value":)" +
                     envelope(65536) + "}}");
}

// Open with the credential sizes of 2048-bit RSA application certificates: 31 value nodes.
std::string open_frame() {
  return request("open",
                 R"({"endpoint":"opc.tcp://plc.example:4840",)"
                 R"("security_policy":"http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",)"
                 R"("security_mode":"SignAndEncrypt","client_uri":"urn:example:opcua:client",)"
                 R"("server_uri":"urn:example:opcua:server","certificate":)" +
                     envelope(1024) + R"(,"private_key":)" + envelope(1218) +
                     R"(,"server_certificate":)" + envelope(1024) + R"(,"trust_certificate":)" +
                     envelope(812) + R"(,"crl":)" + envelope(461) +
                     R"(,"authentication":{"type":"anonymous"},"session_timeout_ms":60000})");
}

// Parameters with 1024 distinct keys, the container limit: every key is
// compared with each preceding key. 1032 value nodes.
std::string wide_object() {
  std::string keys = "{";
  char key[32];
  for (unsigned i = 0; i < 1024; ++i) {
    std::snprintf(key, sizeof(key), "%s\"k%04u\":0", i ? "," : "", i);
    keys += key;
  }
  return request("read", keys + "}");
}

std::string label(const char *name, const std::string &frame) {
  return std::string(name) + ", " + std::to_string(frame.size()) + " B";
}

// Parses `frame`, checks its node count and releases the document.
void parse(void *pool, const std::string &frame, std::size_t nodes) {
  WopJson parsed;
  check(
      wop_json_read(frame.data(), frame.size(), pool, WOP_JSON_POOL_BYTES, &parsed) == WOP_JSON_OK,
      "wop_json_read");
  check(parsed.nodes == nodes, "node count");
  wop_json_clear(&parsed);
}

// The array under parameters.value.value of a parsed write frame.
yyjson_val *write_values(const WopJson &parsed) {
  yyjson_val *parameters = yyjson_obj_get(yyjson_doc_get_root(parsed.document), "parameters");
  return yyjson_obj_get(yyjson_obj_get(parameters, "value"), "value");
}

} // namespace

int main() {
  std::unique_ptr<unsigned char[]> pool(new unsigned char[WOP_JSON_POOL_BYTES]);

  const std::string read = read_frame();
  const std::string open = open_frame();
  const std::string doubles = write_doubles(1024);
  const std::string bytes = write_bytes();
  const std::string wide = wide_object();
  check(bytes.size() < WOP_JSON_FRAME_BYTES, "64 KiB ByteString frame size");

  ankerl::nanobench::Bench parsing;
  parsing.title("wop_json_read")
      .unit("frame")
      .warmup(20)
      .minEpochTime(std::chrono::milliseconds(20));
  parsing.run(label("read request", read), [&] { parse(pool.get(), read, 10); });
  parsing.run(label("open request, 2048-bit RSA credentials", open),
              [&] { parse(pool.get(), open, 31); });
  parsing.run(label("write request, 1024 Doubles", doubles),
              [&] { parse(pool.get(), doubles, 1038); });
  parsing.run(label("write request, 64 KiB ByteString", bytes),
              [&] { parse(pool.get(), bytes, 16); });
  parsing.run(label("1024-key object, duplicate-key limit", wide),
              [&] { parse(pool.get(), wide, 1032); });

  // The number readers over retained documents; each borrows its own pool.
  std::unique_ptr<unsigned char[]> integer_pool(new unsigned char[WOP_JSON_POOL_BYTES]);
  const std::string int64s = write_int64s(1024);
  WopJson real_document;
  WopJson integer_document;
  check(wop_json_read(doubles.data(), doubles.size(), pool.get(), WOP_JSON_POOL_BYTES,
                      &real_document) == WOP_JSON_OK &&
            wop_json_read(int64s.data(), int64s.size(), integer_pool.get(), WOP_JSON_POOL_BYTES,
                          &integer_document) == WOP_JSON_OK,
        "wop_json_read of the number arrays");
  yyjson_val *reals = write_values(real_document);
  yyjson_val *integers = write_values(integer_document);
  check(yyjson_arr_size(reals) == 1024 && yyjson_arr_size(integers) == 1024, "number arrays");

  ankerl::nanobench::Bench numbers;
  numbers.title("number readers")
      .unit("token")
      .batch(1024)
      .warmup(20)
      .minEpochTime(std::chrono::milliseconds(20));
  numbers.run("wop_json_double, 1024 Double tokens", [&] {
    double sum = 0;
    std::size_t index = 0;
    std::size_t count = 0;
    yyjson_val *value = nullptr;
    yyjson_arr_foreach(reals, index, count, value) {
      double number = 0;
      check(wop_json_double(value, &number), "wop_json_double");
      sum += number;
    }
    check(sum == 1024 * 21.5 + 0.125 * 1023 * 1024 / 2, "Double sum");
  });
  numbers.run("wop_json_float, 1024 Double tokens", [&] {
    double sum = 0;
    std::size_t index = 0;
    std::size_t count = 0;
    yyjson_val *value = nullptr;
    yyjson_arr_foreach(reals, index, count, value) {
      float number = 0;
      check(wop_json_float(value, &number), "wop_json_float");
      sum += number;
    }
    check(sum == 1024 * 21.5 + 0.125 * 1023 * 1024 / 2, "Float sum");
  });
  numbers.run("wop_json_int64, 1024 Int64 tokens", [&] {
    int64_t sum = 0;
    std::size_t index = 0;
    std::size_t count = 0;
    yyjson_val *value = nullptr;
    yyjson_arr_foreach(integers, index, count, value) {
      int64_t number = 0;
      check(wop_json_int64(value, &number), "wop_json_int64");
      sum += number - 133000000000000000LL;
    }
    check(sum == 10000000LL * 1023 * 1024 / 2, "Int64 sum");
  });
  numbers.run("wop_json_uint64, 1024 Int64 tokens", [&] {
    uint64_t sum = 0;
    std::size_t index = 0;
    std::size_t count = 0;
    yyjson_val *value = nullptr;
    yyjson_arr_foreach(integers, index, count, value) {
      uint64_t number = 0;
      check(wop_json_uint64(value, &number), "wop_json_uint64");
      sum += number - 133000000000000000ULL;
    }
    check(sum == 10000000ULL * 1023 * 1024 / 2, "UInt64 sum");
  });
  wop_json_clear(&real_document);
  wop_json_clear(&integer_document);
  return 0;
}
