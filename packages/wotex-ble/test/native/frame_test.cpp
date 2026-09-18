// SPDX-License-Identifier: Apache-2.0
#include "frame.hpp"
#include <cstdlib>
#include <iostream>

using namespace wotex::ble;
static void check(bool ok) { if (!ok) std::abort(); }
template <typename F> static void rejects(F run) {
  try { run(); } catch (const InvalidFrame &) { return; }
  std::abort();
}
static Json command(std::string id, std::string op = "health") {
  return {{"version", 1}, {"id", id}, {"operation", op},
          {"parameters", Json::object()}, {"timeout_ms", 1000}};
}
static void invariants() {
  check(parse_line("18446744073709551615\n").get<std::uint64_t>() == UINT64_MAX);
  check(parse_line("-9223372036854775808\n").get<std::int64_t>() == INT64_MIN);
  for (const char *line : {"18446744073709551616\n", "-9223372036854775809\n",
       "1e400\n", "NaN\n", "{}", "{}\n{}\n", "{\"x\":1,\"x\":2}\n",
       "{\"x\":1,\"\\u0078\":2}\n", "\"\\ud800\"\n", "\"\xc0\xaf\"\n"}) {
    rejects([&] { parse_line(line); });
  }
  check(parse_line("1.25\n") == 1.25);
  check(parse_line("\"\\ud83d\\ude80\"\n") == "\xf0\x9f\x9a\x80");
  check(parse_line(std::string(7, '[') + "1" + std::string(7, ']') + "\n").is_array());
  rejects([] { parse_line(std::string(8, '[') + "1" + std::string(8, ']') + "\n"); });
  Json array = Json::array();
  for (int i = 0; i < 1024; ++i) array.push_back(i);
  check(parse_line(array.dump() + "\n").size() == 1024);
  array.push_back(0);
  rejects([&] { parse_line(array.dump() + "\n"); });
  Json object = Json::object();
  for (int i = 0; i < 1024; ++i) object[std::to_string(i)] = i;
  check(parse_line(object.dump() + "\n").size() == 1024);
  object["excess"] = 0;
  rejects([&] { parse_line(object.dump() + "\n"); });
  Json aggregate = Json::array();
  for (int i = 0; i < 4; ++i) aggregate.push_back(Json::array());
  for (int i = 0; i < 4091; ++i) aggregate[i % 4].push_back(0);
  check(parse_line(aggregate.dump() + "\n").size() == 4);
  aggregate[0].push_back(0);
  rejects([&] { parse_line(aggregate.dump() + "\n"); });
  check(parse_line("\"" + std::string(max_line - 3, 'a') + "\"\n").is_string());
  rejects([] { parse_line("\"" + std::string(max_line - 2, 'a') + "\"\n"); });
  auto value = command("1");
  check(request(value));
  value["version"] = true; check(!request(value));
  value = command("1"); value["timeout_ms"] = 60001; check(!request(value));
  value = command("1"); value["timeout_ms"] = -1; check(!request(value));
  value = command("1"); value["parameters"] = nullptr; check(!request(value));
  value = command(std::string(65, 'a')); check(!request(value));
  Sequence ids;
  check(!ids.accept(command("1")));
  check(ids.accept(command("open", "open")));
  check(!ids.accept(command("open", "open")));
  for (std::uint64_t i = 1; i <= 100000; ++i) check(ids.accept(command(std::to_string(i))));
  for (const char *id : {"100000", "01", "-1", "+100001", "1.0", "agent-100001"})
    check(!ids.accept(command(id)));
  check(ids.accept(command("agent-100001", "agent_reply")));
  check(!ids.accept(command("100002", "agent_reply")));
  check(ids.accept(command("18446744073709551615")));
  check(!ids.accept(command("18446744073709551616")));
  check(ids.accept(command("close", "close")));
  const auto line = command("1").dump() + "\n";
  for (std::size_t at = 0; at <= line.size(); ++at) {
    Lines decoder; unsigned count = 0;
    auto consume = [&](std::string_view input) { check(request(parse_line(input))); ++count; };
    decoder.feed(std::string_view(line).substr(0, at), consume);
    decoder.feed(std::string_view(line).substr(at), consume);
    decoder.eof(); check(count == 1 && decoder.buffered() == 0);
  }
  Lines decoder; unsigned count = 0;
  decoder.feed(line + line, [&](std::string_view v) { check(request(parse_line(v))); ++count; });
  check(count == 2); decoder.eof();
  Lines incomplete; incomplete.feed("{", [](auto) {}); rejects([&] { incomplete.eof(); });
  Lines oversized;
  rejects([&] { oversized.feed(std::string(max_line, ' '), [](auto) {}); });
  rejects([&] { oversized.feed(line, [](auto) {}); });
  Lines broken;
  rejects([&] { broken.feed("{}\n", [](auto) { throw InvalidFrame(); }); });
  rejects([&] { broken.eof(); });
}
int main(int argc, char **argv) {
  if (argc == 3 && std::string(argv[1]) == "--parse-request") {
    bool accepted = false;
    // NOLINTNEXTLINE(bugprone-empty-catch): a rejected request leaves accepted false
    try { accepted = request(parse_line(argv[2])); } catch (const InvalidFrame &) {}
    std::cout << Json({{"accepted", accepted}}).dump() << '\n';
    return 0;
  }
  if (argc != 1) return 2;
  invariants();
  std::cout << "native frame invariants passed\n";
}
