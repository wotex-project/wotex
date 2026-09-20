#ifndef WOTEX_THREAD_SDK_HPP
#define WOTEX_THREAD_SDK_HPP

#include "protocol.hpp"
#include "dataset.hpp"
#include "storage.hpp"
#include "commissioning.hpp"
#include "joiner.hpp"
#include <openthread/commissioner.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/joiner.h>
#include <openthread/openthread-system.h>
#include <openthread/tasklet.h>
#include <openthread/thread.h>
#include <openthread/platform/radio.h>
#include <mbedtls/build_info.h>
#include <net/if.h>
#include <memory>
#include <optional>
#include <string>

namespace wotex::thread {
static_assert(MBEDTLS_VERSION_NUMBER == 0x03060700, "The host requires the audited Mbed TLS 3.6.7 pin");
class SdkError final : public std::runtime_error {
 public:
  explicit SdkError(const char *code) : std::runtime_error(code) {}
};

class Sdk final {
 public:
  explicit Sdk(const Json &parameters) {
    if (!exact_keys(parameters, {"radio_url", "interface", "storage_path", "storage_mode", "allow_network_creation"}) ||
        !bounded_string(parameters.at("radio_url"), 4096) ||
        !bounded_string(parameters.at("interface"), 15) ||
        !bounded_string(parameters.at("storage_path"), 4096) ||
        !parameters.at("allow_network_creation").is_boolean() ||
        (parameters.at("storage_mode") != "open_existing" && parameters.at("storage_mode") != "create_new")) {
      throw ProtocolError();
    }
    radio_ = parameters.at("radio_url").get<std::string>();
    interface_ = parameters.at("interface").get<std::string>();
    path_ = parameters.at("storage_path").get<std::string>();
    if (!radio(radio_) || !interface_name(interface_) || !storage_path(path_)) throw ProtocolError();
    if (::if_nametoindex(interface_.c_str()) != 0) throw SdkError("interface_in_use");
    storage_ = std::make_unique<Storage>(path_, parameters.at("storage_mode") == "create_new");
    validate_settings_file("settings.data");
    validate_settings_file("settings.Swap");
    // Anchor SDK file operations to the locked directory even if its pathname moves.
    sdk_path_ = "/proc/self/fd/" + std::to_string(storage_->directory());
    allow_creation_ = parameters.at("allow_network_creation").get<bool>();
    otPlatformConfig config {};
    config.mTunDevice = "/dev/net/tun";
    config.mInterfaceName = interface_.c_str();
    config.mCoprocessorUrls.mUrls[0] = radio_.c_str();
    config.mCoprocessorUrls.mNum = 1;
    config.mSpeedUpFactor = 1;
    config.mDataPath = sdk_path_.c_str();
    config.mSettingsFile = "settings";
    instance_ = otSysInit(&config);
    if (instance_ == nullptr) throw SdkError("sdk_start_failed");
    if (config.mCoprocessorType != OT_COPROCESSOR_RCP ||
        otSetStateChangedCallback(instance_, changed, this) != OT_ERROR_NONE) {
      otSysDeinit(); instance_ = nullptr;
      throw SdkError("sdk_start_failed");
    }
    commissioning_ = std::make_unique<Commissioning>(instance_);
    joiner_ = std::make_unique<JoinerOwner>(instance_);
  }
  ~Sdk() { close(); }
  Sdk(const Sdk &) = delete;
  Sdk &operator=(const Sdk &) = delete;

  Json snapshot() const {
    const otDeviceRole role = otThreadGetDeviceRole(instance_);
    const char *name = otThreadGetNetworkName(instance_);
    const std::uint16_t locator = otThreadGetRloc16(instance_);
    const char *role_name = nullptr;
    switch (role) {
      case OT_DEVICE_ROLE_DISABLED: role_name = "disabled"; break;
      case OT_DEVICE_ROLE_DETACHED: role_name = "detached"; break;
      case OT_DEVICE_ROLE_CHILD: role_name = "child"; break;
      case OT_DEVICE_ROLE_ROUTER: role_name = "router"; break;
      case OT_DEVICE_ROLE_LEADER: role_name = "leader"; break;
      default: throw SdkError("invalid_sdk_state");
    }
    return {{"role", role_name}, {"network_name", name == nullptr ? Json(nullptr) : Json(name)},
            {"rloc16", locator == OT_RADIO_INVALID_SHORT_ADDR ? Json(nullptr) : Json(locator)},
            {"ipv6_enabled", otIp6IsEnabled(instance_)}, {"thread_enabled", role != OT_DEVICE_ROLE_DISABLED},
            {"generation", 1}};
  }
  Json inspect(const std::string &operation) const {
    if (operation == "version") return otGetVersionString();
    Json state = snapshot();
    if (operation == "inspect") return state;
    if (operation == "state") return state.at("role");
    if (operation == "network_name") return state.at("network_name");
    if (operation == "rloc16") return state.at("rloc16");
    throw SdkError("not_supported");
  }
  Commissioning &commissioning() { return *commissioning_; }
  JoinerOwner &joiner() { return *joiner_; }
  void form_network(const Json &parameters) {
    if (!exact_keys(parameters, {"dataset"})) throw ProtocolError();
    DatasetValue active(parameters.at("dataset"));
    if (!active.valid(true)) throw DatasetError();
    if (!allow_creation_) throw SdkError("creation_not_allowed");
    if (otThreadGetDeviceRole(instance_) != OT_DEVICE_ROLE_DISABLED) throw SdkError("invalid_state");
    otOperationalDatasetTlvs existing {};
    const otError stored = otDatasetGetActiveTlvs(instance_, &existing);
    if (stored == OT_ERROR_NONE) throw SdkError("dataset_exists");
    if (stored != OT_ERROR_NOT_FOUND) check_status(stored);
    check_status(otDatasetSetActiveTlvs(instance_, &active.tlvs));
    check_status(otIp6SetEnabled(instance_, true));
    check_status(otThreadSetEnabled(instance_, true));
  }
  bool management_busy() const { return management_pending_; }
  void management_set(const std::string &operation, const Json &parameters) {
    if (!exact_keys(parameters, {"dataset"})) throw ProtocolError();
    DatasetValue value(parameters.at("dataset"));
    const bool active = operation == "management_active_set";
    if (!value.valid(active)) throw DatasetError();
    if (management_pending_) throw SdkError("busy");
    // A zero-component Dataset plus raw TLVs preserves unknown fields and order.
    // The pinned SDK copies these bytes before returning; only this stable context remains borrowed.
    otOperationalDataset empty {};
    management_result_.reset();
    management_pending_ = true;
    const otError status = active
        ? otDatasetSendMgmtActiveSet(instance_, &empty, value.tlvs.mTlvs, value.tlvs.mLength, managed, this)
        : otDatasetSendMgmtPendingSet(instance_, &empty, value.tlvs.mTlvs, value.tlvs.mLength, managed, this);
    if (status != OT_ERROR_NONE) { management_pending_ = false; check_status(status); }
  }
  otChangedFlags take_changed_flags() {
    const otChangedFlags flags = changed_flags_;
    changed_flags_ = 0;
    return flags;
  }
  std::optional<otError> management_result() {
    auto result = management_result_;
    management_result_.reset();
    return result;
  }
  Json set_enabled(const Json &parameters) {
    if (!exact_keys(parameters, {"ipv6", "thread"}) || !parameters.at("ipv6").is_boolean() ||
        !parameters.at("thread").is_boolean()) throw ProtocolError();
    const bool ipv6 = parameters.at("ipv6").get<bool>(), thread = parameters.at("thread").get<bool>();
    if (thread && !ipv6) throw SdkError("invalid_state");
    if (thread) {
      otOperationalDatasetTlvs active {};
      if (otDatasetGetActiveTlvs(instance_, &active) != OT_ERROR_NONE ||
          !DatasetValue(dataset_envelope(active)).valid(true)) throw SdkError("dataset_required");
    }
    // Disable Thread before its IP interface; enable IP before Thread.
    if (!thread && otThreadGetDeviceRole(instance_) != OT_DEVICE_ROLE_DISABLED) {
      check_status(otThreadSetEnabled(instance_, false));
    }
    if (otIp6IsEnabled(instance_) != ipv6) check_status(otIp6SetEnabled(instance_, ipv6));
    if (thread && otThreadGetDeviceRole(instance_) == OT_DEVICE_ROLE_DISABLED) {
      check_status(otThreadSetEnabled(instance_, true));
    }
    return snapshot();
  }
  Json dataset(const std::string &operation, const Json &parameters) const {
    const bool active = dataset_kind(parameters, operation == "validate_dataset");
    if (operation == "validate_dataset") {
      DatasetValue value(parameters.at("dataset"));
      if (!value.valid(active)) throw DatasetError();
      return nullptr;
    }
    otOperationalDatasetTlvs tlvs {};
    const otError error = active ? otDatasetGetActiveTlvs(instance_, &tlvs) : otDatasetGetPendingTlvs(instance_, &tlvs);
    if (error == OT_ERROR_NOT_FOUND) throw SdkError("dataset_not_found");
    if (error != OT_ERROR_NONE) throw SdkError("invalid_sdk_state");
    return dataset_envelope(tlvs);
  }
  void update(otSysMainloopContext &mainloop) {
    otTaskletsProcess(instance_);
    if (otTaskletsArePending(instance_)) mainloop.mTimeout = {0, 0};
    otSysMainloopUpdate(instance_, &mainloop);
  }
  void process(const otSysMainloopContext &mainloop) { otSysMainloopProcess(instance_, &mainloop); }
  void close() {
    if (instance_ != nullptr) {
      joiner_->close();
      commissioning_->close();
      otRemoveStateChangeCallback(instance_, changed, this);
      (void)otThreadSetEnabled(instance_, false);
      (void)otIp6SetEnabled(instance_, false);
      otSysDeinit();
      instance_ = nullptr;
      joiner_.reset();
      commissioning_.reset();
    }
    storage_.reset();
  }
 private:
  static void check_status(otError error) {
    // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is thrown as a value; the host reports it as remote_error
    if (error != OT_ERROR_NONE) throw error;
  }
  static void managed(otError status, void *context) {
    auto *sdk = static_cast<Sdk *>(context);
    sdk->management_pending_ = false;
    sdk->management_result_ = status;
  }
  static void changed(otChangedFlags flags, void *context) {
    static_cast<Sdk *>(context)->changed_flags_ |= flags;
  }
  static bool interface_name(const std::string &name) {
    for (char value : name) {
      if (!((value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') ||
            (value >= '0' && value <= '9') || value == '_' || value == '.' || value == '-')) return false;
    }
    return name.front() != '.' && name.front() != '_' && name.front() != '-';
  }
  static bool radio(const std::string &url) {
    for (unsigned char byte : url) if (byte <= 32 || byte == 127 || byte == '#') return false;
    for (std::string_view prefix : {"spinel+hdlc+uart:///", "spinel+hdlc+forkpty:///", "spinel+spi:///"}) {
      if (url.compare(0, prefix.size(), prefix) == 0 && url.size() > prefix.size() &&
          url[prefix.size()] != '?') return true;
    }
    return false;
  }
  static bool storage_path(const std::string &path) {
    if (path.size() < 2 || path.front() != '/') return false;
    for (unsigned char byte : path) if (byte < 32 || byte == 127) return false;
    return true;
  }
  void validate_settings_file(const char *name) {
    struct stat info {};
    if (::fstatat(storage_->directory(), name, &info, AT_SYMLINK_NOFOLLOW) < 0) {
      if (errno == ENOENT) return;
      throw StorageError();
    }
    if (!S_ISREG(info.st_mode) || (info.st_mode & 0777) != 0600 ||
        info.st_uid != ::geteuid() || info.st_nlink != 1) throw StorageError();
  }
  std::string radio_, interface_, path_, sdk_path_;
  std::unique_ptr<Storage> storage_;
  std::unique_ptr<Commissioning> commissioning_;
  std::unique_ptr<JoinerOwner> joiner_;
  otInstance *instance_ = nullptr;
  otChangedFlags changed_flags_ = 0;
  bool allow_creation_ = false;
  bool management_pending_ = false;
  std::optional<otError> management_result_;
};
}  // namespace wotex::thread
#endif
