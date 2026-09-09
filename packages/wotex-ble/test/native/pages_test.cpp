// SPDX-License-Identifier: Apache-2.0
#include "pages.hpp"
#include <iomanip>
#include <iostream>
#include <sstream>

using namespace wotex::ble;
static void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native pages assertion at line " + std::to_string(line));
}
#define CHECK(value) verify((value), __LINE__)
template<class Function> static std::string error(Function function) {
  try { function(); } catch (const PageFailure &failure) { return failure.what(); }
  return {};
}
static std::string token(std::uint64_t counter) {
  std::ostringstream result; result << std::hex << std::setw(32) << std::setfill('0') << counter; return result.str();
}
static Json characteristic(unsigned index) {
  return {{"service_uuid", "0000180f-0000-1000-8000-00805f9b34fb"},
    {"characteristic_uuid", "00002a19-0000-1000-8000-00805f9b34fb"}, {"service_path", "/org/bluez/hci0/device/service"},
    {"object_path", "/org/bluez/hci0/device/service/char" + std::to_string(index)},
    {"handle", index + 1}, {"flags", {"read", "notify"}}, {"generation", 1}};
}
static Json snapshot(unsigned count) {
  Json result = Json::array(); for (unsigned i = 0; i < count; ++i) result.push_back(characteristic(i)); return result;
}
static Json envelope(const std::string &id, const Json &result) {
  return {{"version", 1}, {"id", id}, {"ok", true}, {"result", result}};
}
struct Fixture {
  std::uint64_t issued = 0;
  NativePages pages{[&] { return token(++issued); }};
  Json page(const Json &parameters, const Json &values, std::uint64_t generation = 1, bool stale = false) {
    return pages.page(PageRequest::from(parameters), "2", values, generation, stale);
  }
};
static void boundaries() {
  Fixture f; const auto values = snapshot(4);
  for (const Json &invalid : {Json(), Json::array(), Json{{"extra", true}}, Json{{"limit", 0}}, Json{{"limit", 65}},
      Json{{"limit", 1.5}}, Json{{"limit", true}}, Json{{"limit", "1"}}})
    CHECK(error([&] { f.page(invalid, values); }) == "invalid_options");
  for (const Json &invalid : {Json(""), Json(std::string(32, 'A')), Json(std::string(31, 'a')), Json(true), Json(1), Json::object()})
    CHECK(error([&] { f.page({{"cursor", invalid}}, values); }) == "invalid_cursor");
  CHECK(error([&] { NativePages invalid({}); }) == "invalid_options");
  CHECK(error([&] { f.pages.offset({std::nullopt, 0}, 1, false); }) == "invalid_options");
  CHECK(error([&] { f.pages.offset({std::string("forged"), 1}, 1, false); }) == "invalid_cursor");
  CHECK(error([&] { f.page(Json::object(), values, 0); }) == "invalid_response");
  CHECK(error([&] { f.page(Json::object(), values, 1, true); }) == "stale_discovery");
  CHECK(error([&] { f.page({{"cursor", token(88)}}, values, 1, true); }) == "invalid_cursor");
  auto first = f.page({{"limit", 1}}, values); CHECK(first.at("cursor") == token(1));
  auto same = f.page({{"limit", 1}}, values); CHECK(same == first && f.issued == 1);
  CHECK(error([&] { f.page({{"cursor", token(1)}}, snapshot(1)); }) == "invalid_response");
  CHECK(error([&] { f.page({{"cursor", token(1)}}, values, 1, true); }) == "stale_discovery");
  CHECK(error([&] { f.page({{"cursor", token(1)}}, values, 2); }) == "stale_discovery");
  f.page(Json::object(), values, 2);
  CHECK(error([&] { f.page(Json::object(), values, 1); }) == "invalid_response");
  CHECK(error([&] { f.pages.page(PageRequest::from(Json::object()), "", values, 2); }) == "invalid_options");
  CHECK(error([&] { f.page(Json::object(), Json::object(), 2); }) == "invalid_options");
  CHECK(error([&] { f.page(Json::object(), snapshot(1025), 2); }) == "invalid_options");
  CHECK(f.page(Json::object(), Json::array(), UINT64_MAX).at("cursor").is_null());
  CHECK(error([&] { f.page(Json::object(), values, UINT64_MAX - 1); }) == "invalid_response");
  std::cout << "native page boundaries passed\n";
}
static void ordering() {
  Fixture f; const auto values = snapshot(1024); Json cursor; Json joined = Json::array();
  do {
    const auto page = f.page({{"cursor", cursor}}, values); cursor = page.at("cursor");
    CHECK(page.at("generation") == 1 && page.at("characteristics").size() == 64);
    for (const auto &item : page.at("characteristics")) joined.push_back(item);
  } while (!cursor.is_null());
  CHECK(joined == values && f.issued == 15 && f.pages.retained_cursors() == 15);
  CHECK(f.page(Json::object(), snapshot(1)).at("cursor").is_null());
  std::cout << "native page ordering passed\n";
}
static void limits() {
  Fixture f; auto values = snapshot(64);
  for (auto &item : values) {
    item["service_path"] = "/" + std::string(4095, 's'); item["object_path"] = "/" + std::string(4095, 'c');
    item["flags"] = Json::array();
    for (unsigned i = 0; i < 64; ++i) item["flags"].push_back(std::to_string(i) + std::string(62, 'f'));
  }
  Json cursor; unsigned count = 0;
  do {
    const auto page = f.page({{"cursor", cursor}}, values); cursor = page.at("cursor");
    CHECK(!page.at("characteristics").empty() && page.at("characteristics").size() < 64);
    const auto encoded = EncodedFrame::from(envelope("2", page)); CHECK(encoded.size() <= max_line);
    count += page.at("characteristics").size();
  } while (!cursor.is_null());
  CHECK(count == 64);
  Fixture nodes; auto many = snapshot(64);
  for (auto &item : many) { item["flags"] = Json::array(); for (unsigned i = 0; i < 64; ++i) item["flags"].push_back(std::to_string(i)); }
  const auto page = nodes.page(Json::object(), many);
  CHECK(page.at("characteristics").size() < 64 && !page.at("cursor").is_null());
  Fixture oversized; auto invalid = snapshot(2); invalid[0]["object_path"] = std::string(max_line, 'x');
  CHECK(error([&] { oversized.page(Json::object(), invalid); }) == "response_limit");
  CHECK(!oversized.issued && !oversized.pages.retained_cursors());
  Fixture invalid_id; CHECK(error([&] { invalid_id.pages.page(PageRequest::from(Json::object()), std::string("\xff"), snapshot(2), 1); }) == "response_limit");
  CHECK(!invalid_id.issued);
  std::cout << "native page aggregate limits passed\n";
}
static void ledger() {
  Fixture f; const auto values = snapshot(1024); Json cursor;
  for (unsigned i = 0; i < 1023; ++i) cursor = f.page({{"cursor", cursor}, {"limit", 1}}, values).at("cursor");
  CHECK(f.issued == 1023 && f.pages.retained_cursors() == 1023);
  CHECK(f.page({{"cursor", cursor}, {"limit", 1}}, values).at("cursor").is_null());
  auto current = f.page({{"limit", 1}}, values, 2).at("cursor");
  CHECK(current == token(1024) && f.pages.retained_cursors() == 1024);
  CHECK(error([&] { f.page({{"cursor", token(1)}}, values, 2); }) == "stale_discovery");
  const auto next = f.page({{"cursor", current}, {"limit", 1}}, values, 2).at("cursor");
  CHECK(next == token(1025) && f.pages.retained_cursors() == 1024);
  CHECK(error([&] { f.page({{"cursor", token(1)}}, values, 2); }) == "invalid_cursor");
  CHECK(error([&] { f.page({{"cursor", token(2)}}, values, 2); }) == "stale_discovery");
  CHECK(f.page({{"cursor", current}, {"limit", 1}}, values, 2).at("cursor") == next && f.issued == 1025);
  for (std::uint64_t generation = 3; generation <= 2000; ++generation) {
    const auto page = f.page({{"limit", 1}}, values, generation);
    CHECK(page.at("cursor") == token(generation + 1023) && f.pages.retained_cursors() == 1024);
  }
  Fixture foreign; CHECK(error([&] { foreign.page({{"cursor", token(3023)}}, values, 2000); }) == "invalid_cursor");
  std::cout << "native page bounded ledger passed\n";
}
static void random_failures() {
  unsigned attempts = 0;
  NativePages collision([&] { ++attempts; return token(1); }); const auto values = snapshot(3);
  const auto first = collision.page(PageRequest::from({{"limit", 1}}), "2", values, 1);
  CHECK(first.at("cursor") == token(1) && attempts == 1);
  CHECK(error([&] { collision.page(PageRequest::from({{"limit", 1}, {"cursor", token(1)}}), "2", values, 1); }) == "resource_limit");
  CHECK(attempts == 9 && collision.retained_cursors() == 1);
  NativePages invalid([] { return "private diagnostic"; });
  CHECK(error([&] { invalid.page(PageRequest::from({{"limit", 1}}), "2", values, 1); }) == "resource_limit");
  NativePages failing([]() -> std::string { throw std::runtime_error("private diagnostic"); });
  CHECK(error([&] { failing.page(PageRequest::from({{"limit", 1}}), "2", values, 1); }) == "resource_limit");
  CHECK(!invalid.retained_cursors() && !failing.retained_cursors());
  std::uint64_t issued = 0; bool unavailable = false;
  NativePages full([&]() -> std::string { if (unavailable) throw std::runtime_error("private diagnostic"); return token(++issued); });
  const auto request = PageRequest::from({{"limit", 1}});
  for (std::uint64_t generation = 1; generation <= 1024; ++generation) full.page(request, "2", values, generation);
  unavailable = true;
  CHECK(error([&] { full.page(request, "2", values, 1025); }) == "resource_limit");
  CHECK(full.retained_cursors() == 1024 && issued == 1024);
  CHECK(error([&] { full.offset(PageRequest::from({{"cursor", token(1)}}), 1025, false); }) == "stale_discovery");
  std::cout << "native page random source failures passed\n";
}
static Json trace(const Json &input) {
  CHECK(fields(input, {"characteristics", "events"}) && input.at("characteristics").is_array() && input.at("events").is_array());
  Fixture f; Json results = Json::array(); std::map<std::string, Json> named;
  for (const auto &event : input.at("events")) {
    CHECK(fields(event, {"name", "parameters", "generation", "stale"}) && event.at("name").is_string());
    auto parameters = event.at("parameters");
    if (parameters.contains("cursor") && parameters.at("cursor").is_object()) {
      const auto &reference = parameters.at("cursor"); CHECK(fields(reference, {"result"}));
      parameters["cursor"] = named.at(reference.at("result").get<std::string>()).at("cursor");
    }
    Json result;
    try { result = f.page(parameters, input.at("characteristics"), event.at("generation").get<std::uint64_t>(), event.at("stale").get<bool>()); }
    catch (const PageFailure &failure) { result = {{"error", failure.what()}}; }
    named[event.at("name").get<std::string>()] = result; results.push_back(result);
  }
  return {{"results", results}, {"retained", f.pages.retained_cursors()}, {"random_calls", f.issued}};
}
static Json ledger_trace(const Json &input) {
  CHECK(fields(input, {"characteristics", "generations", "queries"}) && input.at("characteristics").is_array() &&
    input.at("characteristics").size() == 2 && integer(input.at("generations"), 1, 10000) && input.at("queries").is_array());
  Fixture f; const auto generation = input.at("generations").get<std::uint64_t>();
  auto values = input.at("characteristics");
  for (std::uint64_t current = 1; current <= generation; ++current) {
    for (auto &value : values) value["generation"] = current;
    f.page({{"limit", 1}}, values, current);
  }
  Json results = Json::array();
  for (const auto &query : input.at("queries")) {
    CHECK(fields(query, {"cursor", "stale"}) && query.at("stale").is_boolean());
    try {
      results.push_back({{"offset", f.pages.offset(PageRequest::from({{"cursor", query.at("cursor")}}), generation, query.at("stale").get<bool>())}});
    } catch (const PageFailure &failure) { results.push_back({{"error", failure.what()}}); }
  }
  return {{"results", results}, {"retained", f.pages.retained_cursors()}, {"random_calls", f.issued}};
}
int main(int argc, char **argv) {
  try {
    if (argc == 3 && std::string(argv[1]) == "--page-input") {
      std::cout << trace(parse_line(std::string(argv[2]) + "\n")).dump() << '\n'; return 0;
    }
    if (argc == 3 && std::string(argv[1]) == "--ledger-input") {
      std::cout << ledger_trace(parse_line(std::string(argv[2]) + "\n")).dump() << '\n'; return 0;
    }
    if (argc != 2) return 2;
    const std::string operation = argv[1];
    if (operation == "boundaries") boundaries();
    else if (operation == "ordering") ordering();
    else if (operation == "limits") limits();
    else if (operation == "ledger") ledger();
    else if (operation == "random") random_failures();
    else return 2;
    return 0;
  } catch (const std::exception &failure) { std::cerr << failure.what() << '\n'; return 1; }
}
