// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "notify_value.hpp"
#include "objects_test.hpp"

namespace notify_value_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("notification value assertion at line " + std::to_string(line));
}
#define NOTIFY_VALUE_CHECK(value) ::notify_value_test::verify((value), __LINE__)
inline Json projection(const Json &input) {
  NOTIFY_VALUE_CHECK(fields(input, {"flags", "mode"}));
  try {
    const auto result = NotifyMode::from(input.at("flags"), input.at("mode"));
    return {{"requested_mode", result.requested()}, {"effective_mode", result.effective()}};
  } catch (const InvalidObjects &error) { return {{"error", error.what()}}; }
}
inline void invariants() {
  // WBL-V07: BlueZ chooses the ATT procedure for a dual-mode characteristic.
  for (const auto &flags : {Json::array(), Json::array({"notify"}), Json::array({"indicate"}), Json::array({"notify", "indicate"})}) {
    for (const std::string mode : {"auto", "notify", "indicate"}) {
      const auto result = projection({{"flags", flags}, {"mode", mode}});
      if (flags.size() == 2 && mode != "auto") NOTIFY_VALUE_CHECK(result == Json({{"error", "unsupported_procedure_selection"}}));
      else if (flags.size() == 2) NOTIFY_VALUE_CHECK(result.at("effective_mode") == "bluez_selected");
      else if (flags.empty() || (mode != "auto" && mode != flags[0])) NOTIFY_VALUE_CHECK(result == Json({{"error", "not_supported"}}));
      else NOTIFY_VALUE_CHECK(result.at("requested_mode") == mode && result.at("effective_mode") == flags[0]);
    }
  }
  for (const auto &mode : {Json(), Json(true), Json(1), Json("Notify"), Json("unsupported")})
    NOTIFY_VALUE_CHECK(projection({{"flags", Json::array({"notify"})}, {"mode", mode}}) == Json({{"error", "invalid_options"}}));
  for (const auto &flags : {Json(), Json(true), Json::array({1}), Json::array({""}), Json::array({"notify", "notify"}),
      Json::array({std::string(65, 'a')}), Json::array({std::string("a\0b", 3)})})
    NOTIFY_VALUE_CHECK(projection({{"flags", flags}, {"mode", "auto"}}) == Json({{"error", "invalid_characteristic"}}));
  Json flags = Json::array({"notify"});
  for (unsigned index = 1; index < 64; ++index) flags.push_back("unknown-" + std::to_string(index));
  NOTIFY_VALUE_CHECK(projection({{"flags", flags}, {"mode", "auto"}}).at("effective_mode") == "notify");
  flags.push_back("excess"); NOTIFY_VALUE_CHECK(projection({{"flags", flags}, {"mode", "auto"}}) == Json({{"error", "invalid_characteristic"}}));

  // WBL-V08: every typed Value is distinct, including repeated equal bytes.
  for (const std::size_t size : {0U, 1U, 2U, 255U, 256U, 512U}) {
    Json bytes = Json::array(); for (std::size_t index = 0; index < size; ++index) bytes.push_back(index % 256);
    auto message = object_test::changed_message({{"Value", "ay", bytes}, {"Notifying", "b", true}, {"Unknown", "s", "future"}}, {}, characteristic_interface);
    const auto first = GattChange::from(message.get()), repeated = GattChange::from(message.get());
    NOTIFY_VALUE_CHECK(first.value() && first.value()->value() == bytes.get<std::vector<unsigned char>>() &&
      repeated.value() && repeated.value()->value() == first.value()->value() && first.notifying() && *first.notifying() &&
      first.metadata().values.empty() && first.metadata().invalidated.empty());
    message.reset(); NOTIFY_VALUE_CHECK(first.value()->value().size() == size);
  }
  const std::vector<std::vector<object_test::Property>> invalid{
    {{"Value", "s", "AQ=="}}, {{"Value", "as", Json::array()}}, {{"Notifying", "u", 0}},
    {{"Value", "ay", Json::array()}, {"Value", "ay", Json::array()}},
    {{"Value", "ay", std::vector<unsigned char>(513, 1)}}};
  for (const auto &properties : invalid) {
    auto message = object_test::changed_message(properties, {}, characteristic_interface); bool failed = false;
    try { GattChange::from(message.get()); } catch (const InvalidObjects &) { failed = true; }
    NOTIFY_VALUE_CHECK(failed);
  }
  {
    auto message = object_test::changed_message({{"Notifying", "b", false}}, {"Value"}, characteristic_interface);
    const auto result = GattChange::from(message.get());
    NOTIFY_VALUE_CHECK(!result.value() && result.notifying() && !*result.notifying() && result.metadata().invalidated.count("Value"));
  }
  {
    auto message = object_test::changed_message({{"Value", "s", "unrelated"}}, {}, device_interface);
    const auto result = GattChange::from(message.get());
    NOTIFY_VALUE_CHECK(!result.value() && !result.notifying() && result.metadata().values.empty());
  }
  {
    auto message = object_test::changed_message({{"Handle", "q", 17}}, {"Notifying"}, characteristic_interface);
    const auto result = GattChange::from(message.get());
    NOTIFY_VALUE_CHECK(!result.value() && result.metadata().values == Json({{"Handle", 17}}) && result.metadata().invalidated.count("Notifying"));
  }
}
} // namespace notify_value_test
