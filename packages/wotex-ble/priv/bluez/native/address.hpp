// SPDX-License-Identifier: Apache-2.0
// Immutable selectors for the current peer's validated discovery snapshot.
#pragma once
#include "objects.hpp"
#include <optional>

namespace wotex::ble {
class InvalidAddress : public std::runtime_error {
public:
  explicit InvalidAddress(const char *code = "invalid_address") : std::runtime_error(code) {}
};

class NativeAddress {
  std::string service_, characteristic_;
  std::optional<std::string> object_path_;
  std::optional<std::uint16_t> handle_;
  std::optional<std::uint64_t> generation_;
  NativeAddress(std::string service, std::string characteristic, std::optional<std::string> path,
                std::optional<std::uint16_t> handle, std::optional<std::uint64_t> generation)
    : service_(std::move(service)), characteristic_(std::move(characteristic)), object_path_(std::move(path)),
      handle_(handle), generation_(generation) {}
public:
  static NativeAddress from(const Json &value) {
    if (!fields(value, {"service", "characteristic", "object_path", "handle", "generation"}) ||
        !value.at("service").is_string() || !value.at("characteristic").is_string()) throw InvalidAddress();
    std::string service, characteristic;
    try {
      service = uuid_text(value.at("service").get_ref<const std::string &>());
      characteristic = uuid_text(value.at("characteristic").get_ref<const std::string &>());
    } catch (const InvalidObjects &) { throw InvalidAddress(); }
    std::optional<std::string> path;
    std::optional<std::uint16_t> handle;
    std::optional<std::uint64_t> generation;
    if (!value.at("object_path").is_null()) {
      if (!value.at("object_path").is_string()) throw InvalidAddress();
      const auto &text = value.at("object_path").get_ref<const std::string &>();
      if (text.empty() || text.size() > 4096 || text.find('\0') != std::string::npos ||
          !dbus_validate_path(text.c_str(), nullptr)) throw InvalidAddress();
      path = text;
    }
    if (!value.at("handle").is_null()) {
      if (!integer(value.at("handle"), 1, 65535)) throw InvalidAddress();
      handle = value.at("handle").get<std::uint16_t>();
    }
    if (!value.at("generation").is_null()) {
      if (!integer(value.at("generation"), 0, std::numeric_limits<std::uint64_t>::max())) throw InvalidAddress();
      generation = value.at("generation").get<std::uint64_t>();
    }
    return {std::move(service), std::move(characteristic), std::move(path), handle, generation};
  }
  const Json &select(const Discovery &snapshot, std::uint64_t generation) const {
    if (generation_ && *generation_ != generation) throw InvalidAddress("stale_discovery");
    const Json *selected = nullptr;
    for (const auto &item : snapshot.characteristics) {
      if (item.at("service_uuid") != service_ || item.at("characteristic_uuid") != characteristic_ ||
          (object_path_ && item.at("object_path") != *object_path_) ||
          (handle_ && item.at("handle") != *handle_)) continue;
      if (selected) throw InvalidAddress("ambiguous_characteristic");
      selected = &item;
    }
    if (!selected) throw InvalidAddress("address_mismatch");
    return *selected;
  }
};
} // namespace wotex::ble
