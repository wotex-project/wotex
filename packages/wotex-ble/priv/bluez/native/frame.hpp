// SPDX-License-Identifier: Apache-2.0
// Protocol-v1 parsing shared by the native host and its contract tests. Bounds
// apply while constructing the JSON tree; no SDK operation runs during parsing.
#pragma once
#include "vendor/json.hpp"
#include <algorithm>
#include <cstdint>
#include <cmath>
#include <functional>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace wotex::ble {
using Json = nlohmann::json;
constexpr std::size_t max_line = 131072;

class InvalidFrame : public std::runtime_error {
public:
  InvalidFrame() : std::runtime_error("invalid_frame") {}
};

// Each stack entry owns one container until its end marker. Duplicate-key
// rejection precedes insertion, so JSON's map behavior cannot erase evidence.
class BoundedSax final : public nlohmann::json_sax<Json> {
  struct Container {
    Json value;
    std::string key;
    std::size_t entries = 0;
    bool pending_key = false;
  };
  std::vector<Container> stack_;
  std::size_t nodes_ = 0;
  bool complete_ = false;

  bool node() {
    return ++nodes_ <= 4096 && stack_.size() < 8;
  }
  bool put(Json value) {
    if (stack_.empty()) {
      if (complete_) return false;
      result = std::move(value);
      complete_ = true;
      return true;
    }
    auto &parent = stack_.back();
    if (parent.value.is_object()) {
      if (!parent.pending_key) return false;
      parent.value.emplace(std::move(parent.key), std::move(value));
      parent.pending_key = false;
    } else {
      if (++parent.entries > 1024) return false;
      parent.value.push_back(std::move(value));
    }
    return true;
  }
  bool scalar(Json value) { return node() && put(std::move(value)); }
  bool start(bool object) {
    if (!node()) return false;
    stack_.push_back({object ? Json::object() : Json::array(), {}, 0, false});
    return true;
  }
  bool finish(bool object) {
    if (stack_.empty() || stack_.back().value.is_object() != object ||
        stack_.back().pending_key) return false;
    Json value = std::move(stack_.back().value);
    stack_.pop_back();
    return put(std::move(value));
  }
public:
  Json result;
  bool null() override { return scalar(nullptr); }
  bool boolean(bool value) override { return scalar(value); }
  bool number_integer(number_integer_t value) override { return scalar(value); }
  bool number_unsigned(number_unsigned_t value) override { return scalar(value); }
  bool number_float(number_float_t value, const string_t &token) override {
    // Integer overflow must not be silently rounded into an IEEE double.
    return token.find_first_of(".eE") != std::string::npos &&
           std::isfinite(value) && scalar(value);
  }
  bool string(string_t &value) override { return scalar(std::move(value)); }
  bool binary(binary_t &) override { return false; }
  bool start_object(std::size_t) override { return start(true); }
  bool key(string_t &key) override {
    if (stack_.empty()) return false;
    auto &parent = stack_.back();
    if (!parent.value.is_object() || parent.pending_key ||
        ++parent.entries > 1024 || parent.value.contains(key)) return false;
    parent.key = std::move(key);
    parent.pending_key = true;
    return true;
  }
  bool end_object() override { return finish(true); }
  bool start_array(std::size_t) override { return start(false); }
  bool end_array() override { return finish(false); }
  bool parse_error(std::size_t, const std::string &,
                   const nlohmann::detail::exception &) override { return false; }
};

inline Json parse_line(std::string_view line) {
  if (line.empty() || line.size() > max_line || line.back() != '\n' ||
      line.find('\n') != line.size() - 1) throw InvalidFrame();
  BoundedSax sax;
  if (!Json::sax_parse(line.begin(), line.end(), &sax)) throw InvalidFrame();
  return std::move(sax.result);
}

inline bool fields(const Json &value,
                   std::initializer_list<const char *> names) {
  if (!value.is_object() || value.size() != names.size()) return false;
  return std::all_of(names.begin(), names.end(),
                     [&](const char *key) { return value.contains(key); });
}

inline bool integer(const Json &value, std::uint64_t minimum,
                    std::uint64_t maximum) {
  if (!value.is_number_integer() ||
      (value.is_number_integer() && !value.is_number_unsigned() &&
       value.get<std::int64_t>() < 0)) return false;
  const auto number = value.get<std::uint64_t>();
  return number >= minimum && number <= maximum;
}

inline bool request(const Json &value) {
  if (!fields(value, {"version", "id", "operation", "parameters", "timeout_ms"}) ||
      !integer(value["version"], 1, 1) || !value["id"].is_string() ||
      value["id"].get_ref<const std::string &>().empty() ||
      value["id"].get_ref<const std::string &>().size() > 64 ||
      !value["operation"].is_string() || !value["parameters"].is_object() ||
      !integer(value["timeout_ms"], 1, 60000)) return false;
  const auto &operation = value["operation"].get_ref<const std::string &>();
  for (const char *known : {"open", "discover", "read", "write", "subscribe",
                            "unsubscribe", "pair", "agent_reply", "health", "close"}) {
    if (operation == known) return true;
  }
  return false;
}

// The dispatch counter is shared by data and controls. Its storage does not
// grow with the number of completed operations or subscription lifetimes.
class Sequence {
  std::uint64_t last_ = 0;
  bool opened_ = false;
public:
  bool accept(const Json &value) {
    if (!request(value)) return false;
    const auto &id = value["id"].get_ref<const std::string &>();
    const auto &operation = value["operation"].get_ref<const std::string &>();
    if (operation == "open") {
      if (id != "open" || opened_ || last_ != 0) return false;
      opened_ = true;
      return true;
    }
    if (operation == "close") return id == "close" && value["parameters"].empty();
    if (!opened_) return false;
    std::string_view digits(id);
    if (operation == "agent_reply") {
      if (digits.substr(0, 6) != "agent-") return false;
      digits.remove_prefix(6);
    }
    if (digits.empty() || digits.size() > 20 || digits.front() == '0') return false;
    std::uint64_t number = 0;
    for (char digit : digits) {
      if (digit < '0' || digit > '9') return false;
      const auto next = static_cast<std::uint64_t>(digit - '0');
      if (number > (std::numeric_limits<std::uint64_t>::max() - next) / 10) return false;
      number = number * 10 + next;
    }
    if (number <= last_) return false;
    last_ = number;
    return true;
  }
};

// Incremental decoder holds at most one bounded partial line. Completed lines
// are transferred to the supplied owner immediately, never accumulated here.
class Lines {
  std::string partial_;
  bool failed_ = false;
public:
  void feed(std::string_view bytes,
            const std::function<void(std::string_view)> &consume) {
    if (failed_) throw InvalidFrame();
    try {
      while (!bytes.empty()) {
        const auto newline = bytes.find('\n');
        const auto count = newline == std::string_view::npos ? bytes.size() : newline + 1;
        if (count > max_line - partial_.size()) throw InvalidFrame();
        partial_.append(bytes.data(), count);
        bytes.remove_prefix(count);
        if (newline != std::string_view::npos) {
          consume(partial_);
          partial_.clear();
        } else if (partial_.size() == max_line) {
          // The maximum includes a required newline, so this cannot complete.
          throw InvalidFrame();
        }
      }
    } catch (...) {
      failed_ = true;
      partial_.clear();
      throw;
    }
  }
  void eof() const {
    if (failed_ || !partial_.empty()) throw InvalidFrame();
  }
  std::size_t buffered() const { return partial_.size(); }
};
} // namespace wotex::ble
