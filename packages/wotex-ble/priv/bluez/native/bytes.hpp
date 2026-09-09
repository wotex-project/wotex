// SPDX-License-Identifier: Apache-2.0
// Canonical RFC 4648 base64 for C07 byte envelopes. The 512-byte ATT limit is
// checked before allocating decoded storage; this type performs no protocol I/O.
#pragma once
#include "frame.hpp"

namespace wotex::ble {
class InvalidValue : public std::runtime_error {
public:
  InvalidValue() : std::runtime_error("invalid_value") {}
};
class AttributeBytes {
  std::vector<std::uint8_t> value_;
  explicit AttributeBytes(std::vector<std::uint8_t> value) : value_(std::move(value)) {}
  static int digit(unsigned char value) {
    if (value >= 'A' && value <= 'Z') return value - 'A';
    if (value >= 'a' && value <= 'z') return value - 'a' + 26;
    if (value >= '0' && value <= '9') return value - '0' + 52;
    if (value == '+') return 62;
    if (value == '/') return 63;
    return -1;
  }
public:
  static AttributeBytes from_bytes(std::string_view value) {
    if (value.size() > 512) throw InvalidValue();
    if (value.empty()) return AttributeBytes({});
    return AttributeBytes(std::vector<std::uint8_t>(value.begin(), value.end()));
  }
  static AttributeBytes from(const Json &value) {
    if (!fields(value, {"type", "base64"}) || value.at("type") != "bytes" ||
        !value.at("base64").is_string()) throw InvalidValue();
    const auto &text = value.at("base64").get_ref<const std::string &>();
    if (text.size() > 684 || text.size() % 4) throw InvalidValue();
    if (text.empty()) return AttributeBytes({});
    const unsigned padding = unsigned(text.back() == '=') + unsigned(text[text.size() - 2] == '=');
    const auto length = text.size() / 4 * 3 - padding;
    if (length > 512) throw InvalidValue();
    std::vector<std::uint8_t> result; result.reserve(length);
    for (std::size_t offset = 0; offset < text.size(); offset += 4) {
      const bool last = offset + 4 == text.size();
      const auto a = digit(text[offset]), b = digit(text[offset + 1]);
      const auto c = digit(text[offset + 2]), d = digit(text[offset + 3]);
      if (a < 0 || b < 0) throw InvalidValue();
      result.push_back(static_cast<std::uint8_t>((a << 2) | (b >> 4)));
      if (last && padding == 2) {
        if (text[offset + 2] != '=' || text[offset + 3] != '=' || (b & 15)) throw InvalidValue();
      } else {
        if (c < 0) throw InvalidValue();
        result.push_back(static_cast<std::uint8_t>((b << 4) | (c >> 2)));
        if (last && padding == 1) {
          if (text[offset + 3] != '=' || (c & 3)) throw InvalidValue();
        } else {
          if (d < 0) throw InvalidValue();
          result.push_back(static_cast<std::uint8_t>((c << 6) | d));
        }
      }
    }
    return AttributeBytes(std::move(result));
  }
  Json envelope() const {
    static constexpr char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string result; result.reserve((value_.size() + 2) / 3 * 4);
    for (std::size_t offset = 0; offset < value_.size(); offset += 3) {
      const auto remaining = value_.size() - offset;
      const auto a = value_[offset];
      const auto b = remaining > 1 ? value_[offset + 1] : 0;
      const auto c = remaining > 2 ? value_[offset + 2] : 0;
      result += alphabet[a >> 2];
      result += alphabet[((a & 3) << 4) | (b >> 4)];
      result += remaining > 1 ? alphabet[((b & 15) << 2) | (c >> 6)] : '=';
      result += remaining > 2 ? alphabet[c & 63] : '=';
    }
    return {{"type", "bytes"}, {"base64", std::move(result)}};
  }
  const std::vector<std::uint8_t> &value() const { return value_; }
};
} // namespace wotex::ble
