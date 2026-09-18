// SPDX-License-Identifier: Apache-2.0
// Attribute byte envelopes of the BLE native host (priv/bluez/native/bytes.hpp):
// canonical RFC 4648 base64 decoding of a C07 byte envelope into attribute
// bytes, within the 512-byte ATT bound, and encoding of attribute bytes into
// an envelope, for 20-byte (default ATT MTU), 244-byte (LE Data Length
// Extension) and 512-byte (ATT maximum) values. Each operation is one value.
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <string>
#include <nanobench.h>

#include "bytes.hpp"

namespace {
using wotex::ble::AttributeBytes;
using wotex::ble::Json;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "bytes: " << what << " failed\n";
  std::exit(1);
}

// `size` bytes covering every byte value.
std::string attribute(std::size_t size) {
  std::string bytes(size, '\0');
  for (std::size_t index = 0; index < size; ++index)
    bytes[index] = static_cast<char>((index * 73 + 41) & 0xff);
  return bytes;
}

bool equal(const AttributeBytes &decoded, const std::string &bytes) {
  const auto &value = decoded.value();
  if (value.size() != bytes.size()) return false;
  for (std::size_t index = 0; index < bytes.size(); ++index)
    if (value[index] != static_cast<unsigned char>(bytes[index])) return false;
  return true;
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.title("attribute byte envelopes")
      .unit("value")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  for (const std::size_t size : {20U, 244U, 512U}) {
    const std::string bytes = attribute(size);
    const AttributeBytes value = AttributeBytes::from_bytes(bytes);
    const Json envelope = value.envelope();
    const std::string &text = envelope.at("base64").get_ref<const std::string &>();
    check(text.size() == (size + 2) / 3 * 4, "envelope length");
    check(equal(AttributeBytes::from(envelope), bytes), "round trip");
    const std::string suffix = std::to_string(size) + " B";

    bench.run("decode " + suffix, [&] {
      const AttributeBytes decoded = AttributeBytes::from(envelope);
      check(decoded.value().size() == size, "decoded size");
      ankerl::nanobench::doNotOptimizeAway(decoded);
    });
    bench.run("encode " + suffix, [&] {
      const Json encoded = value.envelope();
      check(encoded.at("base64").get_ref<const std::string &>().size() == text.size(),
            "encoded size");
      ankerl::nanobench::doNotOptimizeAway(encoded);
    });
  }
  return 0;
}
