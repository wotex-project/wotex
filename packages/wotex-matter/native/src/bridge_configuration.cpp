#include "wotex_matter/bridge_configuration.hpp"
#include "wotex_matter/bridge_control.hpp"
#include <nlohmann/json.hpp>
#include <new>
#include <stdexcept>

namespace wotex::matter {
namespace {
bool Path(std::string_view value) {
  if (value.empty() || value.size() > 4096 || value.front() != '/' || value.back() == '/' ||
      value.find_first_of(std::string_view("\0\n\r", 3)) != value.npos)
    return false;
  for (std::size_t begin = 1; begin < value.size();) {
    const auto end = value.find('/', begin);
    const std::string_view segment(value.data() + begin,
                                   end == value.npos ? value.size() - begin : end - begin);
    if (segment.empty() || segment == "." || segment == "..") return false;
    if (end == value.npos) return true;
    begin = end + 1;
  }
  return false;
}
bool Opaque(std::string_view hex, std::string &value) {
  if (hex.empty() || hex.size() > 512 || (hex.size() & 1u)) return false;
  const auto digit = [](char byte) -> int {
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    return -1;
  };
  std::string result;
  result.reserve(hex.size() / 2);
  for (std::size_t i = 0; i < hex.size(); i += 2) {
    const int high = digit(hex[i]), low = digit(hex[i + 1]);
    if (high < 0 || low < 0) return false;
    result += static_cast<char>((high << 4) | low);
  }
  value.swap(result);
  return true;
}

class Sax final : public nlohmann::json_sax<nlohmann::json> {
 public:
  bool null() override {
    if (role_ != Role::Device || !pending_ || (field_ != Minimum && field_ != Maximum))
      return false;
    pending_ = false;
    return true;
  }
  bool boolean(bool) override { return false; }
  bool binary(binary_t &) override { return false; }
  bool number_float(number_float_t, const string_t &) override { return false; }
  bool number_integer(number_integer_t value) override {
    // JSON -0 is still integer zero. Root bounds remain the same after this
    // signed parser representation is converted without changing its value.
    if (role_ == Role::Root && value >= 0)
      return number_unsigned(static_cast<number_unsigned_t>(value));
    if (role_ != Role::Device || !pending_ || (field_ != Minimum && field_ != Maximum) ||
        value < -27315 || value > 32767)
      return false;
    return Temperature(value);
  }
  bool number_unsigned(number_unsigned_t value) override {
    if (!pending_) return false;
    if (role_ == Role::Root) {
      if (field_ == Vendor && value > 0 && value < 65535) configuration.identity.vendor_id = value;
      else if (field_ == Product && value > 0 && value <= 65535)
        configuration.identity.product_id = value;
      else if (field_ == Port && value > 0 && value <= 65535) configuration.port = value;
      else if (field_ == HardwareVersion && value <= 65535) configuration.hardware_version = value;
      else if (field_ == Window && (value == 0 || (value >= 180 && value <= 900)))
        configuration.commissioning_window_seconds = value;
      else return false;
    } else if (role_ == Role::Device) {
      if (field_ == DeviceType && (value == 0x0100 || value == 0x0302))
        device_.device_type = static_cast<BridgedDeviceType>(value);
      else if ((field_ == Minimum || field_ == Maximum) && value <= 32767)
        return Temperature(static_cast<std::int64_t>(value));
      else return false;
    } else return false;
    pending_ = false;
    return true;
  }
  bool string(string_t &value) override {
    if (!pending_) return false;
    bool accepted = false;
    if (role_ == Role::Device) {
      if (field_ == Thing) accepted = Opaque(value, device_.thing_id);
      else if (field_ == Label && value.size() <= 32) {
        device_.node_label = value;
        accepted = true;
      }
    } else if (role_ == Role::Root) {
      switch (field_) {
      case Schema:
        accepted = value == "wotex.matter.bridge-bootstrap@1";
        break;
      case Revision:
        accepted = value == kBridgeSdkRevision;
        break;
      case Model:
        accepted = value == kBridgeModelSha256;
        if (accepted) configuration.identity.model_sha256 = value;
        break;
      case Bridge:
        accepted = Opaque(value, configuration.identity.bridge_id);
        break;
      case StoreMode:
        accepted = value == "new" || value == "reopen";
        if (accepted)
          configuration.store_mode = value == "new" ? StorageMode::CreateNew
                                                    : StorageMode::OpenExisting;
        break;
      case Interface:
        accepted = !value.empty() && value.size() <= 15 &&
            value.find_first_of(std::string_view("\0\n\r", 3)) == value.npos;
        if (accepted) configuration.interface = value;
        break;
      case VendorName:
      case ProductName:
      case HardwareString:
        accepted = !value.empty() && value.size() <= (field_ == HardwareString ? 64u : 32u) &&
            value.find('\0') == value.npos;
        if (accepted) {
          auto &name = field_ == VendorName ? configuration.vendor_name
              : field_ == ProductName       ? configuration.product_name
                                            : configuration.hardware_version_string;
          name = value;
        }
        break;
      default:
        if (field_ == StorePath || field_ == Dac || field_ == Pai || field_ == Declaration ||
            field_ == Key || field_ == Commissioning) {
          accepted = Path(value);
          if (accepted) {
            auto *path = field_ == StorePath ? &configuration.store_path
                : field_ == Dac              ? &configuration.dac_path
                : field_ == Pai              ? &configuration.pai_path
                : field_ == Declaration      ? &configuration.declaration_path
                : field_ == Key              ? &configuration.key_path
                                             : &configuration.commissioning_path;
            *path = value;
          }
        }
      }
    }
    pending_ = false;
    return accepted;
  }
  bool start_object(std::size_t) override {
    if (role_ == Role::None && !started_ && !closed_) {
      started_ = true;
      role_ = Role::Root;
      return true;
    }
    if (role_ == Role::Devices && configuration.devices.size() < 16) {
      device_ = {};
      device_seen_ = 0;
      role_ = Role::Device;
      return true;
    }
    return false;
  }
  bool key(string_t &key) override {
    if (pending_) return false;
    if (role_ == Role::Root) {
      if (key == "schema") field_ = Schema;
      else if (key == "sdk_revision") field_ = Revision;
      else if (key == "model_sha256") field_ = Model;
      else if (key == "bridge_id") field_ = Bridge;
      else if (key == "vendor_id") field_ = Vendor;
      else if (key == "product_id") field_ = Product;
      else if (key == "store_path") field_ = StorePath;
      else if (key == "store_mode") field_ = StoreMode;
      else if (key == "interface") field_ = Interface;
      else if (key == "port") field_ = Port;
      else if (key == "dac_path") field_ = Dac;
      else if (key == "pai_path") field_ = Pai;
      else if (key == "declaration_path") field_ = Declaration;
      else if (key == "key_path") field_ = Key;
      else if (key == "commissioning_path") field_ = Commissioning;
      else if (key == "devices") field_ = Devices;
      else if (key == "vendor_name") field_ = VendorName;
      else if (key == "product_name") field_ = ProductName;
      else if (key == "hardware_version") field_ = HardwareVersion;
      else if (key == "hardware_version_string") field_ = HardwareString;
      else if (key == "commissioning_window_seconds") field_ = Window;
      else return false;
      if (root_seen_ & field_) return false;
      root_seen_ |= field_;
    } else if (role_ == Role::Device) {
      if (key == "thing_id") field_ = Thing;
      else if (key == "device_type") field_ = DeviceType;
      else if (key == "node_label") field_ = Label;
      else if (key == "minimum_temperature") field_ = Minimum;
      else if (key == "maximum_temperature") field_ = Maximum;
      else return false;
      if (device_seen_ & field_) return false;
      device_seen_ |= field_;
    } else return false;
    pending_ = true;
    return true;
  }
  bool end_object() override {
    if (pending_) return false;
    if (role_ == Role::Device) {
      if (device_seen_ != 31) return false;
      const auto minimum = device_.minimum_temperature, maximum = device_.maximum_temperature;
      if (device_.device_type == BridgedDeviceType::OnOffLight) {
        if (minimum || maximum) return false;
      } else if ((minimum && *minimum > 32766) || (maximum && *maximum < -27314) ||
                 (minimum && maximum && *maximum <= *minimum))
        return false;
      for (const auto &existing : configuration.devices)
        if (existing.thing_id == device_.thing_id) return false;
      configuration.devices.push_back(std::move(device_));
      role_ = Role::Devices;
      return true;
    }
    if (role_ != Role::Root || root_seen_ != 2097151) return false;
    role_ = Role::None;
    closed_ = true;
    return true;
  }
  bool start_array(std::size_t) override {
    if (role_ != Role::Root || !pending_ || field_ != Devices) return false;
    pending_ = false;
    role_ = Role::Devices;
    return true;
  }
  bool end_array() override {
    if (role_ != Role::Devices) return false;
    role_ = Role::Root;
    return true;
  }
  bool parse_error(std::size_t, const std::string &, const nlohmann::detail::exception &) override {
    return false;
  }
  bool finished() const { return closed_; }
  BridgeConfiguration configuration;
 private:
  bool Temperature(std::int64_t value) {
    auto &bound = field_ == Minimum ? device_.minimum_temperature : device_.maximum_temperature;
    bound = static_cast<std::int16_t>(value);
    pending_ = false;
    return true;
  }
  enum class Role { None, Root, Devices, Device };
  enum Field : std::uint32_t {
    Schema = 1,
    Revision = 2,
    Model = 4,
    Bridge = 8,
    Vendor = 16,
    Product = 32,
    StorePath = 64,
    StoreMode = 128,
    Interface = 256,
    Port = 512,
    Dac = 1024,
    Pai = 2048,
    Declaration = 4096,
    Key = 8192,
    Commissioning = 16384,
    Devices = 32768,
    VendorName = 65536,
    ProductName = 131072,
    HardwareVersion = 262144,
    HardwareString = 524288,
    Window = 1048576,
    Thing = 1,
    DeviceType = 2,
    Label = 4,
    Minimum = 8,
    Maximum = 16
  };
  Role role_{Role::None};
  Field field_{Schema};
  std::uint32_t root_seen_{0}, device_seen_{0};
  BridgeDeviceConfiguration device_;
  bool started_{false}, closed_{false}, pending_{false};
};
} // namespace

BridgeConfigurationDecode DecodeBridgeConfiguration(
    std::string_view bytes, std::unique_ptr<BridgeConfiguration> &result) noexcept {
  using R = BridgeConfigurationDecode;
  if (bytes.size() > 65'536) return R::Oversized;
  if (bytes.empty() || bytes.find('\0') != bytes.npos) return R::Malformed;
  try {
    Sax sax;
    if (!nlohmann::json::sax_parse(bytes.begin(), bytes.end(), &sax) || !sax.finished())
      return R::Malformed;
    auto owned = std::make_unique<BridgeConfiguration>(std::move(sax.configuration));
    result.swap(owned);
    return R::Decoded;
  } catch (const std::bad_alloc &) {
    return R::NoMemory;
  } catch (const std::length_error &) {
    return R::NoMemory;
  }
}
} // namespace wotex::matter
