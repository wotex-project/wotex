// SPDX-License-Identifier: Apache-2.0
// Independent revision-1 process peer. It imports no production framing or owner.
#include "../../priv/bluez/native/vendor/json.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <map>
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
  const bool streaming = mode.find("stream") == 0;
  struct Stream {
    std::uint64_t route, credit, published = 0, acknowledged = 0;
    bool retired = false;
  };
  std::map<std::string, Stream> streams;
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
  const auto report = [&](const std::string &id, Stream &stream) {
    const auto sequence = ++stream.published;
    emit({{"version", 1},
          {"generation", mode == "stream-stale" ? generation + 1 : generation},
          {"stream_version", 1},
          {"event", "notification"},
          {"subscription_id", mode == "stream-foreign" ? "999" : id},
          {"route", stream.route},
          {"sequence", mode == "stream-gap" ? sequence + 1 : sequence},
          {"value",
           {{"type", "bytes"},
            {"base64",
             mode == "stream-empty"          ? ""
                 : mode == "stream-oversize" ? std::string(684, 'A')
                                             : "AP8="}}}});
  };
  std::string line;
  while (std::getline(std::cin, line)) {
    trace << line << '\n' << std::flush;
    const auto input = Json::parse(line);
    // Test-only control releases a held write through the actual protocol pipe.
    if (input.size() == 1 && input.value("fixture", "") == "release") {
      if (active.empty()) return 65;
      reply(active, nullptr);
      active.clear();
      continue;
    }
    if (input.contains("event")) {
      const auto id = input.at("subscription_id").get<std::string>();
      const auto sequence = input.at("sequence").get<std::uint64_t>();
      const auto found = streams.find(id);
      if (input.size() != 6 || input.at("event") != "notification_ack" ||
          input.at("version") != 1 || input.at("stream_version") != 1 ||
          input.at("generation") != generation || found == streams.end() ||
          sequence < found->second.acknowledged || sequence > found->second.published)
        return 65;
      auto &stream = found->second;
      stream.acknowledged = sequence;
      if (mode == "stream-refill" && !stream.retired)
        while (stream.published < 128 && stream.published - stream.acknowledged < stream.credit)
          report(id, stream);
      continue;
    }
    const auto id = input.at("id").get<std::string>();
    const auto op = input.at("operation").get<std::string>();
    if (op == "open") {
      generation = input.at("parameters").at("generation").get<std::uint64_t>();
      reply(id, {{"generation", generation}});
    } else if (op == "discover") {
      ++discoveries;
      Json records = Json::array();
      for (unsigned int i = 1, count = mode == "stream-capacity" ? 256 : 3; i <= count; ++i)
        records.push_back({{"route", mode == "bad-discovery" ? 0 : i},
                           {"service_uuid", "0000181a-0000-1000-8000-00805f9b34fb"},
                           {"characteristic_uuid",
                            i == 3 ? "00002a19-0000-1000-8000-00805f9b34fb"
                                   : "00002a6e-0000-1000-8000-00805f9b34fb"},
                           {"read", mode != "command-only"},
                           {"write", mode != "command-only"},
                           {"write_without_response", true},
                           {"notify", streaming},
                           {"indicate", streaming && i == 2}});
      if (mode == "changed-discovery" && discoveries > 1) records.erase(2);
      reply(id, {{"characteristics", records}});
    } else if (op == "subscribe" && streaming) {
      const auto &parameters = input.at("parameters");
      auto &stream = streams
                         .emplace(id,
                                  Stream{parameters.at("address").at("route").get<std::uint64_t>(),
                                         parameters.at("credit").get<std::uint64_t>()})
                         .first->second;
      if (mode == "stream-hold") {
        active = id;
        continue;
      }
      if (mode == "stream-early") report(id, stream);
      reply(id,
            {{"stream_version", 1},
             {"subscription_id", mode == "stream-bad-binding" ? "999" : id},
             {"route", stream.route},
             {"requested_mode", parameters.at("mode")},
             {"effective_mode", "notify"},
             {"credit", stream.credit}});
      if (mode != "stream-silent" && mode != "stream-capacity")
        for (std::uint64_t i = 0,
                           count = mode == "stream-over-credit"
                 ? stream.credit + 1
                 : std::min(std::uint64_t(3), stream.credit);
             i < count; ++i)
          report(id, stream);
    } else if (op == "unsubscribe" && streaming) {
      const auto subscription = input.at("parameters").at("subscription_id").get<std::string>();
      auto &stream = streams.at(subscription);
      if (mode == "stream-hold-stop") {
        active = id;
        submitted = false;
        continue;
      }
      stream.retired = true;
      if (mode != "stream-no-retire")
        emit({{"version", 1},
              {"generation", generation},
              {"stream_version", 1},
              {"event", "notification_retired"},
              {"subscription_id", subscription},
              {"route", stream.route},
              {"last_sequence",
               mode == "stream-bad-retire" ? stream.published + 1 : stream.published}});
      reply(id, nullptr);
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
      if (mode == "hold" || mode == "hold-close" || mode == "stream-point-hold") continue;
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
