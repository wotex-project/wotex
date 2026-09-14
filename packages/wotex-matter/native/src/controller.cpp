#include "wotex_matter/controller.hpp"

#include "wotex_matter/authority.hpp"
#include "wotex_matter/sdk_storage.hpp"
#include "wotex_matter/storage.hpp"

#include <controller/CHIPDeviceControllerFactory.h>
#include <credentials/GroupDataProviderImpl.h>
#include <credentials/attestation_verifier/DefaultDeviceAttestationVerifier.h>
#include <credentials/attestation_verifier/FileAttestationTrustStore.h>
#include <crypto/RawKeySessionKeystore.h>
#include <data-model-providers/codegen/Instance.h>
#include <lib/core/CHIPVendorIdentifiers.hpp>
#include <lib/support/CHIPMem.h>
#include <lib/support/CodeUtils.h>
#include <platform/CHIPDeviceLayer.h>
#include <platform/Linux/ConfigurationManagerImpl.h>

#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <utility>
#include <vector>

namespace wotex::matter {
namespace {

bool SamePublicKey(const chip::Crypto::P256PublicKey &left,
                   const chip::Crypto::P256PublicKey &right) {
  return left.Length() == right.Length() &&
      std::memcmp(left.ConstBytes(), right.ConstBytes(), left.Length()) == 0;
}

class ControllerConfigurationManager final
    : public chip::DeviceLayer::ConfigurationManagerImpl {
 private:
  CHIP_ERROR Init() override { return CHIP_NO_ERROR; }
};

} // namespace

class SdkControllerBackend::Impl final {
 public:
  BackendResult Open(const NativeOpenOptions &options) {
    if (open_ || memory_initialized_) {
      return {false, "controller_already_open"};
    }

    options_ = options;
    identity_ = {options.fabric_id, options.controller_node_id,
                 options.vendor_id};
    if (!chip::IsOperationalNodeId(identity_.controller_node_id) ||
        !chip::IsVendorIdValidOperationally(
            static_cast<chip::VendorId>(identity_.vendor_id))) {
      return {false, "invalid_controller_identity"};
    }

    CHIP_ERROR error = chip::Platform::MemoryInit();
    if (error != CHIP_NO_ERROR) {
      return {false, "controller_start_failed"};
    }
    memory_initialized_ = true;

    const StorageMode storage_mode = options.storage_mode == "create_new"
        ? StorageMode::CreateNew
        : StorageMode::OpenExisting;
    const AuthorityMode authority_mode = options.authority == "generate_root"
        ? AuthorityMode::GenerateRoot
        : AuthorityMode::Stored;

    error = DurableStorage::Open(options.storage_path, storage_mode,
                                 authority_mode, identity_, storage_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "storage_open_failed"};
    }
    error = storage_->EnterProcessDirectory();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "storage_open_failed"};
    }
    error = sdk_storage_.Init(*storage_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "sdk_storage_failed"};
    }
    sdk_storage_initialized_ = true;

    error = authority_.Init(*storage_, authority_mode, identity_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "authority_invalid"};
    }

    paa_store_ = std::make_unique<chip::Credentials::FileAttestationTrustStore>(
        options.paa_trust_store.c_str());
    if (!paa_store_->IsInitialized() || paa_store_->paaCount() == 0) {
      Cleanup();
      return {false, "paa_trust_store_invalid"};
    }
    attestation_verifier_ =
        std::make_unique<chip::Credentials::DefaultDACVerifier>(paa_store_.get());

    group_provider_.SetStorageDelegate(storage_.get());
    group_provider_.SetSessionKeystore(&session_keystore_);
    error = group_provider_.Init();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    group_initialized_ = true;
    chip::Credentials::SetGroupDataProvider(&group_provider_);

    chip::Controller::FactoryInitParams factory_params;
    factory_params.fabricIndependentStorage = storage_.get();
    factory_params.groupDataProvider = &group_provider_;
    factory_params.sessionKeystore = &session_keystore_;
    factory_params.operationalKeystore = &sdk_storage_.operational_keystore();
    factory_params.opCertStore = &sdk_storage_.certificate_store();
    factory_params.dataModelProvider =
        chip::app::CodegenDataModelProviderInstance(storage_.get());

    auto &factory = chip::Controller::DeviceControllerFactory::GetInstance();
    chip::DeviceLayer::SetConfigurationMgr(&configuration_manager_);
    error = factory.Init(factory_params);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    factory_initialized_ = true;
    factory.RetainSystemState();
    system_state_retained_ = true;

    error = factory.ServiceEvents();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    event_loop_started_ = true;

    error = Execute(Action::Setup, options.timeout_ms);
    if (error != CHIP_NO_ERROR) {
      const std::string code = error == CHIP_ERROR_TIMEOUT
          ? "controller_start_timeout"
          : "controller_start_failed";
      Cleanup();
      return {false, code};
    }

    open_ = true;
    return {true, {}};
  }

  void Close() { Cleanup(); }
  bool IsOpen() const { return open_; }

 private:
  enum class Action { None, Setup, Shutdown };

  static void Work(intptr_t context) {
    auto *self = reinterpret_cast<Impl *>(context);
    const Action action = self->action_;
    CHIP_ERROR error = CHIP_ERROR_INCORRECT_STATE;
    if (action == Action::Setup) {
      error = self->SetupOnSdkThread();
    } else if (action == Action::Shutdown) {
      self->commissioner_.Shutdown();
      error = CHIP_NO_ERROR;
    }

    {
      std::lock_guard<std::mutex> lock(self->work_mutex_);
      self->work_error_ = error;
      self->work_done_ = true;
    }
    self->work_condition_.notify_one();
  }

  CHIP_ERROR Execute(Action action, std::uint32_t timeout_ms) {
    {
      std::lock_guard<std::mutex> lock(work_mutex_);
      action_ = action;
      work_done_ = false;
      work_error_ = CHIP_ERROR_INCORRECT_STATE;
    }
    ReturnErrorOnFailure(chip::DeviceLayer::PlatformMgr().ScheduleWork(
        Work, reinterpret_cast<intptr_t>(this)));

    std::unique_lock<std::mutex> lock(work_mutex_);
    if (!work_condition_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                                  [this] { return work_done_; })) {
      // Keep the callback target alive until the scheduled SDK work returns.
      // The BEAM owner enforces the separate cleanup grace by terminating this
      // process if the SDK itself does not return.
      work_condition_.wait(lock, [this] { return work_done_; });
      return CHIP_ERROR_TIMEOUT;
    }
    return work_error_;
  }

  CHIP_ERROR SetupOnSdkThread() {
    chip::Controller::SetupParams setup;
    setup.operationalCredentialsDelegate = &authority_;
    setup.controllerVendorId = static_cast<chip::VendorId>(identity_.vendor_id);
    setup.deviceAttestationVerifier = attestation_verifier_.get();
    setup.removeFromFabricTableOnShutdown = false;
    setup.deleteFromFabricTableOnShutdown = false;

    if (options_.storage_mode == "create_new") {
      ReturnErrorOnFailure(controller_key_.Initialize(
          chip::Crypto::ECPKeyTarget::ECDSA));
      ReturnErrorOnFailure(authority_.GenerateControllerChain(
          controller_key_.Pubkey(), controller_noc_, controller_rcac_));
      setup.operationalKeypair = &controller_key_;
      setup.controllerNOC =
          chip::ByteSpan(controller_noc_.data(), controller_noc_.size());
      setup.controllerRCAC =
          chip::ByteSpan(controller_rcac_.data(), controller_rcac_.size());
    } else {
      auto *system_state =
          chip::Controller::DeviceControllerFactory::GetInstance()
              .GetSystemState();
      VerifyOrReturnError(system_state != nullptr, CHIP_ERROR_INCORRECT_STATE);
      chip::FabricIndex match = chip::kUndefinedFabricIndex;
      for (const auto &fabric : *system_state->Fabrics()) {
        chip::Crypto::P256PublicKey root_public_key;
        if (fabric.GetFabricId() == identity_.fabric_id &&
            fabric.GetNodeId() == identity_.controller_node_id &&
            static_cast<std::uint16_t>(fabric.GetVendorId()) ==
                identity_.vendor_id &&
            fabric.FetchRootPubkey(root_public_key) == CHIP_NO_ERROR &&
            SamePublicKey(root_public_key, authority_.root_public_key())) {
          VerifyOrReturnError(match == chip::kUndefinedFabricIndex,
                              CHIP_ERROR_DUPLICATE_KEY_ID);
          match = fabric.GetFabricIndex();
        }
      }
      VerifyOrReturnError(match != chip::kUndefinedFabricIndex,
                          CHIP_ERROR_KEY_NOT_FOUND);
      setup.fabricIndex.SetValue(match);
    }

    ReturnErrorOnFailure(
        chip::Controller::DeviceControllerFactory::GetInstance()
            .SetupCommissioner(setup, commissioner_));
    commissioner_initialized_ = true;

    VerifyOrReturnError(commissioner_.GetFabricId() == identity_.fabric_id &&
                            commissioner_.GetNodeId() ==
                                identity_.controller_node_id,
                        CHIP_ERROR_INVALID_ARGUMENT);
    std::uint8_t compressed[sizeof(std::uint64_t)]{};
    chip::MutableByteSpan compressed_span(compressed);
    ReturnErrorOnFailure(
        commissioner_.GetCompressedFabricIdBytes(compressed_span));
    ReturnErrorOnFailure(chip::Credentials::SetSingleIpkEpochKey(
        &group_provider_, commissioner_.GetFabricIndex(), authority_.ipk(),
        compressed_span));
    return CHIP_NO_ERROR;
  }

  void Cleanup() {
    open_ = false;
    if (commissioner_initialized_ && event_loop_started_) {
      (void) Execute(Action::Shutdown, 1000);
      commissioner_initialized_ = false;
    }
    if (event_loop_started_) {
      (void) chip::DeviceLayer::PlatformMgr().StopEventLoopTask();
      event_loop_started_ = false;
    }
    if (system_state_retained_) {
      (void) chip::Controller::DeviceControllerFactory::GetInstance()
          .ReleaseSystemState();
      system_state_retained_ = false;
    }
    if (factory_initialized_) {
      chip::Controller::DeviceControllerFactory::GetInstance().Shutdown();
      factory_initialized_ = false;
    }
    if (group_initialized_) {
      chip::Credentials::SetGroupDataProvider(nullptr);
      group_provider_.Finish();
      group_initialized_ = false;
    }
    attestation_verifier_.reset();
    paa_store_.reset();
    if (sdk_storage_initialized_) {
      sdk_storage_.Finish();
      sdk_storage_initialized_ = false;
    }
    storage_.reset();
    if (memory_initialized_) {
      chip::Platform::MemoryShutdown();
      memory_initialized_ = false;
    }
  }

  NativeOpenOptions options_;
  ControllerIdentity identity_;
  std::unique_ptr<DurableStorage> storage_;
  SdkStorageBinding sdk_storage_;
  RootAuthority authority_;
  chip::Crypto::RawKeySessionKeystore session_keystore_;
  chip::Credentials::GroupDataProviderImpl group_provider_;
  ControllerConfigurationManager configuration_manager_;
  std::unique_ptr<chip::Credentials::FileAttestationTrustStore> paa_store_;
  std::unique_ptr<chip::Credentials::DefaultDACVerifier>
      attestation_verifier_;
  chip::Controller::DeviceCommissioner commissioner_;
  chip::Crypto::P256Keypair controller_key_;
  std::vector<std::uint8_t> controller_noc_;
  std::vector<std::uint8_t> controller_rcac_;
  std::mutex work_mutex_;
  std::condition_variable work_condition_;
  Action action_{Action::None};
  CHIP_ERROR work_error_{CHIP_ERROR_INCORRECT_STATE};
  bool work_done_{false};
  bool memory_initialized_{false};
  bool sdk_storage_initialized_{false};
  bool group_initialized_{false};
  bool factory_initialized_{false};
  bool system_state_retained_{false};
  bool event_loop_started_{false};
  bool commissioner_initialized_{false};
  bool open_{false};
};

SdkControllerBackend::SdkControllerBackend() : impl_(std::make_unique<Impl>()) {}

SdkControllerBackend::~SdkControllerBackend() = default;

BackendResult SdkControllerBackend::Open(const NativeOpenOptions &options) {
  return impl_->Open(options);
}

void SdkControllerBackend::Close() { impl_->Close(); }

bool SdkControllerBackend::IsOpen() const { return impl_->IsOpen(); }

} // namespace wotex::matter
