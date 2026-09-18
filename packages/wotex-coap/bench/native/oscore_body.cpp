// SPDX-License-Identifier: Apache-2.0
// The upload body of the native OSCORE helper (native/oscore/body.c): canonical
// base64 validation and decoding of one byte envelope, and a whole upload as
// the worker admits it: body_begin (allocation), body_chunk per 32 KiB chunk,
// body_end (SHA-256 verification), data access and clear (erasure). The unit
// is one decoded body byte.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <openssl/evp.h>
#include <nanobench.h>

extern "C" {
#include "body.h"
#include "json.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "oscore_body: " << what << " failed\n";
  std::exit(1);
}

std::vector<unsigned char> pattern(std::size_t size) {
  std::vector<unsigned char> bytes(size);
  for (std::size_t index = 0; index < size; ++index)
    bytes[index] = static_cast<unsigned char>((index * 31U + 7U) & 0xffU);
  return bytes;
}

std::string base64(const std::vector<unsigned char> &bytes) {
  static const char digits[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve(4 * ((bytes.size() + 2) / 3));
  for (std::size_t offset = 0; offset < bytes.size(); offset += 3) {
    const std::size_t left = bytes.size() - offset;
    const unsigned value = (bytes[offset] << 16U) | (left > 1 ? bytes[offset + 1] << 8U : 0U) |
        (left > 2 ? bytes[offset + 2] : 0U);
    encoded += digits[(value >> 18U) & 63U];
    encoded += digits[(value >> 12U) & 63U];
    encoded += left > 1 ? digits[(value >> 6U) & 63U] : '=';
    encoded += left > 2 ? digits[value & 63U] : '=';
  }
  return encoded;
}

// The lowercase SHA-256 of `count` copies of `chunk`, as body_begin expects it.
std::string sha256(const std::vector<unsigned char> &chunk, std::size_t count) {
  unsigned char digest[32];
  unsigned length = 0;
  EVP_MD_CTX *context = EVP_MD_CTX_new();
  check(context != nullptr && EVP_DigestInit_ex(context, EVP_sha256(), nullptr) == 1, "sha256");
  for (std::size_t index = 0; index < count; ++index)
    check(EVP_DigestUpdate(context, chunk.data(), chunk.size()) == 1, "sha256");
  check(EVP_DigestFinal_ex(context, digest, &length) == 1 && length == 32, "sha256");
  EVP_MD_CTX_free(context);
  static const char hex[] = "0123456789abcdef";
  std::string text;
  for (const unsigned char byte : digest) {
    text += hex[byte >> 4U];
    text += hex[byte & 15U];
  }
  return text;
}

// One parsed byte envelope, {"base64":...,"type":"bytes"}, owned by its decoder.
struct Envelope {
  wco_json *json = wco_json_new();
  yyjson_val *value = nullptr;

  explicit Envelope(const std::vector<unsigned char> &bytes) {
    const std::string line = R"({"base64":")" + base64(bytes) + R"(","type":"bytes"})" + '\n';
    check(json != nullptr && wco_json_parse(json, line.data(), line.size()) == WCO_JSON_OK,
          "envelope parse");
    value = wco_json_root(json);
  }
  ~Envelope() { wco_json_free(json); }
  Envelope(const Envelope &) = delete;
  Envelope &operator=(const Envelope &) = delete;
  Envelope(Envelope &&) = delete;
  Envelope &operator=(Envelope &&) = delete;
};

// Admits a body of `count` chunks and verifies what the worker would send.
void upload(wco_body *body, const Envelope &chunk, std::size_t chunk_size, std::size_t count,
            const std::string &hash) {
  static const char id[] = "4";
  const std::size_t total = chunk_size * count;
  check(wco_body_begin(body, id, 1, total, hash.data(), hash.size()) == 1, "body_begin");
  for (std::size_t index = 0; index < count; ++index)
    check(wco_body_chunk(body, id, 1, index * chunk_size, chunk.value) == 1, "body_chunk");
  check(wco_body_end(body, id, 1) == 1, "body_end");
  const std::uint8_t *data = nullptr;
  std::size_t length = 0;
  check(wco_body_data(body, &data, &length) == 1 && length == total, "body data");
  ankerl::nanobench::doNotOptimizeAway(data);
  wco_body_clear(body);
}

} // namespace

int main() {
  const std::vector<unsigned char> small = pattern(1024);
  const std::vector<unsigned char> large = pattern(WCO_BODY_CHUNK_MAX);
  const Envelope small_chunk(small);
  const Envelope large_chunk(large);

  // The decoded chunk is exactly the pattern before anything is measured.
  std::vector<std::uint8_t> buffer(WCO_BODY_CHUNK_MAX);
  std::size_t length = 0;
  check(wco_body_base64(large_chunk.value, buffer.data(), buffer.size(), &length) == 1 &&
            length == large.size() && std::memcmp(buffer.data(), large.data(), length) == 0,
        "base64 round trip");

  wco_body body;
  wco_body_init(&body);

  ankerl::nanobench::Bench bench;
  bench.title("upload body").unit("B").warmup(10).minEpochTime(std::chrono::milliseconds(20));

  bench.batch(large.size()).run("decode one 32 KiB chunk", [&] {
    check(wco_body_base64(large_chunk.value, buffer.data(), buffer.size(), &length) == 1 &&
              length == large.size(),
          "base64 decode");
  });

  const std::string small_hash = sha256(small, 1);
  bench.batch(small.size()).run("upload 1 KiB in 1 chunk", [&] {
    upload(&body, small_chunk, small.size(), 1, small_hash);
  });

  const std::pair<std::size_t, const char *> uploads[] = {{2, "upload 64 KiB in 2 chunks"},
                                                          {32, "upload 1 MiB in 32 chunks"}};
  for (const auto &entry : uploads) {
    const std::size_t count = entry.first;
    const std::string hash = sha256(large, count);
    bench.batch(large.size() * count).run(entry.second, [&] {
      upload(&body, large_chunk, large.size(), count, hash);
    });
  }

  check(body.failed == 0, "no upload failed");
  return 0;
}
