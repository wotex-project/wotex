#include "wotex_matter/bridge_storage.hpp"
#include "wotex_matter/bridge_server.hpp"
#include "sdk_bridge_endpoints_test.hpp"
#include "sdk_bridge_requests_test.hpp"
#include "sdk_bridge_replies_test.hpp"
#include "sdk_bridge_provider_test.hpp"
#include "sdk_bridge_wait_test.hpp"
#include "sdk_bridge_writes_test.hpp"
#include "sdk_bridge_guard_test.hpp"

#include <LinuxCommissionableDataProvider.h>
#include <app/server/Server.h>
#include <app/InteractionModelEngine.h>
#include <app/SafeAttributePersistenceProvider.h>
#include <app/persistence/AttributePersistenceProviderInstance.h>
#include <app/clusters/network-commissioning/CodegenInstance.h>
#include <app/util/endpoint-config-api.h>
#include <credentials/examples/DeviceAttestationCredsExample.h>
#include <credentials/GroupDataProvider.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <data-model-providers/codegen/Instance.h>
#include <lib/support/CHIPMem.h>
#include <platform/CHIPDeviceLayer.h>
#include <setup_payload/SetupPayload.h>

#include <csignal>
#include <arpa/inet.h>
#include <condition_variable>
#include <cstring>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error This standalone probe requires an explicit test build.
#endif

namespace {
class ClosedCommissioning final : public chip::DeviceLayer::CommissionableDataProvider {
 public:
  CHIP_ERROR GetSetupDiscriminator(uint16_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR SetSetupDiscriminator(uint16_t) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pIterationCount(uint32_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pSalt(chip::MutableByteSpan &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pVerifier(chip::MutableByteSpan &, size_t &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR GetSetupPasscode(uint32_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR SetSetupPasscode(uint32_t) override { return CHIP_ERROR_INCORRECT_STATE; }
};
ClosedCommissioning closed_commissioning;
class TestEthernet final : public chip::DeviceLayer::NetworkCommissioning::EthernetDriver {
 public:
  uint8_t GetMaxNetworks() override { return 1; }
  chip::DeviceLayer::NetworkCommissioning::NetworkIterator *GetNetworks() override {
    return new SingleNetwork;
  }
 private:
  class SingleNetwork final : public chip::DeviceLayer::NetworkCommissioning::NetworkIterator {
   public:
    size_t Count() override { return 1; }
    bool Next(chip::DeviceLayer::NetworkCommissioning::Network &network) override {
      if (exhausted_) return false;
      exhausted_ = true;
      network = {};
      std::memcpy(network.networkID, "lo", 2);
      network.networkIDLen = 2;
      network.connected = true;
      return true;
    }
    void Release() override { delete this; }
   private:
    bool exhausted_ = false;
  };
};

void Check(CHIP_ERROR error, const char *stage) {
  if (error != CHIP_NO_ERROR) {
    std::cerr << "server test failed: " << stage << '\n';
    throw std::runtime_error(stage);
  }
}
void Require(bool value, const char *stage) {
  if (!value) {
    std::cerr << "server test failed: " << stage << '\n';
    throw std::runtime_error(stage);
  }
}

void Run(const char *directory, const std::string &mode) {
  using namespace chip;
  using namespace wotex::matter;
  BridgeIdentity identity{"bridge-startup-probe",
                          "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671",
                          0xFFF1, 0x8001};
  if (mode == "wrong_model") {
    identity.model_sha256 = std::string(64, '0');
  } else if (mode == "wrong_vendor") {
    identity.vendor_id = 0xFFF2;
  } else if (mode == "wrong_product") {
    identity.product_id = 0x8002;
  }
  std::unique_ptr<BridgeStorage> store;
  Check(
      BridgeStorage::Open(directory,
                          mode == "reopen" || mode == "endpoints_reopen" ? StorageMode::OpenExisting
                                                                         : StorageMode::CreateNew,
                          identity, store),
      "bridge store");
  Check(store->EnterProcessDirectory(), "private directory");
  BridgeConsumerHandoff handoff({1});
  SdkBridgeServerBinding binding(*store, handoff);
  BridgeConsumerHandoff::Ticket initial_handoff;
  if (mode == "handoff_closed_init") handoff.Close();
  if (mode == "handoff_busy_init") {
    Require(
        handoff.Reserve(100, 600, initial_handoff) == BridgeConsumerHandoff::Admission::Reserved,
        "pending startup fixture");
  }

  LinuxCommissionableDataProvider commissioning;
  uint32_t pin = 0;
  for (unsigned attempt = 0; attempt < 32; ++attempt) {
    Check(Crypto::DRBG_get_bytes(reinterpret_cast<uint8_t *>(&pin), sizeof(pin)),
          "test onboarding");
    pin = pin % 99999998U + 1U;
    if (SetupPayload::IsValidSetupPIN(pin)) break;
  }
  Require(SetupPayload::IsValidSetupPIN(pin), "test onboarding exhausted");
  uint16_t discriminator = 0;
  Check(Crypto::DRBG_get_bytes(reinterpret_cast<uint8_t *>(&discriminator), sizeof(discriminator)),
        "test discriminator");
  discriminator &= 0x0FFF;
  Check(commissioning.Init(NullOptional, NullOptional, 1000, MakeOptional(pin), discriminator),
        "commissionable provider");
  DeviceLayer::SetCommissionableDataProvider(&commissioning);
  auto *original_dac = Credentials::GetDeviceAttestationCredentialsProvider();
  Credentials::SetDeviceAttestationCredentialsProvider(
      Credentials::Examples::GetExampleDACProvider());
  if (mode == "missing_dac") {
    Credentials::SetDeviceAttestationCredentialsProvider(original_dac);
  }
  Check(DeviceLayer::PlatformMgr().InitChipStack(), "platform initialization");
  DeviceLayer::PlatformMgr().LockChipStack();

  auto *delegate = app::CodegenDataModelProviderInstance(&binding.storage_delegate());
  auto provider_probe = testing::PrepareProvider(handoff);
  const bool waiting = mode == "wait" || mode == "wait_input_eof" ||
      mode == "wait_input_malformed" || mode == "wait_input_partial" || mode == "wait_input_cancel";
  const auto input_mode = mode == "wait_input_eof" ? testing::WaitInput::Ended
      : mode == "wait_input_malformed"             ? testing::WaitInput::Malformed
      : mode == "wait_input_partial"               ? testing::WaitInput::Partial
      : mode == "wait_input_cancel"                ? testing::WaitInput::Cancelled
                                                   : testing::WaitInput::Direct;
  auto wait_probe = waiting ? testing::PrepareWait(handoff, *delegate, input_mode) : nullptr;
  BridgeReceiver &receiver = wait_probe ? static_cast<BridgeReceiver &>(*wait_probe)
                                        : provider_probe->receiver();
  SdkBridgeProviderBinding provider(*delegate, receiver);
  auto *model = &provider;
  TestEthernet ethernet;
  Inet::InterfaceId interface;
  Check(Inet::InterfaceId::InterfaceNameToId("lo", interface), "explicit test interface");
  Require(binding.Init(*model, ethernet, Inet::InterfaceId::Null(), 5540) ==
              CHIP_ERROR_INVALID_ARGUMENT,
          "missing interface");
  Require(binding.Init(*model, ethernet, interface, 0) == CHIP_ERROR_INVALID_ARGUMENT,
          "missing port");
  if (mode == "wrong_model" || mode == "wrong_vendor" || mode == "wrong_product" ||
      mode == "missing_dac" || mode == "handoff_closed_init" || mode == "handoff_busy_init") {
    Require(binding.Init(*model, ethernet, interface, 5540) == CHIP_ERROR_INVALID_ARGUMENT,
            "server input refused");
    Require(!binding.initialized(), "refused server remains inactive");
    if (mode == "handoff_busy_init") {
      handoff.Close();
      BridgeConsumerHandoff::Outcome outcome = BridgeConsumerHandoff::Outcome::Unknown;
      Require(handoff.Take(initial_handoff, 100, outcome) ==
                      BridgeConsumerHandoff::Consume::Completed &&
                  outcome == BridgeConsumerHandoff::Outcome::Closed,
              "pending startup fixture consumed");
    }
    binding.Finish();
    app::CodegenDataModelProvider::Instance().SetPersistentStorageDelegate(nullptr);
    Credentials::SetDeviceAttestationCredentialsProvider(original_dac);
    DeviceLayer::SetCommissionableDataProvider(&closed_commissioning);
    DeviceLayer::PlatformMgr().UnlockChipStack();
    DeviceLayer::PlatformMgr().Shutdown();
    std::cout << "server input refusal probe passed\n";
    return;
  }
  if (mode == "startup_failure") {
    const int blocker = socket(AF_INET6, SOCK_DGRAM, 0);
    Require(blocker >= 0, "startup socket");
    sockaddr_in6 address{};
    address.sin6_family = AF_INET6;
    address.sin6_port = htons(5540);
    address.sin6_addr = in6addr_any;
    Require(bind(blocker, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0,
            "startup port custody");
  }
  Check(binding.Init(*model, ethernet, interface, 5540), "server binding initialization");
  Require(binding.initialized(), "server binding active");
  Require(binding.Init(*model, ethernet, interface, 5540) == CHIP_ERROR_INVALID_ARGUMENT,
          "second initialization refused");
  Require(!emberAfEndpointIndexIsEnabled(2), "dummy disabled");
  Require(Server::GetInstance().GetFabricTable().FabricCount() == 0, "empty fabrics");
  ReadOnlyBufferBuilder<app::DataModel::EndpointEntry> endpoints;
  Check(model->Endpoints(endpoints), "model endpoints");
  auto endpoint_list = endpoints.TakeBuffer();
  Require(endpoint_list.size() == 2 && endpoint_list[0].id == 0 && endpoint_list[1].id == 1,
          "root and aggregator only");
  for (const auto &entry : endpoint_list) {
    ReadOnlyBufferBuilder<app::DataModel::DeviceTypeEntry> types;
    Check(model->DeviceTypes(entry.id, types), "root device types");
    auto type_list = types.TakeBuffer();
    Require(type_list.size() == 1, "single fixed device type");
    Require(type_list[0].deviceTypeId == (entry.id == 0 ? 0x0016U : 0x000EU),
            "fixed device type identity");
    Require(type_list[0].deviceTypeRevision == (entry.id == 0 ? 4U : 2U),
            "fixed device type revision");
  }

  std::unique_ptr<SdkBridgeEndpointBinding> children;
  if (mode == "guard" || mode == "guard_missing_finish") {
    testing::VerifyBridgeGuard(binding, provider, mode == "guard_missing_finish");
  }
  if (mode == "writes") testing::VerifyBridgeWrites();
  if (wait_probe) wait_probe->Prepare(binding, provider);
  if (mode.rfind("provider", 0) == 0) {
    provider_probe->Verify(binding, provider, *delegate, mode);
  }
  if (mode == "replies" || mode == "replies_retain") {
    testing::VerifyBridgeReplies(binding, handoff, mode == "replies_retain");
  }
  if (mode.compare(0, 10, "endpoints_") == 0) {
    children = testing::PrepareEndpoints(binding, mode);
  }
  std::unique_ptr<testing::RequestProbe> requests;
  if (mode == "requests" || mode == "requests_invalidated" || mode == "requests_missing_finish") {
    requests = testing::PrepareRequests(handoff, mode == "requests_invalidated");
  }
  std::array<BridgeConsumerHandoff::Ticket, BridgeConsumerHandoff::kCapacity> tickets{};
  if (mode == "handoff") {
    for (auto &ticket : tickets) {
      Require(handoff.Reserve(100, 600, ticket) == BridgeConsumerHandoff::Admission::Reserved,
              "SDK handoff sixteen pending");
    }
  }

  DeviceLayer::PlatformMgr().UnlockChipStack();
  Check(DeviceLayer::PlatformMgr().StartEventLoopTask(), "event loop start");
  if (wait_probe) wait_probe->DuringLoop();
  struct LoopReceipt {
    std::mutex mutex;
    std::condition_variable ready;
    bool ran = false;
    SdkBridgeEndpointBinding *children = nullptr;
    CHIP_ERROR observation = CHIP_NO_ERROR;
    BridgeConsumerHandoff *handoff = nullptr;
    BridgeConsumerHandoff::Ticket *tickets = nullptr;
    bool handoff_ok = false;
    testing::RequestProbe *requests = nullptr;
    bool finish_requests = true;
  } receipt;
  receipt.children = children.get();
  receipt.requests = requests.get();
  receipt.finish_requests = mode != "requests_missing_finish";
  if (mode == "handoff") {
    receipt.handoff = &handoff;
    receipt.tickets = tickets.data();
  }
  Check(DeviceLayer::PlatformMgr().ScheduleWork(
            [](intptr_t context) {
    auto &value = *reinterpret_cast<LoopReceipt *>(context);
    std::lock_guard<std::mutex> lock(value.mutex);
    if (value.children != nullptr) {
      value.observation = testing::ObserveDuringLoop(*value.children);
    }
    if (value.handoff != nullptr) {
      using H = BridgeConsumerHandoff;
      const auto old = value.tickets[0];
      H::Outcome outcome = H::Outcome::Unknown;
      value.handoff_ok = value.handoff->Resolve(old, H::Outcome::Completed, 101) ==
              H::Reply::Stored &&
          value.handoff->Take(old, 101, outcome) == H::Consume::Completed &&
          outcome == H::Outcome::Completed &&
          value.handoff->Reserve(101, 601, value.tickets[0]) == H::Admission::Reserved &&
          value.tickets[0].id == 17 &&
          value.handoff->Resolve(old, H::Outcome::Completed, 101) == H::Reply::UnknownTicket &&
          value.handoff->Resolve(value.tickets[1], H::Outcome::Denied, 102) == H::Reply::Stored &&
          value.handoff->Resolve(value.tickets[2], H::Outcome::Completed, 103) == H::Reply::Stored;
    }
    if (value.requests != nullptr) {
      value.requests->DuringLoop();
      if (value.finish_requests) value.requests->Finish();
    }
    value.ran = true;
    value.ready.notify_one();
  }, reinterpret_cast<intptr_t>(&receipt)),
        "event loop work");
  {
    std::unique_lock<std::mutex> lock(receipt.mutex);
    Require(
        receipt.ready.wait_for(lock, std::chrono::seconds(2), [&receipt] { return receipt.ran; }),
        "event loop deadline");
    Check(receipt.observation, "event loop approved observation");
    if (mode == "handoff") Require(receipt.handoff_ok, "event loop handoff result custody");
  }
  if (mode == "missing_finish" || mode == "endpoints_missing_finish" ||
      mode == "requests_missing_finish") {
    return;
  }
  if (mode == "endpoints_poison_add" || mode == "endpoints_poison_remove") {
    DeviceLayer::PlatformMgr().LockChipStack();
    testing::PoisonEndpoints(*children, mode);
  }
  if (mode == "poison_sdk" || mode == "poison_allocate" || mode == "poison_remove") {
    DeviceLayer::PlatformMgr().LockChipStack();
    BridgeEndpoint endpoint;
    if (mode == "poison_remove") {
      Check(binding.Allocate("removed", BridgedDeviceType::OnOffLight, endpoint),
            "remove fixture allocation");
    }
    Require(mkdir("store.tmp", 0700) == 0, "failed commit fixture");
    if (mode == "poison_sdk") {
      const uint8_t value = 1;
      const CHIP_ERROR error = binding.storage_delegate().SyncSetKeyValue("poison", &value,
                                                                          sizeof(value));
      (void)error;
    } else if (mode == "poison_allocate") {
      const CHIP_ERROR error = binding.Allocate("new", BridgedDeviceType::TemperatureSensor,
                                                endpoint);
      (void)error;
    } else {
      const CHIP_ERROR error = binding.Remove("removed");
      (void)error;
    }
    throw std::runtime_error("poisoned owner continued");
  }
  Check(DeviceLayer::PlatformMgr().StopEventLoopTask(), "event loop stop");
  DeviceLayer::PlatformMgr().LockChipStack();

  if (mode == "handoff_pending_finish") {
    Require(
        handoff.Reserve(100, 600, initial_handoff) == BridgeConsumerHandoff::Admission::Reserved,
        "pending shutdown fixture");
    std::cout << "bridge handoff retained context prepared\n" << std::flush;
    binding.Finish();
    throw std::runtime_error("unconsumed handoff shutdown continued");
  }
  if (mode == "handoff") {
    using H = BridgeConsumerHandoff;
    H::Ticket sentinel{{9}, 99};
    H::Outcome outcome = H::Outcome::Unknown;
    Require(handoff.Reserve(600, 1100, sentinel) == H::Admission::Busy && sentinel.id == 99,
            "unconsumed expired SDK contexts retain admission credit");
    Require(handoff.Take(tickets[1], 600, outcome) == H::Consume::Completed &&
                outcome == H::Outcome::TimedOut,
            "delayed SDK result expired");
    handoff.Close();
    for (std::size_t index = 0; index < tickets.size(); ++index) {
      if (index == 1) continue;
      Require(handoff.Take(tickets[index], 600, outcome) == H::Consume::Completed &&
                  outcome == H::Outcome::Closed,
              "closed SDK handoff consumed exact context");
    }
    Require(handoff.pending() == 0, "SDK handoff drained before resource release");
    std::cout << "bridge handoff event loop and shutdown passed\n" << std::flush;
  }
  if (wait_probe) wait_probe->Finish();
  if (children) testing::FinishEndpoints(*children, binding);
  binding.Finish();
  binding.Finish();
  Require(!binding.initialized(), "binding closed");
  Require(handoff.closed() && handoff.pending() == 0, "handoff closed before SDK release");
  Require(app::InteractionModelEngine::GetInstance()->GetDataModelProvider() == nullptr,
          "model released");
  Require(Credentials::GetGroupDataProvider() == nullptr, "group provider released");
  const uint8_t value = 1;
  Require(app::GetAttributePersistenceProvider()->WriteValue(
              app::ConcreteAttributePath(3, 0x0039, 5), ByteSpan(&value, sizeof(value))) ==
              CHIP_ERROR_INCORRECT_STATE,
          "cluster attribute persistence retired");
  uint8_t retired_value = 0;
  MutableByteSpan retired_span(&retired_value, sizeof(retired_value));
  Require(app::GetAttributePersistenceProvider()->ReadValue(
              app::ConcreteAttributePath(3, 0x0039, 5), retired_span) == CHIP_ERROR_INCORRECT_STATE,
          "cluster attribute reads retired");
  Require(app::GetSafeAttributePersistenceProvider()->SafeWriteValue(
              app::ConcreteAttributePath(0, 0x0028, 0x0005), ByteSpan(&value, sizeof(value))) ==
              CHIP_ERROR_INCORRECT_STATE,
          "attribute persistence retired");
  Require(binding.storage_delegate().SyncSetKeyValue("closed", &value, sizeof(value)) ==
              CHIP_ERROR_INCORRECT_STATE,
          "closed store");
  BridgeEndpoint endpoint;
  Require(binding.Allocate("closed", BridgedDeviceType::OnOffLight, endpoint) ==
              CHIP_ERROR_INCORRECT_STATE,
          "closed allocation");
  Require(binding.Remove("closed") == CHIP_ERROR_INCORRECT_STATE, "closed removal");
  Credentials::SetDeviceAttestationCredentialsProvider(original_dac);
  DeviceLayer::SetCommissionableDataProvider(&closed_commissioning);
  Require(!Credentials::IsDeviceAttestationCredentialsProviderSet(), "DAC released");
  uint16_t retired_discriminator = 0;
  Require(DeviceLayer::GetCommissionableDataProvider()->GetSetupDiscriminator(
              retired_discriminator) == CHIP_ERROR_INCORRECT_STATE,
          "commissionable provider retired");
  DeviceLayer::PlatformMgr().UnlockChipStack();
  DeviceLayer::PlatformMgr().Shutdown();
  std::cout << "server startup and shutdown probe passed\n";
}
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  const std::string mode(argv[2]);
  if (mode != "normal" && mode != "reopen" && mode != "startup_failure" &&
      mode != "missing_finish" && mode != "poison_sdk" && mode != "poison_allocate" &&
      mode != "poison_remove" && mode != "wrong_model" && mode != "wrong_vendor" &&
      mode != "wrong_product" && mode != "missing_dac" && mode != "endpoints_seed" &&
      mode != "endpoints_reopen" && mode != "endpoints_missing_finish" &&
      mode != "endpoints_poison_add" && mode != "endpoints_poison_remove" && mode != "handoff" &&
      mode != "handoff_pending_finish" && mode != "handoff_closed_init" &&
      mode != "handoff_busy_init" && mode != "requests" && mode != "requests_invalidated" &&
      mode != "requests_missing_finish" && mode != "replies" && mode != "replies_retain" &&
      mode != "provider" && mode != "provider_startup_failure" &&
      mode != "provider_shutdown_failure" && mode != "provider_missing_finish" && mode != "wait" &&
      mode != "wait_input_eof" && mode != "wait_input_malformed" && mode != "wait_input_partial" &&
      mode != "wait_input_cancel" && mode != "writes" && mode != "guard" &&
      mode != "guard_missing_finish")
    return 2;
  std::signal(SIGPIPE, SIG_IGN);
  if (chip::Platform::MemoryInit() != CHIP_NO_ERROR) return 1;
  int result = 0;
  try {
    Run(argv[1], mode);
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    result = 1;
  }
  chip::Platform::MemoryShutdown();
  return result;
}
