#include "protocol.hpp"
#include <cstdlib>
#include <iostream>
#include <random>
#include <string>

using namespace wotex::thread;

static void check(bool value) {
  if (!value) std::abort();
}
static void rejects(const std::string &bytes) {
  try { (void)parse_line(bytes); std::abort(); }
  catch (const ProtocolError &error) { check(std::string(error.what()) == "invalid_bridge_message"); }
}
static void rejects_request(const Json &input) {
  try { (void)request(input); std::abort(); }
  catch (const ProtocolError &) {}
}
int main() {
  // WTH-C07/WTH-V04: scalar identity, UTF-8 and exact envelopes.
  const Json base = {{"version", 1}, {"id", "opaque-id"}, {"operation", "inspect"},
                     {"parameters", Json::object()}, {"timeout_ms", 5000}};
  auto value = request(parse_line(base.dump() + "\n"));
  check(value.id == "opaque-id" && value.operation == "inspect" && value.timeout_ms == 5000);
  check(success(value, nullptr).at("result").is_null());
  check(success(value, false).at("result") == false);
  check(success(value, 0).at("result") == 0);
  check(failure(value, "invalid_state").at("error").at("code") == "invalid_state");
  check(ready().at("revision") == kRevision);
  check(parse_line("\"é\"\n") == "é");
  check(parse_line("18446744073709551615\n").get<std::uint64_t>() == UINT64_MAX);

  for (const auto &bytes : {"", "{}", "{}\n{}\n", "{}\n\n", "{\"a\":1,\"a\":2}\n",
                           "{\"a\":1,\"\\u0061\":2}\n", "{\"x\":{\"a\":1,\"a\":2}}\n",
                           "[NaN]\n", "[Infinity]\n", "1e1000\n", "[1,]\n", "//comment\n"}) rejects(bytes);
  rejects(std::string("\"") + char(255) + "\"\n");
  check(parse_line(std::string(kMaximumLine - 3, 'x').insert(0, "\"") + "\"\n").is_string());
  rejects(std::string(kMaximumLine - 2, 'x').insert(0, "\"") + "\"\n");

  // WTH-C07/WTH-V04: depth, per-collection and aggregate limits are independent.
  std::string depth = "0";
  for (std::size_t i = 0; i < kMaximumDepth; ++i) depth = "[" + depth + "]";
  check(parse_line(depth + "\n").is_array());
  rejects("[" + depth + "]\n");
  Json array = Json::array(), object = Json::object();
  for (std::size_t i = 0; i < kMaximumCollection; ++i) {
    array.push_back(0); object[std::to_string(i)] = 0;
  }
  check(parse_line(array.dump() + "\n").size() == kMaximumCollection);
  check(parse_line(object.dump() + "\n").size() == kMaximumCollection);
  array.push_back(0); object["overflow"] = 0;
  rejects(array.dump() + "\n"); rejects(object.dump() + "\n");
  array.erase(array.end() - 1);
  Json aggregate = Json::array({array, array, array, array});
  rejects(aggregate.dump() + "\n");
  aggregate[3].erase(aggregate[3].end() - 5, aggregate[3].end());
  check(parse_line(aggregate.dump() + "\n").is_array());

  for (const auto &key : {"version", "id", "operation", "parameters", "timeout_ms"}) {
    auto missing = base; missing.erase(key); rejects_request(missing);
  }
  auto extra = base; extra["extra"] = "private-canary"; rejects_request(extra);
  for (const Json &timeout : {Json(0), Json(60001), Json(true), Json(1.5), Json("1000"), Json(UINT64_MAX)}) {
    auto bad = base; bad["timeout_ms"] = timeout; rejects_request(bad);
  }
  for (const Json &version : {Json(true), Json(1.0), Json(2), Json(nullptr)}) {
    auto bad = base; bad["version"] = version; rejects_request(bad);
  }
  for (const Json &id : {Json(""), Json(std::string(129, 'x')), Json(1), Json(std::string("a\0b", 3))}) {
    auto bad = base; bad["id"] = id; rejects_request(bad);
  }
  auto bad = base; bad["parameters"] = Json::array(); rejects_request(bad);
  bad = base; bad["operation"] = std::string(65, 'x'); rejects_request(bad);
  rejects_request(nullptr);
  // WTH-C07/WTH-V04: deterministic malformed-byte stress under native sanitizers.
  std::mt19937 generator(0x575448);
  for (std::size_t iteration = 0; iteration < 10000; ++iteration) {
    std::string bytes(generator() % 256, '\0');
    for (char &byte : bytes) byte = static_cast<char>(generator() & 0xff);
    bytes.push_back('\n');
    try { (void)parse_line(bytes); } catch (const ProtocolError &) {}
  }
  std::cout << "WTH-C07 WTH-V04 bounded JSON and request envelope checks passed\n";
}
