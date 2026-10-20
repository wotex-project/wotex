// SPDX-License-Identifier: Apache-2.0
// Independent revision-1 process peer. It imports no production framing or owner.
#include "../../priv/bluez/native/vendor/json.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>
#include <unistd.h>

using Json = nlohmann::json;
static void emit(const Json &value) { std::cout << value.dump() << '\n' << std::flush; }
int main(int argc, char **argv) {
  if (argc != 1) return 64;
  const std::string path = argv[0];
  std::string mode;
  std::ifstream(path + ".mode") >> mode;
  std::ofstream(path + ".pid") << getpid();
  std::ofstream trace(path + ".calls", std::ios::app);
  if (mode == "hold-start") std::this_thread::sleep_for(std::chrono::seconds(30));
  emit({{"version", 1},
        {"event", "ready"},
        {"backend", mode == "bad-ready" ? "other" : "corebluetooth-native"},
        {"revision", "1"}});
  std::uint64_t generation = 0;
  std::string active;
  bool submitted = false;
  unsigned int discoveries = 0;
  const auto reply = [&](const std::string &id, Json result) {
    emit({{"version", 1},
          {"generation", generation},
          {"id", id},
          {"ok", true},
          {"result", std::move(result)}});
  };
  const auto error = [&](const std::string &id, const std::string &code, bool sent, bool cleanup) {
    emit(
        {{"version", 1},
         {"generation", generation},
         {"id", id},
         {"ok", false},
         {"error",
          {{"code", code}, {"cause", "ok"}, {"submitted", sent}, {"cleanup_confirmed", cleanup}}}});
  };
  const auto marker = [&](const std::string &id) {
    emit({{"version", 1}, {"generation", generation}, {"event", "write_submitted"}, {"id", id}});
  };
  std::string line;
  while (std::getline(std::cin, line)) {
    trace << line << '\n' << std::flush;
    const auto input = Json::parse(line);
    const auto id = input.at("id").get<std::string>();
    const auto op = input.at("operation").get<std::string>();
    if (op == "open") {
      generation = input.at("parameters").at("generation").get<std::uint64_t>();
      reply(id, {{"generation", generation}});
    } else if (op == "discover") {
      ++discoveries;
      Json records = Json::array();
      for (unsigned int i = 1; i <= 3; ++i)
        records.push_back({{"route", mode == "bad-discovery" ? 0 : i},
                           {"service_uuid", "0000181a-0000-1000-8000-00805f9b34fb"},
                           {"characteristic_uuid",
                            i == 3 ? "00002a19-0000-1000-8000-00805f9b34fb"
                                   : "00002a6e-0000-1000-8000-00805f9b34fb"},
                           {"read", mode != "command-only"},
                           {"write", mode != "command-only"},
                           {"write_without_response", true},
                           {"notify", false},
                           {"indicate", false}});
      if (mode == "changed-discovery" && discoveries > 1) records.erase(2);
      reply(id, {{"characteristics", records}});
    } else if (op == "health") {
      reply(id, {{"connected", true}, {"services_resolved", true}});
    } else if (op == "close") {
      if (mode == "hold-close") continue;
      if (!active.empty()) error(active, "disconnected", submitted, true);
      if (mode == "unconfirmed-close") error(id, "cleanup_timeout", false, false);
      else reply(id, nullptr);
      return 0;
    } else if (op == "read" || op == "write" || op == "write_command") {
      active = id;
      submitted = false;
      if (mode == "lost-before-marker") return 70;
      if (mode == "refuse") {
        error(id, "not_permitted", false, false);
        active.clear();
        continue;
      }
      if (op != "read" && mode != "missing-marker") {
        marker(mode == "foreign-marker" ? "999" : id);
        submitted = true;
        if (mode == "double-marker") marker(id);
      }
      if (mode == "hold" || mode == "hold-close") continue;
      if (mode == "late") std::this_thread::sleep_for(std::chrono::milliseconds(80));
      if (mode == "post-error") error(id, "not_permitted", submitted, false);
      else if (op == "read") reply(id, {{"type", "bytes"}, {"base64", "AP8="}});
      else if (op == "write" || mode == "wrong-mode") reply(id, nullptr);
      else reply(id, {{"write_mode", "without_response"}, {"evidence", "native_queue_accepted"}});
      active.clear();
    } else return 65;
  }
  return 1;
}
