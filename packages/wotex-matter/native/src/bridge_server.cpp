#include "wotex_matter/bridge_server.hpp"
#include "wotex_matter/bridge_resources.hpp"
#include "wotex_matter/sdk_storage.hpp"

#include <app/InteractionModelEngine.h>
#include <app/SafeAttributePersistenceProvider.h>
#include <app/persistence/AttributePersistenceProvider.h>
#include <app/persistence/AttributePersistenceProviderInstance.h>
#include <app/clusters/network-commissioning/CodegenInstance.h>
#include <app/server/Server.h>
#include <app/server/Dnssd.h>
#include <app/util/endpoint-config-api.h>
#include <credentials/DeviceAttestationCredsProvider.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>

#include <cstdlib>

namespace wotex::matter {
namespace {

constexpr char kModelDigest[] = "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671";

class ClosedAttributeStore final : public chip::app::SafeAttributePersistenceProvider {
 public:
  CHIP_ERROR SafeWriteValue(const chip::app::ConcreteAttributePath &,
                            const chip::ByteSpan &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR SafeReadValue(const chip::app::ConcreteAttributePath &,
                           chip::MutableByteSpan &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR SafeDeleteValue(const chip::app::ConcreteAttributePath &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
};

ClosedAttributeStore closed_attribute_store;

class ClosedClusterAttributeStore final : public chip::app::AttributePersistenceProvider {
 public:
  CHIP_ERROR WriteValue(const chip::app::ConcreteAttributePath &, const chip::ByteSpan &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR ReadValue(const chip::app::ConcreteAttributePath &, chip::MutableByteSpan &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
};

ClosedClusterAttributeStore closed_cluster_attribute_store;

class ServerStore final : public chip::PersistentStorageDelegate {
 public:
  explicit ServerStore(BridgeStorage &storage) : storage_(storage) {}

  CHIP_ERROR SyncGetKeyValue(const char *key, void *buffer, std::uint16_t &size) override {
    if (!active_) {
      return CHIP_ERROR_INCORRECT_STATE;
    }
    return Check(storage_.SyncGetKeyValue(key, buffer, size));
  }
  CHIP_ERROR SyncSetKeyValue(const char *key, const void *value, std::uint16_t size) override {
    if (!active_) {
      return CHIP_ERROR_INCORRECT_STATE;
    }
    return Check(storage_.SyncSetKeyValue(key, value, size));
  }
  CHIP_ERROR SyncDeleteKeyValue(const char *key) override {
    if (!active_) {
      return CHIP_ERROR_INCORRECT_STATE;
    }
    return Check(storage_.SyncDeleteKeyValue(key));
  }

  CHIP_ERROR Check(CHIP_ERROR error) const {
    VerifyHealthy();
    return error;
  }

  void VerifyHealthy() const {
    if (storage_.poisoned()) {
      // Exit before returning to SDK code that can retain cached fabric or
      // attribute data. Kernel teardown releases this process's store lock.
      std::_Exit(SdkBridgeServerBinding::kStoreFailureExit);
    }
  }

  bool active() const { return active_; }
  void Close() { active_ = false; }

 private:
  BridgeStorage &storage_;
  bool active_{true};
};

} // namespace

class SdkBridgeServerBinding::Impl final {
 public:
  Impl(BridgeStorage &storage, BridgeConsumerHandoff &handoff)
      : storage_(storage), handoff_(handoff), delegate_(storage) {}

  ~Impl() {
    if (initialized_) {
      // Destruction must not leave SDK pointers referring to released native
      // resources. Only the serialized owner can perform a normal shutdown.
      std::_Exit(kStartupFailureExit);
    }
  }

  CHIP_ERROR Init(chip::app::DataModel::Provider &model,
                  chip::DeviceLayer::NetworkCommissioning::EthernetDriver &network,
                  const chip::Inet::InterfaceId &interface_id, std::uint16_t port) {
    if (used_ || handoff_.closed() || handoff_.pending() != 0 || !interface_id.IsPresent() ||
        port == 0 || !chip::Credentials::IsDeviceAttestationCredentialsProviderSet() ||
        storage_.identity().model_sha256 != kModelDigest) {
      return CHIP_ERROR_INVALID_ARGUMENT;
    }
    std::uint16_t vendor = 0;
    std::uint16_t product = 0;
    auto *info = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
    if (info->GetVendorId(vendor) != CHIP_NO_ERROR ||
        info->GetProductId(product) != CHIP_NO_ERROR || vendor != storage_.identity().vendor_id ||
        product != storage_.identity().product_id) {
      return CHIP_ERROR_INVALID_ARGUMENT;
    }
    std::uint8_t certificate[1024];
    chip::MutableByteSpan certificate_span(certificate);
    chip::Crypto::AttestationCertVidPid ids;
    auto *dac = chip::Credentials::GetDeviceAttestationCredentialsProvider();
    if (dac->GetDeviceAttestationCert(certificate_span) != CHIP_NO_ERROR ||
        chip::Crypto::ExtractVIDPIDFromX509Cert(certificate_span, ids) != CHIP_NO_ERROR ||
        !ids.mVendorId.HasValue() || !ids.mProductId.HasValue() ||
        static_cast<std::uint16_t>(ids.mVendorId.Value()) != vendor ||
        ids.mProductId.Value() != product) {
      return CHIP_ERROR_INVALID_ARGUMENT;
    }
    delegate_.VerifyHealthy();
    used_ = true;
    CHIP_ERROR error = sdk_storage_.Init(delegate_);
    if (error != CHIP_NO_ERROR) {
      Finish();
      return error;
    }
    groups_.SetStorageDelegate(&delegate_);
    groups_.SetSessionKeystore(&session_keys_);
    error = groups_.Init();
    if (error != CHIP_NO_ERROR) {
      Finish();
      return error;
    }
    groups_initialized_ = true;

    chip::ServerInitParams params;
    params.persistentStorageDelegate = &delegate_;
    params.operationalKeystore = &sdk_storage_.operational_keystore();
    params.opCertStore = &sdk_storage_.certificate_store();
    params.groupDataProvider = &groups_;
    params.sessionKeystore = &session_keys_;
    params.accessDelegate = chip::Access::Examples::GetAccessControlDelegate();
    params.aclStorage = &acl_storage_;
    params.reportScheduler = scheduler_.get();
    params.dataModelProvider = &model;
    params.interfaceId = interface_id;
    params.operationalServicePort = port;
    params.advertiseCommissionableIfNoFabrics = false;

    // Server::Init retains injected pointers and has no complete failure
    // rollback. This binding belongs to a disposable, separately owned host.
    if (chip::Server::GetInstance().Init(params) != CHIP_NO_ERROR) {
      std::_Exit(kStartupFailureExit);
    }
    initialized_ = true;
    network_ = std::make_unique<chip::app::Clusters::NetworkCommissioning::Instance>(0, &network);
    if (network_->Init() != CHIP_NO_ERROR || !emberAfEndpointEnableDisable(2, false)) {
      std::_Exit(kStartupFailureExit);
    }
    delegate_.VerifyHealthy();
    return CHIP_NO_ERROR;
  }

  void Finish() {
    handoff_.Close();
    if (handoff_.pending() != 0) std::_Exit(kStartupFailureExit);
    if (initialized_) {
      // Server shutdown closes the advertiser without releasing its records.
      // Stop discovery while SDK memory and the borrowed fabric table are live.
      chip::app::DnssdServer::Instance().StopServer();
      network_->Shutdown();
      network_.reset();
      chip::Server::GetInstance().Shutdown();
      chip::Server::GetInstance().GetFabricTable().Shutdown();
      chip::app::InteractionModelEngine::GetInstance()->SetDataModelProvider(nullptr);
      chip::app::CodegenDataModelProvider::Instance().SetPersistentStorageDelegate(nullptr);
      // The SDK setter ignores nullptr. Replace the persistence provider with
      // a process-lifetime refusal provider before releasing its store.
      chip::app::SetSafeAttributePersistenceProvider(&closed_attribute_store);
      // Independent server clusters use a second persistence provider. Its
      // global setter also ignores nullptr and its SDK default retains the
      // borrowed storage delegate after model shutdown.
      chip::app::SetAttributePersistenceProvider(&closed_cluster_attribute_store);
      initialized_ = false;
    }
    if (groups_initialized_) {
      groups_.Finish();
      groups_initialized_ = false;
    }
    sdk_storage_.Finish();
    delegate_.Close();
    used_ = true;
  }

  BridgeStorage &storage_;
  BridgeConsumerHandoff &handoff_;
  ServerStore delegate_;
  SdkStorageBinding sdk_storage_;
  chip::Crypto::DefaultSessionKeystore session_keys_;
  chip::Credentials::GroupDataProviderImpl groups_;
  chip::app::DefaultAclStorage acl_storage_;
  chip::app::DefaultTimerDelegate timers_;
  std::unique_ptr<chip::app::reporting::ReportScheduler> scheduler_{
      MakeBridgeReportScheduler(timers_)};
  std::unique_ptr<chip::app::Clusters::NetworkCommissioning::Instance> network_;
  bool used_{false};
  bool initialized_{false};
  bool groups_initialized_{false};
};

SdkBridgeServerBinding::SdkBridgeServerBinding(BridgeStorage &storage,
                                               BridgeConsumerHandoff &handoff)
    : impl_(std::make_unique<Impl>(storage, handoff)) {}

SdkBridgeServerBinding::~SdkBridgeServerBinding() = default;

chip::PersistentStorageDelegate &SdkBridgeServerBinding::storage_delegate() {
  return impl_->delegate_;
}

BridgeStorage &SdkBridgeServerBinding::bridge_storage() { return impl_->storage_; }

CHIP_ERROR SdkBridgeServerBinding::Init(
    chip::app::DataModel::Provider &model,
    chip::DeviceLayer::NetworkCommissioning::EthernetDriver &network,
    const chip::Inet::InterfaceId &interface_id, std::uint16_t port) {
  return impl_->Init(model, network, interface_id, port);
}

void SdkBridgeServerBinding::Finish() { impl_->Finish(); }

bool SdkBridgeServerBinding::initialized() const { return impl_->initialized_; }

CHIP_ERROR SdkBridgeServerBinding::Allocate(const std::string &thing_id, BridgedDeviceType type,
                                            BridgeEndpoint &endpoint) {
  if (!impl_->delegate_.active()) {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  return impl_->delegate_.Check(impl_->storage_.Allocate(thing_id, type, endpoint));
}

CHIP_ERROR SdkBridgeServerBinding::Remove(const std::string &thing_id) {
  if (!impl_->delegate_.active()) {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  return impl_->delegate_.Check(impl_->storage_.Remove(thing_id));
}

} // namespace wotex::matter
