#ifndef WOTEX_MATTER_BRIDGE_SDK_BOOTSTRAP_FIXTURE_HPP
#define WOTEX_MATTER_BRIDGE_SDK_BOOTSTRAP_FIXTURE_HPP
#include "wotex_matter/bridge_sdk_bootstrap.hpp"
#include <app/MessageDef/AttributeReportIBs.h>
#include <condition_variable>
#include <filesystem>
#include <mutex>
#include <cassert>

namespace wotex::matter {
inline void ResourcePorts(const BridgeConfiguration &configuration) {
  BridgeDeviceInfo information(configuration);
  std::array<char, 128> name{};
  name.fill('!');
  assert(information.GetVendorName(name.data(), configuration.vendor_name.size()) ==
         CHIP_ERROR_BUFFER_TOO_SMALL);
  for (const auto value : name) assert(value == '!');
  assert(information.GetVendorName(name.data(), name.size()) == CHIP_NO_ERROR);
  assert(std::string(name.data()) == configuration.vendor_name);
  std::uint16_t vendor = 0;
  assert(information.GetVendorId(vendor) == CHIP_NO_ERROR &&
         vendor == configuration.identity.vendor_id);
  name.fill('!');
  assert(information.GetSerialNumber(name.data(), name.size()) == CHIP_ERROR_NOT_IMPLEMENTED);
  for (const auto value : name) assert(value == '!');
  information.Retire();
  vendor = 77;
  assert(information.GetVendorId(vendor) == CHIP_ERROR_INCORRECT_STATE && vendor == 77);
  assert(information.GetVendorName(name.data(), name.size()) == CHIP_ERROR_INCORRECT_STATE);
  for (const auto value : name) assert(value == '!');
  BridgeEthernet network(configuration.interface);
  assert(network.GetNetworks() == nullptr && network.GetMaxNetworks() == 1);
  assert(network.Init(nullptr) == CHIP_NO_ERROR);
  auto *iterator = network.GetNetworks();
  assert(iterator && iterator->Count() == 1);
  chip::DeviceLayer::NetworkCommissioning::Network entry;
  assert(iterator->Next(entry) && entry.networkIDLen == configuration.interface.size());
  assert(std::memcmp(entry.networkID, configuration.interface.data(), entry.networkIDLen) == 0);
  assert(!iterator->Next(entry));
  iterator->Release();
  assert(network.Init(nullptr) == CHIP_ERROR_INVALID_ARGUMENT);
  network.Shutdown();
  assert(network.GetNetworks() == nullptr && network.Init(nullptr) == CHIP_ERROR_INVALID_ARGUMENT);
  BridgeEthernet missing("missing0");
  assert(missing.Init(nullptr) == CHIP_ERROR_READ_FAILED && missing.GetNetworks() == nullptr);
}
class NoChildExecution final : public BridgeReceiver {
 public:
  chip::app::DataModel::ActionReturnStatus Read(BridgeRequestMetadata,
                                                chip::app::AttributeValueEncoder &) override {
    return chip::Protocols::InteractionModel::Status::UnsupportedAccess;
  }
  chip::app::DataModel::ActionReturnStatus Write(BridgeRequestMetadata,
                                                 chip::app::AttributeValueDecoder &) override {
    return chip::Protocols::InteractionModel::Status::UnsupportedAccess;
  }
  std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(
      BridgeRequestMetadata, chip::TLV::TLVReader &, chip::app::CommandHandler *) override {
    return chip::app::DataModel::ActionReturnStatus(
        chip::Protocols::InteractionModel::Status::UnsupportedAccess);
  }
  void ListNotification(const chip::app::ConcreteAttributePath &,
                        chip::app::DataModel::ListWriteOperation, chip::FabricIndex) override {}
};
template <typename Verify>
void ReadRootIdentity(SdkBridgeProviderBinding &provider, chip::AttributeId attribute,
                      Verify verify) {
  using namespace chip;
  std::array<std::uint8_t, 1024> bytes{};
  TLV::TLVWriter writer;
  writer.Init(bytes);
  app::AttributeReportIBs::Builder reports;
  assert(reports.Init(&writer) == CHIP_NO_ERROR);
  Access::SubjectDescriptor principal;
  principal.authMode = Access::AuthMode::kCase;
  principal.fabricIndex = 1;
  principal.subject = 1;
  const app::ConcreteAttributePath path(0, 0x0028, attribute);
  app::AttributeValueEncoder encoder(reports, principal, path, 0);
  const app::DataModel::ReadAttributeRequest request(path, principal);
  assert(provider.ReadAttribute(request, encoder).IsSuccess());
  assert(reports.EndOfAttributeReportIBs() == CHIP_NO_ERROR && writer.Finalize() == CHIP_NO_ERROR);
  TLV::TLVReader reader;
  reader.Init(ByteSpan(bytes.data(), writer.GetLengthWritten()));
  assert(reader.Next() == CHIP_NO_ERROR && reader.GetType() == TLV::kTLVType_Array);
  TLV::TLVType outer;
  assert(reader.EnterContainer(outer) == CHIP_NO_ERROR && reader.Next() == CHIP_NO_ERROR);
  app::AttributeReportIB::Parser report;
  assert(report.Init(reader) == CHIP_NO_ERROR);
  app::AttributeDataIB::Parser data;
  assert(report.GetAttributeData(&data) == CHIP_NO_ERROR);
  TLV::TLVReader value;
  assert(data.GetData(&value) == CHIP_NO_ERROR);
  verify(value);
  assert(reader.Next() == CHIP_END_OF_TLV && reader.ExitContainer(outer) == CHIP_NO_ERROR);
  assert(reader.Next() == CHIP_END_OF_TLV);
}

inline void OwnedBootstrapLifecycle(BridgeBootstrap &bootstrap,
                                    chip::DeviceLayer::CommissionableDataProvider &closed,
                                    std::string_view mode, long &allocation_failure) {
  using namespace chip;
  const auto directory = std::filesystem::current_path();
  ResourcePorts(*bootstrap.configuration);
  if (mode == "interface") bootstrap.configuration->interface = "missing0";
  std::unique_ptr<BridgeStorage> held_store;
  if (mode == "store-exists" || mode == "store-locked" || mode == "reopen" ||
      mode == "reopen-missing") {
    assert(BridgeStorage::Open(bootstrap.configuration->store_path, StorageMode::CreateNew,
                               bootstrap.configuration->identity, held_store) == CHIP_NO_ERROR);
    if (mode == "reopen" || mode == "reopen-missing") {
      for (std::size_t i = 0; i < bootstrap.configuration->devices.size(); ++i) {
        if (mode == "reopen-missing" && i != 0) break;
        const auto &device = bootstrap.configuration->devices[i];
        BridgeEndpoint endpoint;
        assert(held_store->Allocate(device.thing_id, device.device_type, endpoint) ==
               CHIP_NO_ERROR);
      }
    }
    if (mode != "store-locked") held_store.reset();
    if (mode != "store-exists") bootstrap.configuration->store_mode = StorageMode::OpenExisting;
  }
  auto *original_dac = Credentials::GetDeviceAttestationCredentialsProvider();
  BridgeConsumerHandoff custody({1});
  BridgeConsumerHandoff::Ticket busy_ticket;
  if (mode == "closed") custody.Close();
  if (mode == "busy") {
    assert(custody.Reserve(0, 100, busy_ticket) == BridgeConsumerHandoff::Admission::Reserved);
  }
  NoChildExecution receiver;
  SdkBridgeBootstrap owner(bootstrap, custody, receiver, closed);
  assert(owner.provider() == nullptr && owner.endpoints() == nullptr);
  assert(owner.Start() == CHIP_ERROR_INCORRECT_STATE && owner.Stop() == CHIP_ERROR_INCORRECT_STATE);
  if (mode == "preflight-allocation") allocation_failure = 0;
  const auto initialized = owner.Init();
  allocation_failure = -1;
  if (mode == "closed" || mode == "busy" || mode == "interface" || mode == "store-exists" ||
      mode == "store-locked" || mode == "preflight-allocation") {
    assert(initialized != CHIP_NO_ERROR && owner.provider() == nullptr);
    if (mode == "closed" || mode == "busy") assert(initialized == CHIP_ERROR_INCORRECT_STATE);
    if (mode == "preflight-allocation") assert(initialized == CHIP_ERROR_NO_MEMORY);
    assert(std::filesystem::current_path() == directory);
    assert(Credentials::GetDeviceAttestationCredentialsProvider() == original_dac);
    assert(DeviceLayer::GetCommissionableDataProvider() == &closed);
    assert(owner.Init() == CHIP_ERROR_INCORRECT_STATE);
    owner.Finish();
    assert(owner.Start() == CHIP_ERROR_INCORRECT_STATE);
    custody.Close();
    if (mode == "busy") {
      BridgeConsumerHandoff::Outcome outcome;
      assert(custody.Take(busy_ticket, 0, outcome) == BridgeConsumerHandoff::Consume::Completed);
      assert(outcome == BridgeConsumerHandoff::Outcome::Closed);
    }
    return;
  }
  assert(initialized == CHIP_NO_ERROR);
  assert(std::filesystem::current_path() == bootstrap.configuration->store_path);
  if (mode == "missing-finish") return;
  assert(owner.Init() == CHIP_ERROR_INCORRECT_STATE);
  DeviceLayer::PlatformMgr().LockChipStack();
  auto *provider = owner.provider();
  assert(provider && owner.endpoints() && owner.endpoints()->initialized());
  const auto &configuration = *bootstrap.configuration;
  const std::array<std::uint16_t, 2> registered{3, 4};
  assert(configuration.devices.size() == registered.size());
  ReadOnlyBufferBuilder<app::DataModel::EndpointEntry> children;
  assert(provider->Endpoints(children) == CHIP_NO_ERROR);
  const auto child_entries = children.TakeBuffer();
  assert(child_entries.size() == 4);
  for (std::size_t i = 0; i < configuration.devices.size(); ++i) {
    const auto &device = configuration.devices[i];
    bool found = false;
    for (const auto &entry : child_entries)
      if (entry.id == registered[i]) found = true;
    assert(found);
    ReadOnlyBufferBuilder<app::DataModel::DeviceTypeEntry> types;
    assert(provider->DeviceTypes(registered[i], types) == CHIP_NO_ERROR);
    const auto values = types.TakeBuffer();
    assert(values.size() == 2 && values[0].deviceTypeId == 0x0013 &&
           values[1].deviceTypeId == static_cast<std::uint32_t>(device.device_type));
  }
  for (const auto &entry :
       {std::pair<AttributeId, std::uint16_t>{2, configuration.identity.vendor_id},
        {4, configuration.identity.product_id},
        {7, configuration.hardware_version}}) {
    ReadRootIdentity(*provider, entry.first, [&](TLV::TLVReader &reader) {
      std::uint16_t value = 0;
      assert(reader.Get(value) == CHIP_NO_ERROR && value == entry.second);
    });
  }
  for (const auto &entry :
       {std::pair<AttributeId, const std::string *>{1, &configuration.vendor_name},
        {3, &configuration.product_name},
        {8, &configuration.hardware_version_string}}) {
    ReadRootIdentity(*provider, entry.first, [&](TLV::TLVReader &reader) {
      CharSpan value;
      assert(reader.Get(value) == CHIP_NO_ERROR &&
             value.data_equal(CharSpan(entry.second->data(), entry.second->size())));
    });
  }
  assert(Server::GetInstance().GetCommissioningWindowManager().IsCommissioningWindowOpen() ==
         (configuration.commissioning_window_seconds != 0));
  DeviceLayer::PlatformMgr().UnlockChipStack();
  assert(owner.Start() == CHIP_NO_ERROR);
  if (mode == "running-finish") owner.Finish();
  assert(owner.Start() == CHIP_ERROR_INCORRECT_STATE);
  struct Receipt {
    std::mutex mutex;
    std::condition_variable changed;
    bool ran{false};
  } receipt;
  const auto scheduled = DeviceLayer::PlatformMgr().ScheduleWork([](intptr_t context) {
    auto &value = *reinterpret_cast<Receipt *>(context);
    std::lock_guard<std::mutex> lock(value.mutex);
    value.ran = true;
    value.changed.notify_one();
  }, reinterpret_cast<intptr_t>(&receipt));
  assert(scheduled == CHIP_NO_ERROR);
  {
    std::unique_lock<std::mutex> lock(receipt.mutex);
    assert(receipt.changed.wait_for(lock, std::chrono::seconds(2), [&] { return receipt.ran; }));
  }
  if (mode == "expiry") {
    struct Expiry {
      std::mutex mutex;
      std::condition_variable changed;
      bool verified{false};
    } expiry;
    DeviceLayer::PlatformMgr().LockChipStack();
    const auto timer = DeviceLayer::SystemLayer().StartTimer(System::Clock::Seconds32(181),
                                                             [](System::Layer *, void *context) {
      assert(!Server::GetInstance().GetCommissioningWindowManager().IsCommissioningWindowOpen());
      auto &value = *static_cast<Expiry *>(context);
      std::lock_guard<std::mutex> lock(value.mutex);
      value.verified = true;
      value.changed.notify_one();
    }, &expiry);
    DeviceLayer::PlatformMgr().UnlockChipStack();
    assert(timer == CHIP_NO_ERROR);
    std::unique_lock<std::mutex> lock(expiry.mutex);
    assert(
        expiry.changed.wait_for(lock, std::chrono::seconds(183), [&] { return expiry.verified; }));
  }
  if (mode != "unclosed-finish") custody.Close();
  assert(owner.Stop() == CHIP_NO_ERROR);
  assert(owner.Stop() == CHIP_ERROR_INCORRECT_STATE);
  owner.Finish();
  owner.Finish();
  assert(owner.provider() == nullptr && owner.endpoints() == nullptr);
  assert(owner.Start() == CHIP_ERROR_INCORRECT_STATE && owner.Stop() == CHIP_ERROR_INCORRECT_STATE);
  assert(owner.Init() == CHIP_ERROR_INCORRECT_STATE);
  assert(app::InteractionModelEngine::GetInstance()->GetDataModelProvider() == nullptr);
  assert(Credentials::GetDeviceAttestationCredentialsProvider() == original_dac);
  assert(DeviceLayer::GetCommissionableDataProvider() == &closed);
  assert(std::filesystem::current_path() == directory);
  std::unique_ptr<BridgeStorage> reopened;
  assert(BridgeStorage::Open(configuration.store_path, StorageMode::OpenExisting,
                             configuration.identity, reopened) == CHIP_NO_ERROR);
  std::map<std::string, BridgeEndpoint> persisted;
  assert(reopened->Endpoints(persisted) == CHIP_NO_ERROR && persisted.size() == registered.size());
  for (std::size_t i = 0; i < configuration.devices.size(); ++i) {
    const auto &device = configuration.devices[i];
    const auto found = persisted.find(device.thing_id);
    assert(found != persisted.end() && found->second.endpoint == registered[i] &&
           found->second.device_type == device.device_type);
  }
}
} // namespace wotex::matter
#endif
