// SPDX-License-Identifier: Apache-2.0
// Independent archive peer: JSON syntax only, no production protocol helpers.
#include "extracted/wotex_ble/priv/bluez/native/vendor/json.hpp"
#include <csignal>
#include <fstream>
#include <iostream>
#include <map>
#include <string>
#include <unistd.h>

using Json = nlohmann::json;
static void emit(const Json &frame) { std::cout << frame.dump() << '\n' << std::flush; }
int main(int argc, char **argv) {
  if (argc != 1) return 64;
  std::signal(SIGPIPE, SIG_IGN);
  const std::string path = argv[0];
  std::string mode;
  std::ifstream(path + ".mode") >> mode;
  std::ofstream trace(path + ".trace");
  trace << Json({{"fixture_pid", getpid()}}).dump() << '\n' << std::flush;
  emit({{"version", 1},
        {"event", "ready"},
        {"backend", mode == "bad-ready" ? "wrong" : "corebluetooth-native"},
        {"revision", "1"}});
  std::uint64_t generation = 0;
  std::string pending;
  bool submitted = false;
  struct Stream {
    std::uint64_t route, sequence = 0, acknowledged = 0;
    bool retired = false;
  };
  std::map<std::string, Stream> streams;
  const auto reply = [&](const std::string &id, Json result) {
    emit({{"version", 1},
          {"generation", generation},
          {"id", id},
          {"ok", true},
          {"result", std::move(result)}});
  };
  const auto error = [&](const std::string &id, const char *code, bool sent, bool cleanup) {
    emit(
        {{"version", 1},
         {"generation", generation},
         {"id", id},
         {"ok", false},
         {"error",
          {{"code", code}, {"cause", code}, {"submitted", sent}, {"cleanup_confirmed", cleanup}}}});
  };
  std::string line;
  char byte = 0;
  while (std::cin.get(byte)) {
    if (line.size() == 131071 && byte != '\n') return 65;
    if (byte != '\n') {
      line.push_back(byte);
      continue;
    }
    const auto frame = Json::parse(line, nullptr, false);
    if (!frame.is_object()) return 65;
    trace << line << '\n' << std::flush;
    line.clear();
    if (frame.contains("event")) {
      if (frame.size() != 6 || frame.at("version") != 1 || frame.at("generation") != generation ||
          frame.at("stream_version") != 1 || frame.at("event") != "notification_ack" ||
          !frame.at("sequence").is_number_unsigned())
        return 65;
      const auto id = frame.at("subscription_id").get<std::string>();
      auto found = streams.find(id);
      if (found == streams.end()) return 65;
      const auto sequence = frame.at("sequence").get<std::uint64_t>();
      if (sequence < found->second.acknowledged || sequence > found->second.sequence) return 65;
      found->second.acknowledged = sequence;
      continue;
    }
    if (frame.size() != 5 || frame.at("version") != 1 || !frame.at("id").is_string() ||
        !frame.at("parameters").is_object() || !frame.at("timeout_ms").is_number_unsigned() ||
        frame.at("timeout_ms") < 1 || frame.at("timeout_ms") > 60000)
      return 65;
    const auto id = frame.at("id").get<std::string>();
    const auto operation = frame.at("operation").get<std::string>();
    const auto &parameters = frame.at("parameters");
    if (operation == "open") {
      if (id != "open" || generation || parameters.size() != 4 ||
          parameters.at("pairing") != "system")
        return 65;
      generation = parameters.at("generation").get<std::uint64_t>();
      reply(id, {{"generation", generation}});
    } else if (operation == "discover") {
      Json routes = Json::array();
      for (unsigned route = 1; route <= 3; ++route)
        routes.push_back({{"route", route},
                          {"service_uuid", "0000181a-0000-1000-8000-00805f9b34fb"},
                          {"characteristic_uuid",
                           route == 3 ? "00002a19-0000-1000-8000-00805f9b34fb"
                                      : "00002a6e-0000-1000-8000-00805f9b34fb"},
                          {"read", true},
                          {"write", true},
                          {"write_without_response", true},
                          {"notify", true},
                          {"indicate", route == 2}});
      reply(id, {{"characteristics", routes}});
    } else if (operation == "health") {
      reply(id, {{"connected", true}, {"services_resolved", true}});
    } else if (operation == "close") {
      if (!pending.empty()) error(pending, "disconnected", submitted, true);
      reply(id, nullptr);
      return 0;
    } else if (operation == "read" || operation == "write" || operation == "write_command") {
      const auto &address = parameters.at("address");
      if (address.size() != 2 || address.at("generation") != generation ||
          address.at("route") < 1 || address.at("route") > 3)
        return 65;
      if (operation == "read") {
        reply(id, {{"type", "bytes"}, {"base64", "AP8="}});
        continue;
      }
      if (parameters.size() != 2 || parameters.at("value").size() != 2 ||
          parameters.at("value").at("type") != "bytes")
        return 65;
      pending = id;
      submitted = mode != "missing-marker";
      if (submitted)
        emit(
            {{"version", 1}, {"generation", generation}, {"event", "write_submitted"}, {"id", id}});
      if (mode == "blocked") continue;
      if (mode == "post-error" || mode == "sleep-write")
        error(id, mode == "post-error" ? "not_permitted" : "disconnected", submitted,
              mode == "sleep-write");
      else if (operation == "write" || mode == "command-ack")
        reply(mode == "wrong-id" ? "999" : id, nullptr);
      else
        reply(mode == "wrong-id" ? "999" : id,
              {{"write_mode", "without_response"}, {"evidence", "native_queue_accepted"}});
      pending.clear();
      if (mode == "sleep-write") {
        emit({{"version", 1},
              {"generation", generation},
              {"event", "connection_lost"},
              {"code", "disconnected"}});
        return 1;
      }
    } else if (operation == "subscribe") {
      if (parameters.size() != 4 || parameters.at("stream_version") != 1 ||
          parameters.at("address").at("generation") != generation ||
          parameters.at("mode") == "indicate")
        return 65;
      const auto credit = parameters.at("credit").get<unsigned>();
      if (credit < 1 || credit > 64 || streams.size() >= 3) return 65;
      auto &stream = streams
                         .emplace(id,
                                  Stream{parameters.at("address").at("route").get<std::uint64_t>()})
                         .first->second;
      reply(id,
            {{"stream_version", 1},
             {"subscription_id", mode == "bad-binding" ? "999" : id},
             {"route", stream.route},
             {"requested_mode", parameters.at("mode")},
             {"effective_mode", "notify"},
             {"credit", credit}});
      if (mode != "silent")
        for (unsigned count = 0; count < std::min(3u, credit); ++count) {
          emit({{"version", 1},
                {"generation", generation},
                {"stream_version", 1},
                {"event", "notification"},
                {"subscription_id", id},
                {"route", stream.route},
                {"sequence", ++stream.sequence},
                {"value", {{"type", "bytes"}, {"base64", mode == "bad-value" ? "!" : "AP8="}}}});
        }
    } else if (operation == "unsubscribe") {
      const auto original = parameters.at("subscription_id").get<std::string>();
      auto &stream = streams.at(original);
      stream.retired = true;
      if (mode != "no-retire")
        emit({{"version", 1},
              {"generation", generation},
              {"stream_version", 1},
              {"event", "notification_retired"},
              {"subscription_id", original},
              {"route", stream.route},
              {"last_sequence", stream.sequence}});
      reply(id, nullptr);
    } else return 65;
  }
  return line.empty() ? 1 : 65;
}
