// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "objects.hpp"
#include <fcntl.h>
#include <unistd.h>

namespace object_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("object assertion failed at line " + std::to_string(line));
}
#define OBJECT_CHECK(value) ::object_test::verify((value), __LINE__)
struct Property { std::string name, signature; Json value; };
using Interface = std::pair<std::string, std::vector<Property>>;
using Object = std::pair<std::string, std::vector<Interface>>;

inline void append(DBusMessageIter &iterator, int type, const void *value) {
  OBJECT_CHECK(dbus_message_iter_append_basic(&iterator, type, value));
}
inline void string(DBusMessageIter &iterator, const std::string &value, int type = DBUS_TYPE_STRING) {
  const char *pointer = value.c_str(); append(iterator, type, &pointer);
}
inline void property(DBusMessageIter &iterator, const Property &property) {
  DBusMessageIter pair, variant;
  OBJECT_CHECK(dbus_message_iter_open_container(&iterator, DBUS_TYPE_DICT_ENTRY, nullptr, &pair));
  string(pair, property.name);
  OBJECT_CHECK(dbus_message_iter_open_container(&pair, DBUS_TYPE_VARIANT, property.signature.c_str(), &variant));
  if (property.signature == "s" || property.signature == "o") {
    string(variant, property.value, property.signature == "s" ? DBUS_TYPE_STRING : DBUS_TYPE_OBJECT_PATH);
  } else if (property.signature == "b") {
    dbus_bool_t value = property.value.get<bool>(); append(variant, DBUS_TYPE_BOOLEAN, &value);
  } else if (property.signature == "q") {
    dbus_uint16_t value = property.value.get<dbus_uint16_t>(); append(variant, DBUS_TYPE_UINT16, &value);
  } else if (property.signature == "u") {
    dbus_uint32_t value = property.value.get<dbus_uint32_t>(); append(variant, DBUS_TYPE_UINT32, &value);
  } else if (property.signature == "h") {
    int value = property.value.get<int>(); append(variant, DBUS_TYPE_UNIX_FD, &value);
  } else if (property.signature == "as") {
    DBusMessageIter array;
    OBJECT_CHECK(dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "s", &array));
    for (const auto &value : property.value) string(array, value);
    OBJECT_CHECK(dbus_message_iter_close_container(&variant, &array));
  } else if (property.signature == "ay") {
    DBusMessageIter array;
    OBJECT_CHECK(dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "y", &array));
    unsigned char value = 1; append(array, DBUS_TYPE_BYTE, &value);
    OBJECT_CHECK(dbus_message_iter_close_container(&variant, &array));
  } else throw std::runtime_error("unimplemented test value");
  OBJECT_CHECK(dbus_message_iter_close_container(&pair, &variant));
  OBJECT_CHECK(dbus_message_iter_close_container(&iterator, &pair));
}
inline Message message(const std::vector<Object> &objects) {
  Message result(dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN));
  OBJECT_CHECK(result != nullptr);
  DBusMessageIter root, array;
  dbus_message_iter_init_append(result.get(), &root);
  OBJECT_CHECK(dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "{oa{sa{sv}}}", &array));
  for (const auto &[path, interfaces] : objects) {
    DBusMessageIter object, interface_array;
    OBJECT_CHECK(dbus_message_iter_open_container(&array, DBUS_TYPE_DICT_ENTRY, nullptr, &object));
    string(object, path, DBUS_TYPE_OBJECT_PATH);
    OBJECT_CHECK(dbus_message_iter_open_container(&object, DBUS_TYPE_ARRAY, "{sa{sv}}", &interface_array));
    for (const auto &[name, properties] : interfaces) {
      DBusMessageIter interface, property_array;
      OBJECT_CHECK(dbus_message_iter_open_container(&interface_array, DBUS_TYPE_DICT_ENTRY, nullptr, &interface));
      string(interface, name);
      OBJECT_CHECK(dbus_message_iter_open_container(&interface, DBUS_TYPE_ARRAY, "{sv}", &property_array));
      for (const auto &value : properties) property(property_array, value);
      OBJECT_CHECK(dbus_message_iter_close_container(&interface, &property_array));
      OBJECT_CHECK(dbus_message_iter_close_container(&interface_array, &interface));
    }
    OBJECT_CHECK(dbus_message_iter_close_container(&object, &interface_array));
    OBJECT_CHECK(dbus_message_iter_close_container(&array, &object));
  }
  OBJECT_CHECK(dbus_message_iter_close_container(&root, &array));
  return result;
}
inline void rejects(const std::vector<Object> &objects, const std::string &reason) {
  auto input = message(objects); bool rejected = false;
  try { ObjectReader().read(input.get()); }
  catch (const InvalidObjects &error) { rejected = reason == error.what(); }
  OBJECT_CHECK(rejected);
}
inline void discovery_rejects(const std::vector<Object> &objects, const NativePeer &peer,
                               const std::string &reason) {
  auto input = message(objects); const auto snapshot = ObjectReader().read(input.get());
  bool rejected = false;
  try { discovery(snapshot, peer, 1); }
  catch (const InvalidObjects &error) { rejected = reason == error.what(); }
  OBJECT_CHECK(rejected);
}
inline const Json peer_fields{{"adapter", "/org/bluez/hci0"},
  {"address", "aa:bb:cc:dd:ee:ff"}, {"address_type", "random"}};
inline const std::vector<Object> baseline{
  {"/org/bluez/hci0", {{adapter_interface, {}}}},
  {"/org/bluez/hci0/device", {{device_interface, {
    {"Adapter", "o", "/org/bluez/hci0"}, {"Address", "s", "aa:bb:cc:dd:ee:ff"},
    {"AddressType", "s", "random"}, {"Connected", "b", true}, {"ServicesResolved", "b", true}}}}},
  {"/org/bluez/hci0/device/service", {{service_interface, {
    {"Device", "o", "/org/bluez/hci0/device"}, {"UUID", "s", "180F"}}}}},
  {"/org/bluez/hci0/device/service/char", {{characteristic_interface, {
    {"Service", "o", "/org/bluez/hci0/device/service"}, {"UUID", "s", "2A19"},
    {"Handle", "q", 17}, {"Flags", "as", Json::array({"read", "notify", "future-flag"})}}}}}
};
inline void invariants() {
  const auto peer = NativePeer::from(peer_fields);
  OBJECT_CHECK(peer.address == "AA:BB:CC:DD:EE:FF");
  auto input = message(baseline);
  auto objects = ObjectReader().read(input.get());
  const auto found = discovery(objects, peer, std::numeric_limits<std::uint64_t>::max());
  OBJECT_CHECK(found.device_path == "/org/bluez/hci0/device" && found.connected && found.services_resolved);
  const Json expected = Json::array({{
    {"service_uuid", "0000180f-0000-1000-8000-00805f9b34fb"},
    {"characteristic_uuid", "00002a19-0000-1000-8000-00805f9b34fb"},
    {"service_path", "/org/bluez/hci0/device/service"},
    {"object_path", "/org/bluez/hci0/device/service/char"}, {"handle", 17},
    {"flags", Json::array({"read", "notify", "future-flag"})},
    {"generation", std::numeric_limits<std::uint64_t>::max()}
  }});
  OBJECT_CHECK(found.characteristics == expected);

  auto unrelated = baseline;
  unrelated[2].second[0].second[0].value = "/org/bluez/hci0/device_other";
  input = message(unrelated);
  OBJECT_CHECK(discovery(ObjectReader().read(input.get()), peer, 1).characteristics.empty());
  unrelated = baseline;
  unrelated.push_back(unrelated[1]); unrelated.back().first = "/other_device";
  discovery_rejects(unrelated, peer, "ambiguous_peer");
  unrelated = baseline; unrelated.erase(unrelated.begin());
  discovery_rejects(unrelated, peer, "peer_not_found");
  unrelated = baseline; unrelated[1].second[0].second.pop_back();
  discovery_rejects(unrelated, peer, "invalid_response");

  auto changed = baseline;
  changed[3].second[0].second[2].signature = "u";
  rejects(changed, "invalid_response");
  changed = baseline; changed[1].second[0].second[0].signature = "s";
  rejects(changed, "invalid_response");
  changed = baseline; changed[1].second[0].second[3] = {"Connected", "q", 1};
  rejects(changed, "invalid_response");
  changed = baseline; changed[3].second[0].second[3] = {"Flags", "ay", Json::array({1})};
  rejects(changed, "invalid_response");
  changed = baseline; changed[3].second[0].second[2].value = 0;
  rejects(changed, "invalid_characteristic");
  changed = baseline; changed[3].second[0].second[3].value = Json::array({"read", "read"});
  rejects(changed, "invalid_characteristic");
  changed = baseline; changed[3].second[0].second[3].value = Json::array({std::string(65, 'x')});
  rejects(changed, "invalid_characteristic");
  changed = baseline; changed[3].second[0].second[3].value = Json::array({""});
  rejects(changed, "invalid_characteristic");
  changed = baseline; auto &flags = changed[3].second[0].second[3].value;
  flags = Json::array();
  for (unsigned i = 0; i < 64; ++i) flags.push_back("flag_" + std::to_string(i));
  input = message(changed); OBJECT_CHECK(ObjectReader().read(input.get()).values().size() == 4);
  flags.push_back("excess"); rejects(changed, "invalid_characteristic");
  changed = baseline; changed.push_back(baseline[0]); rejects(changed, "invalid_response");
  changed = baseline; changed[0].second.push_back(changed[0].second[0]); rejects(changed, "invalid_response");
  changed = baseline; changed[1].second[0].second.push_back(changed[1].second[0].second[0]);
  rejects(changed, "invalid_response");

  changed = baseline;
  changed[3].second[0].second.erase(changed[3].second[0].second.begin() + 2);
  input = message(changed); objects = ObjectReader().read(input.get());
  OBJECT_CHECK(discovery(objects, peer, 0).characteristics[0]["handle"].is_null());
  changed = baseline; changed[3].second[0].second.push_back({"Unknown", "s", std::string(100000, 'x')});
  changed[3].second.push_back({"org.example.Future", {{"Future", "ay", Json::array({1})}}});
  input = message(changed); objects = ObjectReader().read(input.get());
  OBJECT_CHECK(objects.values().at(changed[3].first).size() == 1);
  OBJECT_CHECK(!objects.values().at(changed[3].first).at(characteristic_interface).contains("Unknown"));
  const int descriptor = open("/dev/null", O_RDONLY); OBJECT_CHECK(descriptor >= 0);
  changed = {{"/object", {{"org.example.Future", {{"Descriptor", "h", descriptor}}}}}};
  input = message(changed); OBJECT_CHECK(::close(descriptor) == 0);
  bool fd_rejected = false;
  try { ObjectReader().read(input.get()); } catch (const InvalidObjects &) { fd_rejected = true; }
  OBJECT_CHECK(fd_rejected);

  changed = {};
  for (unsigned i = 0; i < 4096; ++i) changed.push_back({"/object_" + std::to_string(i), {}});
  input = message(changed); OBJECT_CHECK(ObjectReader().read(input.get()).values().size() == 4096);
  changed.push_back({"/excess", {}}); rejects(changed, "object_limit");
  changed = {{"/object", {}}};
  for (unsigned i = 0; i < 64; ++i) changed[0].second.push_back({"org.example.Interface" + std::to_string(i), {}});
  input = message(changed); OBJECT_CHECK(ObjectReader().read(input.get()).values().size() == 1);
  changed[0].second.push_back({"org.example.Excess", {}}); rejects(changed, "object_limit");
  changed = {{"/object", {{"org.example.Future", {}}}}};
  for (unsigned i = 0; i < 256; ++i)
    changed[0].second[0].second.push_back({"P" + std::to_string(i), "s", ""});
  input = message(changed); OBJECT_CHECK(ObjectReader().read(input.get()).values().size() == 1);
  changed[0].second[0].second.push_back({"Excess", "s", ""}); rejects(changed, "object_limit");
  changed[0].second[0].second.pop_back();
  const auto template_object = changed[0];
  for (unsigned i = 1; i < 254; ++i) {
    changed.push_back(template_object); changed.back().first = "/object_" + std::to_string(i);
  }
  changed.push_back({"/last", {{"org.example.Future", {{"A", "s", ""}, {"B", "s", ""}}}}});
  input = message(changed); OBJECT_CHECK(ObjectReader().read(input.get()).values().size() == 255);
  changed.back().second[0].second.push_back({"C", "s", ""});
  rejects(changed, "object_limit");

  changed = {{"/" + std::string(4095, 'x'), {}}};
  input = message(changed); OBJECT_CHECK(ObjectReader().read(input.get()).values().size() == 1);
  changed[0].first += 'x'; rejects(changed, "object_limit");
  changed = {baseline[0], baseline[1]};
  for (unsigned i = 0; i < 1024; ++i) {
    changed.push_back(baseline[2]); changed.back().first = "/service_" + std::to_string(i);
  }
  input = message(changed);
  OBJECT_CHECK(discovery(ObjectReader().read(input.get()), peer, 1).characteristics.empty());
  changed.push_back(baseline[3]); changed.back().second[0].second[0].value = "/service_0";
  discovery_rejects(changed, peer, "object_limit");
  changed = {baseline[0], baseline[1], baseline[2]};
  for (unsigned i = 0; i < 1023; ++i) {
    changed.push_back(baseline[3]); changed.back().first = "/characteristic_" + std::to_string(i);
  }
  input = message(changed);
  OBJECT_CHECK(discovery(ObjectReader().read(input.get()), peer, 1).characteristics.size() == 1023);
  changed.push_back(baseline[3]); discovery_rejects(changed, peer, "object_limit");

  for (const auto &valid : {"180f", "0000180F", "0000180f00001000800000805f9b34fb", "0000180f-0000-1000-8000-00805f9b34fb"})
    OBJECT_CHECK(uuid_text(valid) == "0000180f-0000-1000-8000-00805f9b34fb");
  for (const auto &invalid : {"", "180", "-180f", "0000180f_0000_1000_8000_00805f9b34fb", "zzzz"}) {
    bool rejected = false;
    try { uuid_text(invalid); } catch (const InvalidObjects &) { rejected = true; }
    OBJECT_CHECK(rejected);
  }
  for (auto invalid : {Json(), Json::object(), peer_fields}) {
    if (invalid == peer_fields) invalid["extra"] = true;
    bool rejected = false;
    try { NativePeer::from(invalid); } catch (const InvalidObjects &) { rejected = true; }
    OBJECT_CHECK(rejected);
  }
  for (const auto &[field, invalid] : std::vector<std::pair<std::string, Json>>{
    {"adapter", "relative"}, {"adapter", "/" + std::string(4096, 'x')},
    {"adapter", std::string("/x\0hidden", 9)}, {"address", "AA:BB:CC:DD:EE:FG"},
    {"address", "AA-BB-CC-DD-EE-FF"}, {"address_type", "unknown"}, {"address", 123}}) {
    auto value = peer_fields; value[field] = invalid;
    bool rejected = false;
    try { NativePeer::from(value); } catch (const InvalidObjects &) { rejected = true; }
    OBJECT_CHECK(rejected);
  }
}
#undef OBJECT_CHECK
} // namespace object_test
