#ifndef WOTEX_MATTER_BRIDGE_DEVICE_INFO_HPP
#define WOTEX_MATTER_BRIDGE_DEVICE_INFO_HPP
#include "wotex_matter/bridge_configuration.hpp"
#include <platform/DeviceInstanceInfoProvider.h>
#include <cstring>

namespace wotex::matter {
// Borrowed validated configuration outlives this identity provider. The host
// installs it explicitly after platform initialization and before server init,
// then restores the captured original provider before shutdown/destruction.
// No optional factory data or SDK example/default identity is selected.
class BridgeDeviceInfo final : public chip::DeviceLayer::DeviceInstanceInfoProvider {
 public:
  explicit BridgeDeviceInfo(const BridgeConfiguration &configuration)
      : configuration_(configuration) {}
  void Retire() noexcept { active_ = false; }
  CHIP_ERROR GetVendorName(char *output, std::size_t capacity) override {
    return Copy(configuration_.vendor_name, output, capacity);
  }
  CHIP_ERROR GetProductName(char *output, std::size_t capacity) override {
    return Copy(configuration_.product_name, output, capacity);
  }
  CHIP_ERROR GetHardwareVersionString(char *output, std::size_t capacity) override {
    return Copy(configuration_.hardware_version_string, output, capacity);
  }
  CHIP_ERROR GetVendorId(std::uint16_t &value) override {
    if (!active_) return CHIP_ERROR_INCORRECT_STATE;
    value = configuration_.identity.vendor_id;
    return CHIP_NO_ERROR;
  }
  CHIP_ERROR GetProductId(std::uint16_t &value) override {
    if (!active_) return CHIP_ERROR_INCORRECT_STATE;
    value = configuration_.identity.product_id;
    return CHIP_NO_ERROR;
  }
  CHIP_ERROR GetHardwareVersion(std::uint16_t &value) override {
    if (!active_) return CHIP_ERROR_INCORRECT_STATE;
    value = configuration_.hardware_version;
    return CHIP_NO_ERROR;
  }
  CHIP_ERROR GetPartNumber(char *, std::size_t) override { return Absent(); }
  CHIP_ERROR GetProductURL(char *, std::size_t) override { return Absent(); }
  CHIP_ERROR GetProductLabel(char *, std::size_t) override { return Absent(); }
  CHIP_ERROR GetSerialNumber(char *, std::size_t) override { return Absent(); }
  CHIP_ERROR GetManufacturingDate(std::uint16_t &, std::uint8_t &, std::uint8_t &) override {
    return Absent();
  }
  CHIP_ERROR GetManufacturingDateSuffix(chip::MutableCharSpan &) override { return Absent(); }
  CHIP_ERROR GetRotatingDeviceIdUniqueId(chip::MutableByteSpan &) override { return Absent(); }
  CHIP_ERROR GetProductFinish(chip::app::Clusters::BasicInformation::ProductFinishEnum *) override {
    return Absent();
  }
  CHIP_ERROR GetProductPrimaryColor(chip::app::Clusters::BasicInformation::ColorEnum *) override {
    return Absent();
  }
  CHIP_ERROR GetJointFabricMode(std::uint8_t &) override { return Absent(); }
  CHIP_ERROR GetLocalConfigDisabled(bool &value) override {
    if (!active_) return CHIP_ERROR_INCORRECT_STATE;
    return DeviceInstanceInfoProvider::GetLocalConfigDisabled(value);
  }
  CHIP_ERROR SetLocalConfigDisabled(bool value) override {
    if (!active_) return CHIP_ERROR_INCORRECT_STATE;
    return DeviceInstanceInfoProvider::SetLocalConfigDisabled(value);
  }
 private:
  CHIP_ERROR Absent() const {
    return active_ ? CHIP_ERROR_NOT_IMPLEMENTED : CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR Copy(const std::string &value, char *output, std::size_t capacity) const {
    if (!active_) return CHIP_ERROR_INCORRECT_STATE;
    if (output == nullptr || capacity <= value.size()) return CHIP_ERROR_BUFFER_TOO_SMALL;
    std::memcpy(output, value.data(), value.size());
    output[value.size()] = '\0';
    return CHIP_NO_ERROR;
  }
  const BridgeConfiguration &configuration_;
  bool active_{true};
};
} // namespace wotex::matter
#endif
