#ifndef WOTEX_MATTER_BRIDGE_SERVER_HPP
#define WOTEX_MATTER_BRIDGE_SERVER_HPP

#include "wotex_matter/bridge_storage.hpp"

#include <app/data-model-provider/Provider.h>
#include <inet/InetInterface.h>
#include <platform/NetworkCommissioning.h>

#include <memory>

namespace wotex::matter {

// Internal native-process binding. The owner explicitly initializes memory,
// providers and PlatformMgr, holds the SDK stack lock for Init/Finish, and
// stops the event loop before Finish. The store, model and Ethernet driver
// outlive this binding. Each process has one SDK server lifetime.
//
// A poisoned store or an incomplete SDK Server::Init terminates this native
// process. The SDK cannot roll back a partial initialization or keep serving
// cached values after a failed durable write. The outer Port owner must reap
// that process and classify its exit; it must not retry a mutation.
class SdkBridgeServerBinding final {
 public:
  static constexpr int kStoreFailureExit = 74;
  static constexpr int kStartupFailureExit = 70;

  explicit SdkBridgeServerBinding(BridgeStorage &storage);
  ~SdkBridgeServerBinding();
  SdkBridgeServerBinding(const SdkBridgeServerBinding &) = delete;
  SdkBridgeServerBinding &operator=(const SdkBridgeServerBinding &) = delete;

  chip::PersistentStorageDelegate &storage_delegate();
  CHIP_ERROR Init(chip::app::DataModel::Provider &model,
                  chip::DeviceLayer::NetworkCommissioning::EthernetDriver &network,
                  const chip::Inet::InterfaceId &interface_id, std::uint16_t port);
  void Finish();
  bool initialized() const;

  CHIP_ERROR Allocate(const std::string &thing_id, BridgedDeviceType type,
                      BridgeEndpoint &endpoint);
  CHIP_ERROR Remove(const std::string &thing_id);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace wotex::matter

#endif
