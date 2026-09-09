// SPDX-License-Identifier: Apache-2.0
// Discovery paging over a validated immutable SDK snapshot. Cursor ownership is
// bounded by a generation/offset ledger; this component performs no D-Bus I/O.
#pragma once
#include "output.hpp"
#include <map>
#include <optional>

namespace wotex::ble {
class PageFailure : public std::runtime_error {
public:
  explicit PageFailure(const char *code) : std::runtime_error(code) {}
};
class PageRequest {
public:
  const std::optional<std::string> cursor;
  const std::size_t limit;
  static bool token(std::string_view value) {
    return value.size() == 32 && std::all_of(value.begin(), value.end(), [](char c) {
      return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
  }
  static PageRequest from(const Json &parameters) {
    if (!parameters.is_object() || parameters.size() > 2) throw PageFailure("invalid_options");
    for (const auto &[key, unused] : parameters.items()) {
      (void)unused;
      if (key != "cursor" && key != "limit") throw PageFailure("invalid_options");
    }
    if (parameters.contains("limit") && !integer(parameters.at("limit"), 1, 64)) throw PageFailure("invalid_options");
    std::optional<std::string> cursor;
    if (parameters.contains("cursor") && !parameters.at("cursor").is_null()) {
      const auto &value = parameters.at("cursor");
      if (!value.is_string() || !token(value.get_ref<const std::string &>())) throw PageFailure("invalid_cursor");
      cursor = value.get<std::string>();
    }
    return {std::move(cursor), parameters.contains("limit") ? parameters.at("limit").get<std::size_t>() : 64};
  }
};

class NativePages {
  using Position = std::pair<std::uint64_t, std::size_t>;
  std::map<std::string, Position> cursors_;
  std::map<Position, std::string> positions_;
  std::function<std::string()> random_;
  std::uint64_t generation_ = 0;

  std::string issue(std::uint64_t generation, std::size_t offset) {
    const Position position{generation, offset};
    const auto found = positions_.find(position);
    if (found != positions_.end()) return found->second;
    if (cursors_.size() == 1024 && positions_.begin()->first.first >= generation) throw PageFailure("resource_limit");
    std::string token;
    for (unsigned attempt = 0; attempt < 8; ++attempt) {
      try { token = random_(); }
      catch (...) { throw PageFailure("resource_limit"); }
      if (!PageRequest::token(token)) throw PageFailure("resource_limit");
      if (!cursors_.count(token)) break;
      token.clear();
    }
    if (token.empty()) throw PageFailure("resource_limit");
    if (cursors_.size() == 1024) {
      // Generation order, then ascending offset: reuse never changes eviction.
      const auto oldest = positions_.begin(); cursors_.erase(oldest->second); positions_.erase(oldest);
    }
    cursors_.emplace(token, position); positions_.emplace(position, token); return token;
  }
  static Json reply(const std::string &id, const Json &result) {
    return {{"version", 1}, {"id", id}, {"ok", true}, {"result", result}};
  }
public:
  // The host provides its explicit OS random source; tests inject deterministic
  // tokens. Reusing a generation/offset does not consult the random source.
  explicit NativePages(std::function<std::string()> random) : random_(std::move(random)) {
    if (!random_) throw PageFailure("invalid_options");
  }
  NativePages(const NativePages &) = delete;
  NativePages &operator=(const NativePages &) = delete;

  std::size_t offset(const PageRequest &request, std::uint64_t generation, bool stale) const {
    if (request.limit < 1 || request.limit > 64) throw PageFailure("invalid_options");
    if (request.cursor && !PageRequest::token(*request.cursor)) throw PageFailure("invalid_cursor");
    if (!generation || generation < generation_) throw PageFailure("invalid_response");
    if (!request.cursor) {
      if (stale) throw PageFailure("stale_discovery");
      return 0;
    }
    const auto found = cursors_.find(*request.cursor);
    if (found == cursors_.end()) throw PageFailure("invalid_cursor");
    if (stale || found->second.first != generation) throw PageFailure("stale_discovery");
    return found->second.second;
  }

  Json page(const PageRequest &request, const std::string &id, const Json &characteristics,
            std::uint64_t generation, bool stale = false) {
    if (id.empty() || id.size() > 64 || !characteristics.is_array() || characteristics.size() > 1024 ||
        request.limit < 1 || request.limit > 64 || (request.cursor && !PageRequest::token(*request.cursor))) throw PageFailure("invalid_options");
    const auto first = offset(request, generation, stale);
    if (first > characteristics.size() || (request.cursor && first == characteristics.size())) throw PageFailure("invalid_response");
    Json result{{"generation", generation}, {"characteristics", Json::array()}, {"cursor", nullptr}};
    std::size_t next = first;
    for (; next < characteristics.size() && next - first < request.limit; ++next) {
      result["characteristics"].push_back(characteristics[next]);
      result["cursor"] = next + 1 < characteristics.size() ? Json(std::string(32, '0')) : Json();
      try { EncodedFrame::from(reply(id, result)); }
      catch (const InvalidFrame &) { result["characteristics"].erase(result["characteristics"].end() - 1); break; }
    }
    if (next == first && next < characteristics.size()) throw PageFailure("response_limit");
    result["cursor"] = next < characteristics.size() ? Json(issue(generation, next)) : Json();
    try { EncodedFrame::from(reply(id, result)); }
    catch (const InvalidFrame &) { throw PageFailure("response_limit"); }
    generation_ = generation; return result;
  }
  std::size_t retained_cursors() const { return cursors_.size(); }
};
} // namespace wotex::ble
