#include "wotex_matter/bridge_configuration.hpp"
#include "wotex_matter/bridge_control.hpp"
#include <nlohmann/json.hpp>
#include <cassert>
#include <cstdlib>
#include <iostream>
#include <new>
#include <string>

namespace {
long remaining = -1;
}
void *operator new(std::size_t size) {
  if (remaining == 0) {
    remaining = -1;
    throw std::bad_alloc();
  }
  if (remaining > 0) --remaining;
  if (auto *memory = std::malloc(size == 0 ? 1 : size)) return memory;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *value) noexcept { std::free(value); }
void operator delete[](void *value) noexcept { std::free(value); }
void operator delete(void *value, std::size_t) noexcept { std::free(value); }
void operator delete[](void *value, std::size_t) noexcept { std::free(value); }

int main() {
  using namespace wotex::matter;
  using Json = nlohmann::json;
  using R = BridgeConfigurationDecode;
  Json device = {{"thing_id", "0061ff"},
                 {"device_type", 0x0100},
                 {"node_label", "explicit label"},
                 {"minimum_temperature", nullptr},
                 {"maximum_temperature", nullptr}};
  Json input = {{"schema", "wotex.matter.bridge-bootstrap@1"},
                {"sdk_revision", kBridgeSdkRevision},
                {"model_sha256", kBridgeModelSha256},
                {"bridge_id", "00ff"},
                {"vendor_id", 0xFFF1},
                {"product_id", 0x8001},
                {"vendor_name", "consumer"},
                {"product_name", "explicit bridge"},
                {"hardware_version", 1},
                {"hardware_version_string", "explicit hardware"},
                {"store_path", "/data/bridge-store"},
                {"store_mode", "new"},
                {"interface", "eth0"},
                {"port", 5540},
                {"dac_path", "/data/dac.der"},
                {"commissioning_window_seconds", 0},
                {"pai_path", "/data/pai.der"},
                {"declaration_path", "/data/cd.bin"},
                {"key_path", "/data/key.bin"},
                {"commissioning_path", "/data/setup.bin"},
                {"devices", Json::array({device})}};
  std::unique_ptr<BridgeConfiguration> owner;
  assert(DecodeBridgeConfiguration(input.dump(), owner) == R::Decoded);
  assert(owner->identity.bridge_id == std::string("\0\xff", 2));
  assert(owner->devices.size() == 1 && owner->devices[0].thing_id == std::string("\0a\xff", 3));
  assert(owner->store_mode == StorageMode::CreateNew && owner->port == 5540);
  assert(owner->commissioning_window_seconds == 0);
  auto *initial = owner.get();
  const auto refuse = [&](const Json &value) {
    assert(DecodeBridgeConfiguration(value.dump(), owner) == R::Malformed &&
           owner.get() == initial);
  };
  for (auto field = input.begin(); field != input.end(); ++field) {
    auto changed = input;
    changed.erase(field.key());
    refuse(changed);
  }
  auto changed = input;
  changed["extra"] = "refused";
  refuse(changed);
  changed = input;
  changed["key_path"] = "relative";
  refuse(changed);
  for (const auto &path : {std::string("/data/../key.bin"), std::string("/data//key.bin"),
                           std::string("/data/./key.bin"), std::string("/data/key\0.bin", 14),
                           std::string("/data/key\n.bin")}) {
    changed["key_path"] = path;
    refuse(changed);
  }
  changed = input;
  changed["sdk_revision"] = std::string(40, '0');
  refuse(changed);
  changed = input;
  changed["model_sha256"] = std::string(64, '0');
  refuse(changed);
  for (const auto &name : {"vendor_name", "product_name", "hardware_version_string"}) {
    changed = input;
    changed[name] = "";
    refuse(changed);
    changed[name] = std::string(65, 'x');
    refuse(changed);
    changed[name] = std::string("nul\0text", 8);
    refuse(changed);
  }
  changed = input;
  changed["hardware_version"] = 65536;
  refuse(changed);
  changed = input;
  changed["port"] = 65536;
  refuse(changed);
  for (const auto value : {1, 179, 901, 65536}) {
    changed = input;
    changed["commissioning_window_seconds"] = value;
    refuse(changed);
  }
  for (const auto value : {180, 900}) {
    changed = input;
    changed["commissioning_window_seconds"] = value;
    assert(DecodeBridgeConfiguration(changed.dump(), owner) == R::Decoded);
    assert(owner->commissioning_window_seconds == value);
    initial = owner.get();
  }
  changed = input;
  changed["vendor_id"] = -1;
  refuse(changed);
  changed = input;
  changed["devices"] = Json::array({device, device});
  refuse(changed);
  changed = input;
  changed["devices"][0]["thing_id"] = "AA";
  refuse(changed);
  changed = input;
  changed["devices"][0]["minimum_temperature"] = 0;
  refuse(changed);
  changed = input;
  changed["devices"][0]["device_type"] = 0x0302;
  changed["devices"][0]["minimum_temperature"] = -27315;
  changed["devices"][0]["maximum_temperature"] = 32767;
  assert(DecodeBridgeConfiguration(changed.dump(), owner) == R::Decoded);
  assert(owner->devices[0].minimum_temperature == -27315 &&
         owner->devices[0].maximum_temperature == 32767);
  initial = owner.get();
  changed["devices"][0]["maximum_temperature"] = -27315;
  refuse(changed);
  changed = input;
  changed["devices"] = Json::array();
  for (unsigned i = 0; i < 16; ++i) {
    device["thing_id"] = std::string("0") + "0123456789abcdef"[i];
    changed["devices"].push_back(device);
  }
  assert(DecodeBridgeConfiguration(changed.dump(), owner) == R::Decoded &&
         owner->devices.size() == 16);
  initial = owner.get();
  device["thing_id"] = "10";
  changed["devices"].push_back(device);
  refuse(changed);
  assert(DecodeBridgeConfiguration(std::string(65537, ' '), owner) == R::Oversized &&
         owner.get() == initial);
  const auto valid = input.dump();
  for (const auto &bad : {std::string("[]"), std::string("{}"),
                          std::string("{\"devices\":[[[[]]]]}"), valid + "{}", valid + '\0'})
    assert(DecodeBridgeConfiguration(bad, owner) == R::Malformed && owner.get() == initial);
  const auto duplicate = valid.substr(0, valid.size() - 1) + ",\"port\":5540}";
  assert(DecodeBridgeConfiguration(duplicate, owner) == R::Malformed && owner.get() == initial);
  for (const auto &field :
       {"vendor_id", "product_id", "port", "hardware_version", "commissioning_window_seconds"}) {
    for (const Json &value : {Json(-1), Json(1.0), Json(true), Json(nullptr), Json("1"),
                              Json::array(), Json::object()}) {
      changed = input;
      changed[field] = value;
      refuse(changed);
    }
  }
  for (const auto &field : {"vendor_id", "product_id", "port"}) {
    changed = input;
    changed[field] = 0;
    refuse(changed);
  }
  changed = input;
  changed["vendor_id"] = 65535;
  refuse(changed);
  for (const auto &field : {"bridge_id", "store_mode", "interface"}) {
    changed = input;
    changed[field] = "";
    refuse(changed);
  }
  changed = input;
  changed["bridge_id"] = std::string(514, 'a');
  refuse(changed);
  changed["bridge_id"] = "0";
  refuse(changed);
  changed["bridge_id"] = "aF";
  refuse(changed);
  changed = input;
  changed["interface"] = std::string(16, 'a');
  refuse(changed);
  changed["interface"] = std::string("lo\0x", 4);
  refuse(changed);
  changed = input;
  changed["store_mode"] = "create-or-reopen";
  refuse(changed);
  changed = input;
  changed["key_path"] = "/" + std::string(4096, 'a');
  refuse(changed);
  changed["key_path"] = "/";
  refuse(changed);
  for (auto field = device.begin(); field != device.end(); ++field) {
    changed = input;
    changed["devices"][0].erase(field.key());
    refuse(changed);
  }
  for (const Json &value : {Json(nullptr), Json(true), Json(0), Json("device"), Json::array()}) {
    changed = input;
    changed["devices"] = Json::array({value});
    refuse(changed);
  }
  changed = input;
  changed["devices"][0]["unknown"] = true;
  refuse(changed);
  changed = input;
  changed["devices"][0]["device_type"] = 0x0101;
  refuse(changed);
  changed["devices"][0]["device_type"] = 0x0302;
  changed["devices"][0]["minimum_temperature"] = -27316;
  refuse(changed);
  changed["devices"][0]["minimum_temperature"] = 32767;
  refuse(changed);
  changed["devices"][0]["minimum_temperature"] = nullptr;
  changed["devices"][0]["maximum_temperature"] = -27315;
  refuse(changed);
  changed["devices"][0]["maximum_temperature"] = 32768;
  refuse(changed);
  changed = input;
  changed["devices"][0]["node_label"] = std::string(33, 'a');
  refuse(changed);
  auto invalid_utf8 = valid;
  invalid_utf8[invalid_utf8.find("explicit label")] = static_cast<char>(0xFF);
  assert(DecodeBridgeConfiguration(invalid_utf8, owner) == R::Malformed && owner.get() == initial);
  changed = input;
  changed["bridge_id"] = std::string(512, 'f');
  changed["devices"][0]["thing_id"] = std::string(512, 'a');
  changed["vendor_id"] = 65534;
  changed["product_id"] = 65535;
  changed["port"] = 65535;
  changed["hardware_version"] = 0;
  changed["vendor_name"] = std::string(32, 'v');
  changed["product_name"] = std::string(32, 'p');
  changed["hardware_version_string"] = std::string(64, 'h');
  changed["interface"] = std::string(15, 'a');
  changed["key_path"] = "/" + std::string(4095, 'a');
  changed["store_mode"] = "reopen";
  changed["devices"][0]["node_label"] = std::string(32, 'n');
  assert(DecodeBridgeConfiguration(changed.dump(), owner) == R::Decoded);
  assert(owner->identity.bridge_id.size() == 256 && owner->devices[0].thing_id.size() == 256);
  assert(owner->hardware_version == 0 && owner->store_mode == StorageMode::OpenExisting);
  changed = input;
  changed["devices"][0]["node_label"] = std::string("nul\0label", 9);
  assert(DecodeBridgeConfiguration(changed.dump(), owner) == R::Decoded);
  assert(owner->devices[0].node_label == std::string("nul\0label", 9));
  for (const auto &field :
       {std::string("hardware_version"), std::string("commissioning_window_seconds")}) {
    auto negative_zero = valid;
    const auto key = "\"" + field + "\":";
    const auto begin = negative_zero.find(key) + key.size();
    const auto end = negative_zero.find_first_not_of("0123456789", begin);
    negative_zero.replace(begin, end - begin, "-0");
    assert(DecodeBridgeConfiguration(negative_zero, owner) == R::Decoded);
    assert((field == "hardware_version" ? owner->hardware_version
                                        : owner->commissioning_window_seconds) == 0);
  }
  auto padded = valid + std::string(65536 - valid.size(), ' ');
  assert(DecodeBridgeConfiguration(padded, owner) == R::Decoded);
  initial = owner.get();
  bool reached = false;
  std::size_t failures = 0;
  for (long point = 0; point < 256; ++point) {
    remaining = point;
    const auto result = DecodeBridgeConfiguration(valid, owner);
    remaining = -1;
    if (result == R::Decoded) {
      reached = true;
      break;
    }
    assert(result == R::NoMemory && owner.get() == initial);
    ++failures;
  }
  assert(reached && failures > 0 && owner->identity.bridge_id == std::string("\0\xff", 2));
  std::cout << "bounded bridge bootstrap configuration passed\n";
}
