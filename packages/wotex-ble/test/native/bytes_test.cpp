// SPDX-License-Identifier: Apache-2.0
#include "bytes.hpp"
#include <iostream>
using namespace wotex::ble;
static void check(bool value) { if (!value) throw std::runtime_error("native bytes assertion"); }
static Json envelope(const std::string &value) { return {{"type", "bytes"}, {"base64", value}}; }
static void rejected(const Json &value) {
  bool rejected = false;
  try { AttributeBytes::from(value); } catch (const InvalidValue &) { rejected = true; }
  check(rejected);
}
static void invariants() {
  check(AttributeBytes::from_bytes(std::string_view{}).value().empty());
  // RFC 4648 section 10 examples are independent known-answer values.
  for (const auto &[plain, encoded] : std::vector<std::pair<std::string, std::string>>{
    {"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"},
    {"foob", "Zm9vYg=="}, {"fooba", "Zm9vYmE="}, {"foobar", "Zm9vYmFy"}}) {
    check(AttributeBytes::from_bytes(plain).envelope() == envelope(encoded));
    const auto decoded = AttributeBytes::from(envelope(encoded));
    check(std::string(decoded.value().begin(), decoded.value().end()) == plain);
  }
  std::string bytes;
  for (std::size_t length = 0; length <= 512; ++length) {
    const auto value = AttributeBytes::from_bytes(bytes);
    check(AttributeBytes::from(value.envelope()).value() == value.value());
    bytes += static_cast<char>(length & 255);
  }
  bool oversized = false;
  try { AttributeBytes::from_bytes(bytes); } catch (const InvalidValue &) { oversized = true; }
  check(oversized);
  for (const auto &text : {"A", "AA", "AAA", "====", "=AAA", "A=AA", "AA=A", "AA==AAAA",
       "AAA=AAAA", "AB==", "AAB=", "AA-_", "AA==\n", "AA== ", "\xc3\xa4=="}) rejected(envelope(text));
  rejected(envelope(std::string("AA\0=", 4)));
  rejected(envelope(std::string(684, 'A'))); // 513 decoded bytes without padding
  rejected(envelope(std::string(688, 'A')));
  for (const auto &value : {Json(), Json::array(), Json::object(), Json({{"type", "bytes"}}),
       Json({{"type", "bytes"}, {"base64", true}}), Json({{"type", true}, {"base64", ""}}),
       Json({{"type", "bytes"}, {"base64", ""}, {"extra", 1}})}) rejected(value);
  const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  for (unsigned digit = 0; digit < 64; ++digit) {
    if (digit & 15) rejected(envelope(std::string("A") + alphabet[digit] + "=="));
    if (digit & 3) rejected(envelope(std::string("AA") + alphabet[digit] + "="));
  }
}
int main(int argc, char **argv) {
  try {
    if (argc == 3 && std::string(argv[1]) == "--decode") {
      Json result;
      try {
        const auto value = AttributeBytes::from(parse_line(std::string(argv[2]) + "\n"));
        result = {{"accepted", true}, {"bytes", value.value()}};
      } catch (const InvalidValue &) { result = {{"accepted", false}}; }
      catch (const InvalidFrame &) { result = {{"accepted", false}}; }
      std::cout << result.dump() << '\n'; return 0;
    }
    if (argc != 1) return 2;
    invariants(); std::cout << "native byte envelope invariants passed\n"; return 0;
  } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
