#ifndef WOTEX_MATTER_BRIDGE_ETHERNET_HPP
#define WOTEX_MATTER_BRIDGE_ETHERNET_HPP
#include <platform/NetworkCommissioning.h>
#include <cstring>
#include <net/if.h>
#include <new>
#include <string>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace wotex::matter {
// One explicitly selected externally configured interface. No interface
// discovery, configuration, connect/retry or invented connected state occurs.
// Kernel link flags are sampled for each bounded one-entry SDK iterator.
class BridgeEthernet final : public chip::DeviceLayer::NetworkCommissioning::EthernetDriver {
 public:
  explicit BridgeEthernet(std::string interface) : interface_(std::move(interface)) {}
  CHIP_ERROR Init(NetworkStatusChangeCallback *) override {
    if (used_ || interface_.empty() || interface_.size() >= IFNAMSIZ ||
        interface_.find('\0') != interface_.npos)
      return CHIP_ERROR_INVALID_ARGUMENT;
    used_ = true;
    bool connected = false;
    if (!Sample(connected)) return CHIP_ERROR_READ_FAILED;
    active_ = true;
    return CHIP_NO_ERROR;
  }
  void Shutdown() override { active_ = false; }
  std::uint8_t GetMaxNetworks() override { return 1; }
  chip::DeviceLayer::NetworkCommissioning::NetworkIterator *GetNetworks() override {
    if (!active_) return nullptr;
    bool connected = false;
    if (!Sample(connected)) return nullptr;
    return new (std::nothrow) Single(interface_, connected);
  }
 private:
  class Single final : public chip::DeviceLayer::NetworkCommissioning::NetworkIterator {
   public:
    Single(const std::string &name, bool connected) {
      std::memcpy(network_.networkID, name.data(), name.size());
      network_.networkIDLen = static_cast<std::uint8_t>(name.size());
      network_.connected = connected;
    }
    std::size_t Count() override { return 1; }
    bool Next(chip::DeviceLayer::NetworkCommissioning::Network &result) override {
      if (returned_) return false;
      returned_ = true;
      result = network_;
      return true;
    }
    void Release() override { delete this; }
   private:
    chip::DeviceLayer::NetworkCommissioning::Network network_{};
    bool returned_{false};
  };
  bool Sample(bool &connected) const {
    const int descriptor = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (descriptor < 0) return false;
    ifreq request{};
    std::memcpy(request.ifr_name, interface_.data(), interface_.size());
    const int status = ioctl(descriptor, SIOCGIFFLAGS, &request);
    close(descriptor);
    if (status != 0) return false;
    connected = (request.ifr_flags & IFF_UP) != 0 && (request.ifr_flags & IFF_RUNNING) != 0;
    return true;
  }
  const std::string interface_;
  bool used_{false}, active_{false};
};
} // namespace wotex::matter
#endif
