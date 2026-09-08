#ifndef WOTEX_THREAD_PROTOCOL_HPP
#define WOTEX_THREAD_PROTOCOL_HPP

#include <nlohmann/json.hpp>
#include <cstddef>
#include <cstdint>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace wotex::thread {
using Json = nlohmann::json;
constexpr std::size_t kMaximumLine = 128 * 1024;
constexpr std::size_t kMaximumDepth = 8;
constexpr std::size_t kMaximumCollection = 1024;
constexpr std::size_t kMaximumNodes = 4096;
constexpr std::string_view kRevision = "5c8c318627954c99cd1a957a290bbd4b1027d04b";

class ProtocolError final : public std::runtime_error {
 public:
  ProtocolError() : std::runtime_error("invalid_bridge_message") {}
};

inline Json parse_line(std::string_view line) {
  if (line.empty() || line.size() > kMaximumLine || line.back() != '\n' ||
      line.substr(0, line.size() - 1).find('\n') != std::string_view::npos) {
    throw ProtocolError();
  }
  struct Frame {
    bool object;
    std::size_t elements = 0;
    std::set<std::string> keys;
  };
  std::vector<Frame> frames;
  std::size_t nodes = 0;
  auto value = [&] {
    if (++nodes > kMaximumNodes) throw ProtocolError();
    if (!frames.empty() && !frames.back().object &&
        ++frames.back().elements > kMaximumCollection) throw ProtocolError();
  };
  auto callback = [&](int, Json::parse_event_t event, Json &parsed) {
    switch (event) {
      case Json::parse_event_t::object_start:
      case Json::parse_event_t::array_start:
        value();
        if (frames.size() == kMaximumDepth) throw ProtocolError();
        frames.push_back({event == Json::parse_event_t::object_start, 0, {}});
        break;
      case Json::parse_event_t::object_end:
      case Json::parse_event_t::array_end:
        frames.pop_back();
        break;
      case Json::parse_event_t::key:
        if (++frames.back().elements > kMaximumCollection ||
            !frames.back().keys.insert(parsed.get<std::string>()).second) {
          throw ProtocolError();
        }
        break;
      case Json::parse_event_t::value:
        value();
        break;
    }
    return true;
  };
  try {
    return Json::parse(line.begin(), line.end(), callback);
  } catch (const Json::exception &) {
    throw ProtocolError();
  }
}

inline bool exact_keys(const Json &value, const std::set<std::string> &keys) {
  if (!value.is_object() || value.size() != keys.size()) return false;
  for (const auto &key : keys) if (!value.contains(key)) return false;
  return true;
}

inline bool bounded_string(const Json &value, std::size_t maximum) {
  if (!value.is_string()) return false;
  const auto &text = value.get_ref<const std::string &>();
  return !text.empty() && text.size() <= maximum && text.find('\0') == std::string::npos;
}

struct Request {
  std::string id;
  std::string operation;
  Json parameters;
  std::uint32_t timeout_ms;
};

inline Request request(const Json &value) {
  if (!exact_keys(value, {"version", "id", "operation", "parameters", "timeout_ms"}) ||
      !value.at("version").is_number_integer() || value.at("version") != 1 ||
      !bounded_string(value.at("id"), 128) || !bounded_string(value.at("operation"), 64) ||
      !value.at("parameters").is_object() || !value.at("timeout_ms").is_number_integer() ||
      value.at("timeout_ms") < 1 || value.at("timeout_ms") > 60000) {
    throw ProtocolError();
  }
  return {value.at("id").get<std::string>(), value.at("operation").get<std::string>(),
          value.at("parameters"), value.at("timeout_ms").get<std::uint32_t>()};
}

inline Json ready() {
  return {{"version", 1}, {"event", "ready"}, {"backend", "openthread"}, {"revision", kRevision}};
}
inline Json success(const Request &request, const Json &result) {
  return {{"version", 1}, {"id", request.id}, {"ok", true}, {"result", result}};
}
inline Json failure(const Request &request, std::string_view code) {
  return {{"version", 1}, {"id", request.id}, {"ok", false}, {"error", {{"code", code}}}};
}
}  // namespace wotex::thread
#endif
