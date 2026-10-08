// SPDX-License-Identifier: Apache-2.0
// Independent WMB.09/WRT.06 reference. No WoTEx decoder or device APIs.
#include "sha256.hpp"
#include "vendor/json.hpp"
#include <algorithm>
#include <cerrno>
#include <exception>
#include <set>
#include <unistd.h>

namespace {
using Json = nlohmann::json;
constexpr const char *contract_sha256 =
    "0ca3f57f25c41ca3d04f8b0d97d5ffc780d90440d4d482cb9dbf743e45437e42";
constexpr int64_t safe_integer = 9007199254740991;
struct ProtocolFault : std::exception {};
void require(bool condition) {
  if (!condition) throw ProtocolFault{};
}

bool closed(const Json &value, std::initializer_list<const char *> keys) {
  return value.is_object() && value.size() == keys.size() &&
      std::all_of(keys.begin(), keys.end(), [&](const char *key) { return value.contains(key); });
}
bool integer(const Json &value, int64_t min, int64_t max) {
  if (!value.is_number_integer()) return false;
  if (value.is_number_unsigned())
    return value.get<uint64_t>() <= static_cast<uint64_t>(max) &&
        (min <= 0 || value.get<uint64_t>() >= static_cast<uint64_t>(min));
  const int64_t number = value.get<int64_t>();
  return number >= min && number <= max;
}
bool text(const Json &value, size_t min, size_t max) {
  return value.is_string() && value.get_ref<const std::string &>().size() >= min &&
      value.get_ref<const std::string &>().size() <= max;
}
bool digest(const Json &value) {
  if (!text(value, 64, 64)) return false;
  const auto &s = value.get_ref<const std::string &>();
  return std::all_of(s.begin(), s.end(),
                     [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); });
}
bool token(const Json &value) {
  if (!text(value, 1, 128)) return false;
  const auto &s = value.get_ref<const std::string &>();
  const auto alnum = [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'); };
  return alnum(s.front()) && std::all_of(s.begin(), s.end(), [&](char c) {
    return alnum(c) || c == '.' || c == '_' || c == ':' || c == '/' || c == '-';
  });
}
bool flat(const Json &value) {
  if (!value.is_object() || value.size() > 16 || value.dump().size() > 4096) return false;
  for (auto it = value.begin(); it != value.end(); ++it) {
    if (it.key().empty() || it.key().size() > 128) return false;
    if (!(it->is_null() || it->is_boolean() || integer(*it, -safe_integer, safe_integer) ||
          text(*it, 0, 256)))
      return false;
  }
  return true;
}

Json parse(const std::string &bytes) {
  require(!bytes.empty() && bytes.size() < 131072 && bytes.compare(0, 3, "\xef\xbb\xbf") != 0);
  bool quoted = false, escaped = false;
  for (size_t i = 0; i < bytes.size(); ++i) {
    const char c = bytes[i];
    require(c != '\r' && c != '\n');
    if (quoted) {
      if (escaped) escaped = false;
      else if (c == '\\') escaped = true;
      else if (c == '"') quoted = false;
    } else if (c == '"') quoted = true;
    else if ((c >= '0' && c <= '9') || c == '-') {
      size_t end = i + 1;
      while (end < bytes.size() &&
             ((bytes[end] >= '0' && bytes[end] <= '9') || bytes[end] == '.' || bytes[end] == 'e' ||
              bytes[end] == 'E' || bytes[end] == '+' || bytes[end] == '-'))
        ++end;
      require(end - i <= 18);
      for (size_t n = i + 1; n < end; ++n) require(bytes[n] >= '0' && bytes[n] <= '9');
      i = end - 1;
    }
  }
  std::vector<std::set<std::string>> keys;
  size_t nodes = 0;
  auto callback = [&](int depth, Json::parse_event_t event, Json &value) {
    require(depth < 24);
    if (event == Json::parse_event_t::object_start) {
      require(++nodes <= 4096);
      keys.emplace_back();
    } else if (event == Json::parse_event_t::key) {
      require(!keys.empty() && keys.back().size() < 256 &&
              keys.back().insert(value.get<std::string>()).second);
    } else if (event == Json::parse_event_t::object_end) {
      keys.pop_back();
    } else if (event == Json::parse_event_t::array_start) {
      throw ProtocolFault{}; // No inbound v1 field admits an array.
    } else if (event == Json::parse_event_t::value) {
      require(++nodes <= 4096 && !value.is_number_float());
      if (value.is_number_integer()) require(integer(value, -safe_integer, safe_integer));
      if (value.is_string()) require(text(value, 0, 87384));
    }
    return true;
  };
  return Json::parse(bytes, callback);
}

std::vector<uint8_t> input_bytes(const Json &value) {
  require(closed(value, {"type", "base64"}) && value["type"] == "bytes" &&
          text(value["base64"], 0, 87384));
  const auto &encoded = value["base64"].get_ref<const std::string &>();
  const size_t padding = encoded.empty()
      ? 0
      : (encoded.back() == '=' ? (encoded.size() > 1 && encoded[encoded.size() - 2] == '=' ? 2 : 1)
                               : 0);
  require(encoded.size() % 4 == 0 && encoded.size() / 4 * 3 - padding <= 65536);
  const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::vector<uint8_t> output;
  output.reserve(encoded.size() / 4 * 3 - padding);
  for (size_t i = 0; i < encoded.size(); i += 4) {
    std::array<unsigned, 4> digit{};
    const bool last = i + 4 == encoded.size();
    for (size_t j = 0; j < 4; ++j) {
      if (encoded[i + j] == '=') {
        require(last && j >= 2 && padding != 0 && j >= 4 - padding);
      } else {
        const size_t found = alphabet.find(encoded[i + j]);
        require(found != std::string::npos && (!last || j < 4 - padding));
        digit[j] = static_cast<unsigned>(found);
      }
    }
    if (last && padding == 2) require((digit[1] & 15) == 0);
    if (last && padding == 1) require((digit[2] & 3) == 0);
    output.push_back(static_cast<uint8_t>((digit[0] << 2) | (digit[1] >> 4)));
    if (!last || padding < 2)
      output.push_back(static_cast<uint8_t>((digit[1] << 4) | (digit[2] >> 2)));
    if (!last || padding == 0) output.push_back(static_cast<uint8_t>((digit[2] << 6) | digit[3]));
  }
  return output;
}

void configuration(const Json &value) {
  require(closed(value, {"registers", "byte_order", "word_order", "scale", "signed"}) &&
          integer(value["registers"], 1, 4) && integer(value["scale"], -32768, 32767) &&
          value["signed"].is_boolean() &&
          (value["byte_order"] == "big" || value["byte_order"] == "little") &&
          (value["word_order"] == "big" || value["word_order"] == "little"));
}

Json projected(const std::vector<uint8_t> &bytes, const Json &metadata, const Json &config,
               std::string &refusal) {
  refusal = "invalid_input";
  if (!closed(metadata, {"format"}) || !text(metadata["format"], 0, 256)) return nullptr;
  if (metadata["format"] != "packed-bcd-v1") {
    refusal = "unsupported_format";
    return nullptr;
  }
  const size_t words = config["registers"].get<size_t>();
  if (bytes.size() != words * 2) return nullptr;
  std::vector<unsigned> digits;
  for (size_t logical = 0; logical < words; ++logical) {
    const size_t physical = config["word_order"] == "big" ? logical : words - logical - 1;
    for (size_t part = 0; part < 2; ++part) {
      const size_t offset = config["byte_order"] == "big" ? part : 1 - part;
      const uint8_t byte = bytes[physical * 2 + offset];
      digits.push_back(byte >> 4);
      digits.push_back(byte & 15);
    }
  }
  bool negative = false;
  if (config["signed"].get<bool>()) {
    const unsigned sign = digits.back();
    if (sign != 12 && sign != 13) return nullptr;
    negative = sign == 13;
    digits.pop_back();
  }
  int64_t coefficient = 0;
  for (unsigned digit : digits) {
    if (digit > 9) return nullptr;
    coefficient = coefficient * 10 + digit;
  }
  refusal = "unsupported_value";
  if (negative && coefficient == 0) return nullptr;
  int exponent = config["scale"].get<int>();
  if (coefficient == 0) exponent = 0;
  else
    while (coefficient % 10 == 0) {
      coefficient /= 10;
      ++exponent;
    }
  if (exponent > 32767) return nullptr;
  if (negative) coefficient = -coefficient;
  return Json{
      {"type", "decimal"}, {"coefficient", std::to_string(coefficient)}, {"exponent", exponent}};
}

void output(const Json &frame) {
  const std::string bytes = frame.dump() + "\n";
  size_t offset = 0;
  while (offset < bytes.size()) {
    const ssize_t wrote = write(STDOUT_FILENO, bytes.data() + offset, bytes.size() - offset);
    if (wrote < 0 && errno == EINTR) continue;
    require(wrote > 0);
    offset += static_cast<size_t>(wrote);
  }
}

class Codec {
  Json config;
  int64_t next = 1;
  int decode_ms = 0;
  bool ready = false;
 public:
  bool accept(const Json &frame) {
    require(frame.is_object() && frame.contains("v") && integer(frame["v"], 1, 1) &&
            frame.contains("type"));
    if (frame["type"] == "stop") {
      require(closed(frame, {"v", "type"}));
      return false;
    }
    if (!ready) {
      require(frame["type"] == "hello" &&
              closed(frame,
                     {"v", "type", "instance_id", "generation", "descriptor_sha256", "contract_id",
                      "contract_sha256", "decode_ms", "configuration", "configuration_sha256"}));
      require(token(frame["instance_id"]) && integer(frame["generation"], 1, safe_integer) &&
              digest(frame["descriptor_sha256"]) &&
              frame["contract_id"] == "wotex.modbus.register-decimal" &&
              frame["contract_sha256"] == contract_sha256 && integer(frame["decode_ms"], 1, 1000) &&
              digest(frame["configuration_sha256"]));
      config = frame["configuration"];
      configuration(config);
      require(wmb_reference::sha256(config.dump()) == frame["configuration_sha256"]);
      decode_ms = frame["decode_ms"].get<int>();
      Json response = frame;
      response.erase("configuration");
      response["type"] = "ready";
      output(response);
      ready = true;
    } else {
      require(frame["type"] == "decode" &&
              closed(frame, {"v", "type", "seq", "request_id", "budget_ms", "bytes", "metadata"}));
      require(integer(frame["seq"], 1, safe_integer) && frame["seq"] == next &&
              text(frame["request_id"], 1, 256) && integer(frame["budget_ms"], 1, decode_ms) &&
              flat(frame["metadata"]));
      const auto bytes = input_bytes(frame["bytes"]);
      std::string refusal;
      Json value = projected(bytes, frame["metadata"], config, refusal);
      Json response{{"v", 1},
                    {"type", value.is_null() ? "refusal" : "result"},
                    {"seq", next},
                    {"request_id", frame["request_id"]}};
      if (value.is_null()) response["code"] = refusal;
      else response["value"] = value;
      output(response);
      ++next;
    }
    return true;
  }
};
} // namespace

int main() {
  try {
    require(wmb_reference::sha256("") ==
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    require(wmb_reference::sha256("abc") ==
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    require(wmb_reference::sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    Codec codec;
    std::string pending;
    std::array<char, 4096> chunk{};
    for (;;) {
      const ssize_t count = read(STDIN_FILENO, chunk.data(), chunk.size());
      if (count < 0 && errno == EINTR) continue;
      require(count >= 0);
      if (count == 0) {
        require(pending.empty());
        return 0;
      }
      for (ssize_t i = 0; i < count; ++i) {
        if (chunk[static_cast<size_t>(i)] == '\n') {
          if (!codec.accept(parse(pending))) return 0;
          pending.clear();
        } else {
          require(pending.size() < 131071);
          pending.push_back(chunk[static_cast<size_t>(i)]);
        }
      }
    }
  } catch (...) {
    return 65; // No parser, configuration, input or exception diagnostics.
  }
}
