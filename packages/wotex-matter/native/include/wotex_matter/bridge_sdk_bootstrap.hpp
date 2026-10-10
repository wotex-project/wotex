#ifndef WOTEX_MATTER_BRIDGE_SDK_BOOTSTRAP_HPP
#define WOTEX_MATTER_BRIDGE_SDK_BOOTSTRAP_HPP

#include "wotex_matter/bridge_bootstrap.hpp"
#include "bridge_device_info.hpp"
#include "bridge_ethernet.hpp"
#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_provider.hpp"
#include <app/InteractionModelEngine.h>
#include <app/server/Server.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <data-model-providers/codegen/Instance.h>
#include <platform/CHIPDeviceLayer.h>
#include <cstdlib>
#include <fcntl.h>
#include <unistd.h>

namespace wotex::matter {

// Internal resource owner. The caller initializes SDK memory and supplies a
// successfully loaded bootstrap, receiver, custody and closed provider that
// outlive this owner. Configuration remains unchanged through this lifetime.
// The caller owns request closure/drain before Stop and Finish, and admission
// before Start. Init/Finish acquire the SDK lock; Start/Stop run outside that
// lock and Stop runs outside the SDK event loop. All calls are serialized.
// No ready/closed receipt, clock qualification or command authority is
// established by this resource owner.
class SdkBridgeBootstrap final {
 public:
  SdkBridgeBootstrap(BridgeBootstrap &bootstrap, BridgeConsumerHandoff &custody,
                     BridgeReceiver &receiver,
                     chip::DeviceLayer::CommissionableDataProvider &retired)
      : bootstrap_(bootstrap), custody_(custody), receiver_(receiver), retired_(retired),
        information_(*bootstrap.configuration), ethernet_(bootstrap.configuration->interface) {}
  ~SdkBridgeBootstrap() {
    if (platform_ || loop_ || previous_directory_ >= 0)
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  }
  SdkBridgeBootstrap(const SdkBridgeBootstrap &) = delete;
  SdkBridgeBootstrap &operator=(const SdkBridgeBootstrap &) = delete;

  CHIP_ERROR Init() {
    using namespace chip;
    if (used_) return CHIP_ERROR_INCORRECT_STATE;
    used_ = true;
    if (custody_.closed() || custody_.pending() != 0) return CHIP_ERROR_INCORRECT_STATE;
    const auto &configuration = *bootstrap_.configuration;
    Inet::InterfaceId interface;
    ReturnErrorOnFailure(
        Inet::InterfaceId::InterfaceNameToId(configuration.interface.c_str(), interface));
    try {
      ReturnErrorOnFailure(BridgeStorage::Open(configuration.store_path, configuration.store_mode,
                                               configuration.identity, store_));
    } catch (const std::bad_alloc &) {
      store_.reset();
      return CHIP_ERROR_NO_MEMORY;
    }
    previous_directory_ = open(".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (previous_directory_ < 0) return CHIP_ERROR_READ_FAILED;
    const auto entered = store_->EnterProcessDirectory();
    if (entered != CHIP_NO_ERROR) {
      close(previous_directory_);
      previous_directory_ = -1;
      return entered;
    }
    original_dac_ = Credentials::GetDeviceAttestationCredentialsProvider();
    Credentials::SetDeviceAttestationCredentialsProvider(bootstrap_.credentials.get());
    DeviceLayer::SetCommissionableDataProvider(bootstrap_.credentials.get());
    // Partial platform startup is process-fatal; it cannot produce a receipt
    // pretending that SDK resource cleanup or a usable server was established.
    if (DeviceLayer::PlatformMgr().InitChipStack() != CHIP_NO_ERROR)
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    platform_ = true;
    original_information_ = DeviceLayer::GetDeviceInstanceInfoProvider();
    DeviceLayer::SetDeviceInstanceInfoProvider(&information_);
    DeviceLayer::PlatformMgr().LockChipStack();
    try {
      server_ = std::make_unique<SdkBridgeServerBinding>(*store_, custody_);
      auto *generated = app::CodegenDataModelProviderInstance(&server_->storage_delegate());
      provider_ = std::make_unique<SdkBridgeProviderBinding>(*generated, receiver_);
      if (server_->Init(*provider_, ethernet_, interface, configuration.port) != CHIP_NO_ERROR)
        std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
      if (configuration.store_mode == StorageMode::CreateNew) {
        for (const auto &device : configuration.devices) {
          BridgeEndpoint endpoint;
          if (server_->Allocate(device.thing_id, device.device_type, endpoint) != CHIP_NO_ERROR)
            std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
        }
      }
      endpoints_ = std::make_unique<SdkBridgeEndpointBinding>(*server_);
      if (endpoints_->Init(configuration.devices) != CHIP_NO_ERROR)
        std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
      auto &window = Server::GetInstance().GetCommissioningWindowManager();
      if (window.IsCommissioningWindowOpen())
        std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
      if (configuration.commissioning_window_seconds != 0 &&
          window.OpenBasicCommissioningWindow(
              System::Clock::Seconds32(configuration.commissioning_window_seconds),
              CommissioningWindowAdvertisement::kDnssdOnly) != CHIP_NO_ERROR)
        std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    } catch (const std::bad_alloc &) {
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    }
    DeviceLayer::PlatformMgr().UnlockChipStack();
    return CHIP_NO_ERROR;
  }

  CHIP_ERROR Start() {
    if (!platform_ || loop_ || started_) return CHIP_ERROR_INCORRECT_STATE;
    const auto status = chip::DeviceLayer::PlatformMgr().StartEventLoopTask();
    if (status == CHIP_NO_ERROR) loop_ = started_ = true;
    return status;
  }
  CHIP_ERROR Stop() {
    if (!platform_ || !loop_) return CHIP_ERROR_INCORRECT_STATE;
    const auto status = chip::DeviceLayer::PlatformMgr().StopEventLoopTask();
    if (status == CHIP_NO_ERROR) loop_ = false;
    return status;
  }
  void Finish() {
    using namespace chip;
    if (!platform_) return;
    if (loop_) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    DeviceLayer::PlatformMgr().LockChipStack();
    if (!custody_.closed() || custody_.pending() != 0)
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    Server::GetInstance().GetCommissioningWindowManager().CloseCommissioningWindow();
    endpoints_->Finish();
    server_->Finish();
    app::CodegenDataModelProvider::Instance().SetPersistentStorageDelegate(nullptr);
    DeviceLayer::SetDeviceInstanceInfoProvider(original_information_);
    Credentials::SetDeviceAttestationCredentialsProvider(original_dac_);
    DeviceLayer::SetCommissionableDataProvider(&retired_);
    information_.Retire();
    endpoints_.reset();
    provider_.reset();
    server_.reset();
    DeviceLayer::PlatformMgr().UnlockChipStack();
    DeviceLayer::PlatformMgr().Shutdown();
    platform_ = false;
    if (fchdir(previous_directory_) != 0 || close(previous_directory_) != 0)
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    previous_directory_ = -1;
    store_.reset();
  }
  SdkBridgeProviderBinding *provider() noexcept { return provider_.get(); }
  SdkBridgeEndpointBinding *endpoints() noexcept { return endpoints_.get(); }

 private:
  BridgeBootstrap &bootstrap_;
  BridgeConsumerHandoff &custody_;
  BridgeReceiver &receiver_;
  chip::DeviceLayer::CommissionableDataProvider &retired_;
  BridgeDeviceInfo information_;
  BridgeEthernet ethernet_;
  std::unique_ptr<BridgeStorage> store_;
  std::unique_ptr<SdkBridgeServerBinding> server_;
  std::unique_ptr<SdkBridgeProviderBinding> provider_;
  std::unique_ptr<SdkBridgeEndpointBinding> endpoints_;
  chip::Credentials::DeviceAttestationCredentialsProvider *original_dac_{nullptr};
  chip::DeviceLayer::DeviceInstanceInfoProvider *original_information_{nullptr};
  int previous_directory_{-1};
  bool used_{false}, platform_{false}, loop_{false}, started_{false};
};
} // namespace wotex::matter
#endif
