// SPDX-License-Identifier: Apache-2.0
// Typed ObjectManager decoding. Unknown values remain in the bounded libdbus
// message; only admitted discovery fields enter the owned snapshot.
#pragma once
#include "bus.hpp"
#include "frame.hpp"
#include <cstring>
#include <set>

namespace wotex::ble {
constexpr const char *adapter_interface = "org.bluez.Adapter1";
constexpr const char *device_interface = "org.bluez.Device1";
constexpr const char *service_interface = "org.bluez.GattService1";
constexpr const char *characteristic_interface = "org.bluez.GattCharacteristic1";

class InvalidObjects : public std::runtime_error {
public:
  explicit InvalidObjects(const char *reason = "invalid_response") : std::runtime_error(reason) {}
};

inline std::string uuid_text(const std::string &value) {
  if (value.size() != 4 && value.size() != 8 && value.size() != 32 && value.size() != 36)
    throw InvalidObjects("invalid_characteristic");
  std::string compact;
  for (std::size_t i = 0; i < value.size(); ++i) {
    const char c = value[i];
    if (value.size() == 36 && (i == 8 || i == 13 || i == 18 || i == 23)) {
      if (c != '-') throw InvalidObjects("invalid_characteristic");
      continue;
    }
    // NOLINTNEXTLINE(bugprone-branch-clone): digits and lower-case hex digits are both kept as they are
    if (c >= '0' && c <= '9') compact += c;
    else if (c >= 'a' && c <= 'f') compact += c;
    else if (c >= 'A' && c <= 'F') compact += static_cast<char>(c + ('a' - 'A'));
    else throw InvalidObjects("invalid_characteristic");
  }
  if (compact.size() <= 8)
    compact = std::string(8 - compact.size(), '0') + compact + "00001000800000805f9b34fb";
  return compact.substr(0, 8) + "-" + compact.substr(8, 4) + "-" + compact.substr(12, 4) +
         "-" + compact.substr(16, 4) + "-" + compact.substr(20);
}

class ObjectSnapshot {
  friend class ObjectReader;
  Json objects_;
  explicit ObjectSnapshot(Json objects) : objects_(std::move(objects)) {}
public:
  const Json &values() const { return objects_; }
};

struct PropertiesChange {
  std::string interface;
  Json values;
  std::set<std::string> invalidated;
};
struct RemovedInterfaces { std::string path; std::set<std::string> interfaces; };

class ObjectReader {
  std::size_t entries_ = 0;
  void entry() { if (++entries_ > 65536) throw InvalidObjects("object_limit"); }
  static void type(DBusMessageIter &iterator, int expected) {
    if (dbus_message_iter_get_arg_type(&iterator) != expected) throw InvalidObjects();
  }
  static DBusMessageIter child(DBusMessageIter &iterator, int expected) {
    type(iterator, expected); DBusMessageIter result;
    dbus_message_iter_recurse(&iterator, &result); return result;
  }
  static void next(DBusMessageIter &iterator) {
    if (!dbus_message_iter_next(&iterator)) throw InvalidObjects();
  }
  static void end(DBusMessageIter &iterator) {
    if (dbus_message_iter_next(&iterator)) throw InvalidObjects();
  }
  static std::string text(DBusMessageIter &iterator, int expected, std::size_t maximum,
                          const char *invalid = "object_limit") {
    type(iterator, expected);
    const char *value = nullptr; dbus_message_iter_get_basic(&iterator, &value);
    if (!value || !*value || strnlen(value, maximum + 1) > maximum) throw InvalidObjects(invalid);
    return value;
  }
  static bool known(const std::string &interface) {
    return interface == adapter_interface || interface == device_interface ||
           interface == service_interface || interface == characteristic_interface;
  }
  static int property_type(const std::string &interface, const std::string &name) {
    if (interface == device_interface) {
      if (name == "Adapter") return DBUS_TYPE_OBJECT_PATH;
      if (name == "Address" || name == "AddressType") return DBUS_TYPE_STRING;
      if (name == "Connected" || name == "ServicesResolved") return DBUS_TYPE_BOOLEAN;
    } else if (interface == service_interface) {
      if (name == "Device") return DBUS_TYPE_OBJECT_PATH;
      if (name == "UUID") return DBUS_TYPE_STRING;
    } else if (interface == characteristic_interface) {
      if (name == "Service") return DBUS_TYPE_OBJECT_PATH;
      if (name == "UUID") return DBUS_TYPE_STRING;
      if (name == "Handle") return DBUS_TYPE_UINT16;
      if (name == "Flags") return DBUS_TYPE_ARRAY;
    }
    return DBUS_TYPE_INVALID;
  }
  static Json value(DBusMessageIter &variant, int expected) {
    auto data = child(variant, DBUS_TYPE_VARIANT);
    type(data, expected);
    Json result;
    switch (expected) {
      case DBUS_TYPE_OBJECT_PATH:
      case DBUS_TYPE_STRING: result = text(data, expected, 4096); break;
      case DBUS_TYPE_BOOLEAN: {
        dbus_bool_t value; dbus_message_iter_get_basic(&data, &value); result = bool(value); break;
      }
      case DBUS_TYPE_UINT16: {
        dbus_uint16_t value; dbus_message_iter_get_basic(&data, &value);
        if (!value) throw InvalidObjects("invalid_characteristic");
        result = value; break;
      }
      case DBUS_TYPE_ARRAY: {
        if (dbus_message_iter_get_element_type(&data) != DBUS_TYPE_STRING) throw InvalidObjects();
        auto flags = child(data, DBUS_TYPE_ARRAY);
        result = Json::array(); std::set<std::string> seen;
        while (dbus_message_iter_get_arg_type(&flags) != DBUS_TYPE_INVALID) {
          if (seen.size() == 64) throw InvalidObjects("invalid_characteristic");
          const auto flag = text(flags, DBUS_TYPE_STRING, 64, "invalid_characteristic");
          if (!seen.insert(flag).second) throw InvalidObjects("invalid_characteristic");
          result.push_back(flag);
          dbus_message_iter_next(&flags);
        }
        break;
      }
      default: throw InvalidObjects();
    }
    end(data); return result;
  }
  Json properties(DBusMessageIter &array, const std::string &interface,
                  std::set<std::string> *names = nullptr) {
    auto item = child(array, DBUS_TYPE_ARRAY);
    Json result = Json::object(); std::set<std::string> seen;
    while (dbus_message_iter_get_arg_type(&item) != DBUS_TYPE_INVALID) {
      entry();
      if (seen.size() == 256) throw InvalidObjects("object_limit");
      auto pair = child(item, DBUS_TYPE_DICT_ENTRY);
      const auto name = text(pair, DBUS_TYPE_STRING, 255);
      if (!dbus_validate_member(name.c_str(), nullptr) || !seen.insert(name).second) throw InvalidObjects();
      next(pair); type(pair, DBUS_TYPE_VARIANT);
      const auto expected = property_type(interface, name);
      if (expected != DBUS_TYPE_INVALID) result[name] = value(pair, expected);
      end(pair); dbus_message_iter_next(&item);
    }
    if (names) *names = std::move(seen);
    return result;
  }
  Json interfaces(DBusMessageIter &array) {
    auto item = child(array, DBUS_TYPE_ARRAY);
    Json result = Json::object(); std::set<std::string> seen;
    while (dbus_message_iter_get_arg_type(&item) != DBUS_TYPE_INVALID) {
      entry();
      if (seen.size() == 64) throw InvalidObjects("object_limit");
      auto pair = child(item, DBUS_TYPE_DICT_ENTRY);
      const auto name = text(pair, DBUS_TYPE_STRING, 255);
      if (!dbus_validate_interface(name.c_str(), nullptr) || !seen.insert(name).second) throw InvalidObjects();
      next(pair);
      auto selected = properties(pair, name);
      if (known(name)) result[name] = std::move(selected);
      end(pair); dbus_message_iter_next(&item);
    }
    return result;
  }
public:
  Json device_properties(DBusMessage *message) {
    entries_ = 0;
    if (!message || dbus_message_contains_unix_fds(message) ||
        dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_METHOD_RETURN ||
        !dbus_message_has_signature(message, "a{sv}")) throw InvalidObjects();
    DBusMessageIter root;
    if (!dbus_message_iter_init(message, &root)) throw InvalidObjects();
    auto result = properties(root, device_interface); end(root); return result;
  }

  ObjectSnapshot read(DBusMessage *message) {
    entries_ = 0;
    if (!message || dbus_message_contains_unix_fds(message) ||
        dbus_message_get_type(message) != DBUS_MESSAGE_TYPE_METHOD_RETURN ||
        !dbus_message_has_signature(message, "a{oa{sa{sv}}}")) throw InvalidObjects();
    DBusMessageIter root;
    if (!dbus_message_iter_init(message, &root)) throw InvalidObjects();
    auto item = child(root, DBUS_TYPE_ARRAY); Json result = Json::object();
    while (dbus_message_iter_get_arg_type(&item) != DBUS_TYPE_INVALID) {
      entry();
      if (result.size() == 4096) throw InvalidObjects("object_limit");
      auto pair = child(item, DBUS_TYPE_DICT_ENTRY);
      const auto path = text(pair, DBUS_TYPE_OBJECT_PATH, 4096);
      if (result.contains(path)) throw InvalidObjects();
      next(pair); result[path] = interfaces(pair);
      end(pair); dbus_message_iter_next(&item);
    }
    end(root); return ObjectSnapshot(std::move(result));
  }

  PropertiesChange changed(DBusMessage *message) {
    entries_ = 0;
    if (!message || dbus_message_contains_unix_fds(message) ||
        !dbus_message_is_signal(message, "org.freedesktop.DBus.Properties", "PropertiesChanged") ||
        !dbus_message_has_signature(message, "sa{sv}as")) throw InvalidObjects();
    DBusMessageIter root;
    if (!dbus_message_iter_init(message, &root)) throw InvalidObjects();
    auto interface = text(root, DBUS_TYPE_STRING, 255);
    if (!dbus_validate_interface(interface.c_str(), nullptr)) throw InvalidObjects();
    next(root); std::set<std::string> changed;
    auto values = properties(root, interface, &changed);
    next(root); auto item = child(root, DBUS_TYPE_ARRAY);
    std::set<std::string> invalidated;
    while (dbus_message_iter_get_arg_type(&item) != DBUS_TYPE_INVALID) {
      if (invalidated.size() == 256) throw InvalidObjects("object_limit");
      const auto name = text(item, DBUS_TYPE_STRING, 255);
      if (!dbus_validate_member(name.c_str(), nullptr) || !invalidated.insert(name).second || changed.count(name))
        throw InvalidObjects();
      dbus_message_iter_next(&item);
    }
    end(root); return {std::move(interface), std::move(values), std::move(invalidated)};
  }

  ObjectSnapshot added(DBusMessage *message) {
    entries_ = 0;
    if (!message || dbus_message_contains_unix_fds(message) ||
        !dbus_message_is_signal(message, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded") ||
        !dbus_message_has_signature(message, "oa{sa{sv}}")) throw InvalidObjects();
    DBusMessageIter root;
    if (!dbus_message_iter_init(message, &root)) throw InvalidObjects();
    entry(); const auto path = text(root, DBUS_TYPE_OBJECT_PATH, 4096);
    next(root); Json result = Json::object(); result[path] = interfaces(root);
    end(root); return ObjectSnapshot(std::move(result));
  }

  RemovedInterfaces removed(DBusMessage *message) {
    entries_ = 0;
    if (!message || dbus_message_contains_unix_fds(message) ||
        !dbus_message_is_signal(message, "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved") ||
        !dbus_message_has_signature(message, "oas")) throw InvalidObjects();
    DBusMessageIter root;
    if (!dbus_message_iter_init(message, &root)) throw InvalidObjects();
    auto path = text(root, DBUS_TYPE_OBJECT_PATH, 4096);
    next(root); auto item = child(root, DBUS_TYPE_ARRAY);
    std::set<std::string> interfaces;
    while (dbus_message_iter_get_arg_type(&item) != DBUS_TYPE_INVALID) {
      if (interfaces.size() == 64) throw InvalidObjects("object_limit");
      const auto name = text(item, DBUS_TYPE_STRING, 255);
      if (!dbus_validate_interface(name.c_str(), nullptr) || !interfaces.insert(name).second) throw InvalidObjects();
      dbus_message_iter_next(&item);
    }
    end(root); return {std::move(path), std::move(interfaces)};
  }
};

struct Discovery {
  std::string device_path;
  bool connected, services_resolved;
  Json characteristics;
  std::set<std::string> service_paths;
};

class NativePeer {
  NativePeer(std::string adapter, std::string address, std::string type)
    : adapter(std::move(adapter)), address(std::move(address)), address_type(std::move(type)) {}
public:
  const std::string adapter, address, address_type;
  static NativePeer from(const Json &value) {
    if (!fields(value, {"adapter", "address", "address_type"}) ||
        !value.at("adapter").is_string() || !value.at("address").is_string() ||
        !value.at("address_type").is_string()) throw InvalidObjects("invalid_peer");
    const auto adapter = value.at("adapter").get<std::string>();
    auto address = value.at("address").get<std::string>();
    const auto type = value.at("address_type").get<std::string>();
    if (adapter.empty() || adapter.size() > 4096 || adapter.find('\0') != std::string::npos ||
        !dbus_validate_path(adapter.c_str(), nullptr) || address.size() != 17 ||
        (type != "public" && type != "random")) throw InvalidObjects("invalid_peer");
    for (std::size_t i = 0; i < address.size(); ++i) {
      char &c = address[i];
      if (i % 3 == 2) { if (c != ':') throw InvalidObjects("invalid_peer"); }
      else if (c >= 'a' && c <= 'f') c = static_cast<char>(c - ('a' - 'A'));
      else if (!((c >= 'A' && c <= 'F') || (c >= '0' && c <= '9'))) throw InvalidObjects("invalid_peer");
    }
    return {adapter, address, type};
  }
};

inline Discovery discovery(const ObjectSnapshot &snapshot, const NativePeer &peer, std::uint64_t generation) {
  const auto &objects = snapshot.values();
  const auto &adapter = peer.adapter, &address = peer.address, &address_type = peer.address_type;
  if (!objects.contains(adapter) || !objects.at(adapter).contains(adapter_interface))
    throw InvalidObjects("peer_not_found");
  std::string path; Json device;
  for (const auto &[key, interfaces] : objects.items()) {
    if (!interfaces.contains(device_interface)) continue;
    const auto &candidate = interfaces.at(device_interface);
    std::string remote = candidate.value("Address", std::string());
    std::transform(remote.begin(), remote.end(), remote.begin(), [](unsigned char c) {
      return c >= 'a' && c <= 'f' ? static_cast<char>(c - ('a' - 'A')) : static_cast<char>(c);
    });
    if (candidate.value("Adapter", std::string()) != adapter || remote != address ||
        candidate.value("AddressType", std::string()) != address_type) continue;
    if (!path.empty()) throw InvalidObjects("ambiguous_peer");
    path = key; device = candidate;
  }
  if (path.empty()) throw InvalidObjects("peer_not_found");
  if (!device.contains("Connected") || !device.at("Connected").is_boolean() ||
      !device.contains("ServicesResolved") || !device.at("ServicesResolved").is_boolean()) throw InvalidObjects();
  std::map<std::string, std::string> services;
  for (const auto &[key, interfaces] : objects.items()) {
    if (!interfaces.contains(service_interface)) continue;
    const auto &service = interfaces.at(service_interface);
    if (service.value("Device", std::string()) != path) continue;
    if (services.size() == 1024) throw InvalidObjects("object_limit");
    services.emplace(key, uuid_text(service.value("UUID", std::string())));
  }
  Json characteristics = Json::array();
  for (const auto &[key, interfaces] : objects.items()) {
    if (!interfaces.contains(characteristic_interface)) continue;
    const auto &characteristic = interfaces.at(characteristic_interface);
    const auto service = characteristic.value("Service", std::string());
    const auto found = services.find(service);
    if (found == services.end()) continue;
    if (services.size() + characteristics.size() == 1024) throw InvalidObjects("object_limit");
    if (!characteristic.contains("Flags") || !characteristic.at("Flags").is_array())
      throw InvalidObjects("invalid_characteristic");
    characteristics.push_back({{"service_uuid", found->second},
      {"characteristic_uuid", uuid_text(characteristic.value("UUID", std::string()))},
      {"service_path", service}, {"object_path", key},
      {"handle", characteristic.value("Handle", Json(nullptr))},
      {"flags", characteristic.at("Flags")}, {"generation", generation}});
  }
  std::sort(characteristics.begin(), characteristics.end(), [](const Json &a, const Json &b) {
    return std::make_pair(a.at("service_path"), a.at("object_path")) <
           std::make_pair(b.at("service_path"), b.at("object_path"));
  });
  std::set<std::string> service_paths;
  for (const auto &[key, unused] : services) { (void)unused; service_paths.insert(key); }
  return {path, device.at("Connected"), device.at("ServicesResolved"), std::move(characteristics), std::move(service_paths)};
}
} // namespace wotex::ble
