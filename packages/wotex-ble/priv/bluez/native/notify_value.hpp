// SPDX-License-Identifier: Apache-2.0
// Typed PropertiesChanged payloads. Source/path ownership is checked by the
// subscription dispatcher before this decoder; no Value implies no report.
#pragma once
#include "bytes.hpp"
#include "objects.hpp"
#include <optional>

namespace wotex::ble {
class NotifyMode {
  std::string requested_, effective_;
  NotifyMode(std::string requested, std::string effective)
    : requested_(std::move(requested)), effective_(std::move(effective)) {}
public:
  static NotifyMode from(const Json &flags, const Json &requested) {
    if (requested != "auto" && requested != "notify" && requested != "indicate")
      throw InvalidObjects("invalid_options");
    if (!flags.is_array() || flags.size() > 64) throw InvalidObjects("invalid_characteristic");
    std::set<std::string> seen;
    for (const auto &flag : flags) {
      if (!flag.is_string()) throw InvalidObjects("invalid_characteristic");
      const auto &text = flag.get_ref<const std::string &>();
      if (text.empty() || text.size() > 64 || text.find('\0') != std::string::npos || !seen.insert(text).second)
        throw InvalidObjects("invalid_characteristic");
    }
    const bool notify = seen.count("notify"), indicate = seen.count("indicate");
    if (notify && indicate) {
      if (requested != "auto") throw InvalidObjects("unsupported_procedure_selection");
      return {"auto", "bluez_selected"};
    }
    if (notify && requested != "indicate") return {requested.get<std::string>(), "notify"};
    if (indicate && requested != "notify") return {requested.get<std::string>(), "indicate"};
    throw InvalidObjects("not_supported");
  }
  const std::string &requested() const { return requested_; }
  const std::string &effective() const { return effective_; }
};

class GattChange {
  PropertiesChange metadata_;
  std::optional<AttributeBytes> value_;
  std::optional<bool> notifying_;
  explicit GattChange(PropertiesChange metadata) : metadata_(std::move(metadata)) {}
public:
  static GattChange from(DBusMessage *message) {
    GattChange result(ObjectReader().changed(message));
    if (result.metadata_.interface != characteristic_interface) return result;
    DBusMessageIter root, array;
    dbus_message_iter_init(message, &root); dbus_message_iter_next(&root);
    dbus_message_iter_recurse(&root, &array);
    while (dbus_message_iter_get_arg_type(&array) != DBUS_TYPE_INVALID) {
      DBusMessageIter entry, variant;
      dbus_message_iter_recurse(&array, &entry);
      const char *name = nullptr; dbus_message_iter_get_basic(&entry, &name);
      dbus_message_iter_next(&entry); dbus_message_iter_recurse(&entry, &variant);
      if (std::strcmp(name, "Value") == 0) {
        if (dbus_message_iter_get_arg_type(&variant) != DBUS_TYPE_ARRAY ||
            dbus_message_iter_get_element_type(&variant) != DBUS_TYPE_BYTE) throw InvalidObjects();
        DBusMessageIter bytes; dbus_message_iter_recurse(&variant, &bytes);
        const unsigned char *value = nullptr; int count = 0;
        dbus_message_iter_get_fixed_array(&bytes, &value, &count);
        if (count < 0 || count > 512 || (count && !value)) throw InvalidObjects();
        const auto view = count ? std::string_view(reinterpret_cast<const char *>(value), static_cast<std::size_t>(count)) : std::string_view{};
        result.value_.emplace(AttributeBytes::from_bytes(view));
      } else if (std::strcmp(name, "Notifying") == 0) {
        if (dbus_message_iter_get_arg_type(&variant) != DBUS_TYPE_BOOLEAN) throw InvalidObjects();
        dbus_bool_t value; dbus_message_iter_get_basic(&variant, &value); result.notifying_ = bool(value);
      }
      dbus_message_iter_next(&array);
    }
    return result;
  }
  const PropertiesChange &metadata() const { return metadata_; }
  const std::optional<AttributeBytes> &value() const { return value_; }
  const std::optional<bool> &notifying() const { return notifying_; }
};
} // namespace wotex::ble
