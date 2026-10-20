#include "sdk_bridge_receiver_test.hpp"
#include "wotex_matter/bridge_sdk_receiver.hpp"
#include "wotex_matter/bridge_replies.hpp"

#include <app/MessageDef/AttributeReportIB.h>
#include <app/MessageDef/AttributeDataIB.h>
#include <access/AccessControl.h>
#include <credentials/TestOnlyLocalCertificateAuthority.h>
#include <credentials/GroupDataProvider.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cassert>
#include <chrono>
#include <csignal>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <poll.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Guarded SDK receiver fixtures must remain separate from production execution.
#endif

namespace wotex::matter::testing {
namespace {
using Json = nlohmann::json;
using Status = chip::Protocols::InteractionModel::Status;
using Action = chip::app::DataModel::ActionReturnStatus;
using CommandPath = chip::app::ConcreteCommandPath;
using ClusterStatus = chip::Protocols::InteractionModel::ClusterStatusCode;
const std::string generation = "01000000000000000000000000000000";
std::string Control(std::string_view type) {
  return Json({{"v", 1}, {"backend", "matter-bridge"}, {"type", type}, {"generation", generation}})
             .dump() +
      '\n';
}
void Send(int descriptor, const Json &frame) {
  const auto bytes = frame.dump() + '\n';
  assert(write(descriptor, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
}
void SendControl(int descriptor, std::string_view type) {
  const auto bytes = Control(type);
  assert(write(descriptor, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
}
std::string Line(int descriptor) {
  std::string bytes;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (std::chrono::steady_clock::now() < deadline) {
    pollfd source{descriptor, POLLIN, 0};
    assert(poll(&source, 1, 100) >= 0);
    if (!(source.revents & (POLLIN | POLLHUP))) continue;
    char byte;
    const auto count = read(descriptor, &byte, 1);
    if (count == 0) return bytes;
    assert(count == 1 && bytes.size() < 262144);
    bytes += byte;
    if (byte == '\n') return bytes;
  }
  assert(false && "SDK receiver pipe wait exceeded its bound");
  return {};
}
class Lock final {
 public:
  Lock() { chip::DeviceLayer::PlatformMgr().LockChipStack(); }
  ~Lock() { chip::DeviceLayer::PlatformMgr().UnlockChipStack(); }
};
class Clock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
};
class Handler final : public chip::app::CommandHandler {
 public:
  chip::Access::SubjectDescriptor principal;
  std::atomic<unsigned> held{0}, statuses{0}, data{0};
  std::atomic<int> result{-1};
  bool reject{false};
  CHIP_ERROR FallibleAddStatus(const CommandPath &, const ClusterStatus &status,
                               const char *) override {
    if (reject) return CHIP_ERROR_NO_MEMORY;
    result.store(static_cast<int>(status.GetStatus()));
    statuses.fetch_add(1);
    return CHIP_NO_ERROR;
  }
  void AddStatus(const CommandPath &path, const ClusterStatus &status,
                 const char *context) override {
    assert(FallibleAddStatus(path, status, context) == CHIP_NO_ERROR);
  }
  CHIP_ERROR AddResponseData(const CommandPath &, chip::CommandId,
                             const chip::app::DataModel::EncodableToTLV &value) override {
    std::uint8_t bytes[8192];
    chip::TLV::TLVWriter writer;
    writer.Init(bytes);
    chip::app::DataModel::FabricAwareTLVWriter fabric(writer, principal.fabricIndex);
    const auto error = value.EncodeTo(fabric, chip::TLV::AnonymousTag());
    if (error != CHIP_NO_ERROR) return error;
    if (writer.Finalize() != CHIP_NO_ERROR) return CHIP_ERROR_INTERNAL;
    data.fetch_add(1);
    result.store(static_cast<int>(Status::Success));
    return CHIP_NO_ERROR;
  }
  void AddResponse(const CommandPath &path, chip::CommandId id,
                   const chip::app::DataModel::EncodableToTLV &value) override {
    assert(AddResponseData(path, id, value) == CHIP_NO_ERROR);
  }
  chip::FabricIndex GetAccessingFabricIndex() const override {
    assert(held == 0);
    return principal.fabricIndex;
  }
  chip::Access::SubjectDescriptor GetSubjectDescriptor() const override {
    assert(held == 0);
    return principal;
  }
  bool IsTimedInvoke() const override {
    assert(held == 0);
    return false;
  }
  chip::Messaging::ExchangeContext *GetExchangeContext() const override {
    assert(false);
    return nullptr;
  }
  void FlushAcksRightAwayOnSlowCommand() override { assert(false); }
 protected:
  void IncrementHoldOff(Handle *) override { assert(held.fetch_add(1) == 0); }
  void DecrementHoldOff(Handle *) override { assert(held.fetch_sub(1) == 1); }
};
class Renderer final : public BridgeInvokeReply {
 public:
  explicit Renderer(std::string_view selection) : mode(selection) {}
  CHIP_ERROR Completed(chip::app::CommandHandler &handler,
                       const BridgeInvocation &invocation) noexcept override {
    ++completed;
    // Native rendering must not retain the input/result custody mutex.
    owner->With([](auto &, auto) {});
    if (mode != "groups")
      return handler.FallibleAddStatus(
          {invocation.request.endpoint, invocation.request.cluster, invocation.request.member},
          Status::Success);
    const chip::CommandId responses[]{0, 1, 2, 3};
    SdkBridgeCommandReply scoped(handler, invocation.request,
                                 chip::Span<const chip::CommandId>(responses));
    if (scoped.configuration_status() != CHIP_NO_ERROR) return scoped.configuration_status();
    chip::TLV::TLVReader arguments;
    arguments.Init(invocation.arguments.data(), invocation.arguments.size());
    ReturnErrorOnFailure(arguments.Next());
    chip::app::DataModel::InvokeRequest request(
        {invocation.request.endpoint, invocation.request.cluster, invocation.request.member},
        invocation.request.principal);
    const auto result = chip::app::CodegenDataModelProvider::Instance().InvokeCommand(
        request, arguments, &scoped);
    if (result) (void)scoped.FallibleAddStatus(request.path, result->GetStatusCode());
    return scoped.result();
  }
  const std::string_view mode;
  BridgeHandoffOwner *owner{nullptr};
  std::atomic<unsigned> completed{0};
};
class Fixture final : public BridgeSdkProcessReceiver {
 public:
  explicit Fixture(std::string_view selection)
      : mode(selection), renderer(selection), core(renderer) {}
  CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, BridgeConsumerHandoff &shared,
                    BridgeHandoffOwner &custody, BridgeOutputOwner &output,
                    SdkBridgeObservationOwner &observations) noexcept override {
    provider = runtime.provider();
    endpoints = runtime.endpoints();
    owner = &custody;
    renderer.owner = &custody;
    auto &table = chip::Server::GetInstance().GetFabricTable();
    chip::Credentials::TestOnlyLocalCertificateAuthority authority;
    authority.Init();
    assert(authority.GetStatus() == CHIP_NO_ERROR);
    std::uint8_t bytes[chip::Crypto::kMIN_CSR_Buffer_Size];
    chip::MutableByteSpan csr(bytes);
    assert(table.AllocatePendingOperationalKey(chip::NullOptional, csr) == CHIP_NO_ERROR);
    authority.GenerateNocChain(17, 1, csr);
    assert(authority.GetStatus() == CHIP_NO_ERROR &&
           table.AddNewPendingTrustedRootCert(authority.GetRcac()) == CHIP_NO_ERROR);
    chip::FabricIndex index;
    assert(table.AddNewPendingFabricWithOperationalKeystore(
               authority.GetNoc(), authority.GetIcac(), static_cast<chip::VendorId>(0xFFF1), &index,
               chip::FabricTable::AdvertiseIdentity::No) == CHIP_NO_ERROR);
    assert(table.CommitPendingFabricData() == CHIP_NO_ERROR);
    principal.fabricIndex = index;
    principal.authMode = chip::Access::AuthMode::kCase;
    principal.subject = 42;
    principal.cats.values[0] = 0x00010002;
    if (mode == "groups") {
      using Groups = chip::Credentials::GroupDataProvider;
      Groups::KeySet keys(1, Groups::SecurityPolicy::kTrustFirst, 1);
      std::fill(std::begin(keys.epoch_keys[0].key), std::end(keys.epoch_keys[0].key), 0x5a);
      std::uint8_t compressed[8];
      chip::MutableByteSpan compressed_fabric(compressed);
      assert(table.FindFabricWithIndex(index)->GetCompressedFabricIdBytes(compressed_fabric) ==
             CHIP_NO_ERROR);
      auto *groups = chip::Credentials::GetGroupDataProvider();
      assert(groups->SetKeySet(index, compressed_fabric, keys) == CHIP_NO_ERROR &&
             groups->SetGroupKey(index, 7, 1) == CHIP_NO_ERROR);
    }
    if (mode != "missing-acl") {
      auto &access = chip::Access::GetAccessControl();
      chip::Access::AccessControl::Entry entry;
      assert(access.PrepareEntry(entry) == CHIP_NO_ERROR &&
             entry.SetFabricIndex(index) == CHIP_NO_ERROR &&
             entry.SetPrivilege(chip::Access::Privilege::kAdminister) == CHIP_NO_ERROR &&
             entry.SetAuthMode(chip::Access::AuthMode::kCase) == CHIP_NO_ERROR &&
             entry.AddSubject(nullptr, 42) == CHIP_NO_ERROR &&
             access.CreateEntry(nullptr, index, &acl, entry) == CHIP_NO_ERROR);
    }
    for (auto &handler : handlers) handler.principal = principal;
    handlers[0].reject = mode == "invoke-render-error";
    assert(endpoints->Observe(std::string("\0\1", 2), 3, {true, false, std::nullopt}) ==
           CHIP_NO_ERROR);
    std::string identity = "unchanged";
    assert(endpoints->ResolveThing(3, identity) == CHIP_NO_ERROR &&
           identity == std::string("\0\1", 2));
    identity = "unchanged";
    assert(endpoints->ResolveThing(2, identity) == CHIP_ERROR_NOT_FOUND && identity == "unchanged");
    const auto status = core.Attach(runtime, shared, custody, output, observations);
    attached.store(status == CHIP_NO_ERROR);
    return status;
  }
  bool ResultReady(const BridgeConsumerHandoff::Ticket &ticket) noexcept override {
    return core.ResultReady(ticket);
  }
  bool Retire() noexcept override { return core.Retire(); }
  CHIP_ERROR Finish() noexcept override {
    assert(work_done.load());
    const auto status = core.Finish();
    for (const auto &handler : handlers) assert(handler.held == 0);
    EmberAfAttributeMetadata attribute{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
    attribute.attributeId = 0;
    std::uint8_t state;
    assert(SdkBridgeEndpointBinding::ReadExternal(3, 6, &attribute, &state, 1) == Status::Success);
    assert(state == ((mode == "read-observe" || mode == "write-version") ? 1 : 0));
    if (mode == "write" || mode == "write-denied" || mode == "write-version" ||
        mode == "write-null" || mode == "startup-write" || mode == "startup-read") {
      attribute.attributeId = mode == "write-null" || mode.substr(0, 8) == "startup-" ? 0x4003
                                                                                      : 0x4001;
      std::array<std::uint8_t, 2> value{0, 0};
      assert(SdkBridgeEndpointBinding::ReadExternal(3, 6, &attribute, value.data(), 2) ==
             Status::Success);
      if (mode == "write") {
        std::uint16_t stored;
        std::memcpy(&stored, value.data(), 2);
        assert(stored == 25);
      }
      if (mode == "write-denied" || mode == "write-version") assert(value[0] == 0 && value[1] == 0);
      if (mode == "write-null") assert(value[0] == 0xFF);
      if (mode.substr(0, 8) == "startup-") assert(value[0] == 2);
    }
    if (mode == "groups") {
      assert(chip::Credentials::GetGroupDataProvider()->HasEndpoint(principal.fabricIndex, 7, 3) &&
             handlers[0].data == 1 && handlers[0].statuses == 0 && renderer.completed == 1);
    }
    if (mode == "invoke-denied" || mode == "invoke-timeout" || mode == "invoke-closed" ||
        mode == "invoke-failed" || mode == "invoke-unknown" || mode == "invoke-revoked")
      assert(renderer.completed == 0);
    if (mode == "invoke-closed") assert(handlers[0].result == static_cast<int>(Status::Failure));
    return status;
  }
  Action Read(BridgeRequestMetadata request, chip::app::AttributeValueEncoder &encoder) override {
    return core.Read(request, encoder);
  }
  Action Write(BridgeRequestMetadata request, chip::app::AttributeValueDecoder &decoder) override {
    return core.Write(request, decoder);
  }
  std::optional<Action> Invoke(BridgeRequestMetadata request, chip::TLV::TLVReader &arguments,
                               chip::app::CommandHandler *handler) override {
    return core.Invoke(request, arguments, handler);
  }
  void ListNotification(const chip::app::ConcreteAttributePath &path,
                        chip::app::DataModel::ListWriteOperation operation,
                        chip::FabricIndex fabric) override {
    core.ListNotification(path, operation, fabric);
  }
  void Work() {
    using namespace chip;
    using namespace chip::app;
    if (mode == "startup-read") {
      EmberAfAttributeMetadata attribute{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
      attribute.attributeId = 0x4003;
      std::uint8_t value;
      assert(SdkBridgeEndpointBinding::ReadExternal(3, 6, &attribute, &value, 1) ==
                 Status::Success &&
             value == 2);
      work_done.store(true);
      return;
    }
    if (mode.substr(0, 6) == "invoke" || mode == "groups") {
      const unsigned count = mode == "invoke-full" ? 17 : 1;
      for (unsigned i = 0; i < count; ++i) {
        std::uint8_t bytes[64];
        TLV::TLVWriter writer;
        writer.Init(bytes);
        TLV::TLVType outer;
        assert(writer.StartContainer(TLV::AnonymousTag(), TLV::kTLVType_Structure, outer) ==
               CHIP_NO_ERROR);
        if (mode == "groups") {
          assert(writer.Put(TLV::ContextTag(0), std::uint16_t{7}) == CHIP_NO_ERROR &&
                 writer.PutString(TLV::ContextTag(1), "") == CHIP_NO_ERROR);
        }
        assert(writer.EndContainer(outer) == CHIP_NO_ERROR && writer.Finalize() == CHIP_NO_ERROR);
        TLV::TLVReader arguments;
        arguments.Init(bytes, writer.GetLengthWritten());
        assert(arguments.Next() == CHIP_NO_ERROR);
        const DataModel::InvokeRequest request(
            {3, mode == "groups" ? 4U : 6U, mode == "groups" ? 0U : 1U}, principal);
        const auto returned = provider->InvokeCommand(request, arguments, &handlers[i]);
        if (i < 16)
          assert(!returned && handlers[i].held == 1 && handlers[i].statuses == 0 &&
                 handlers[i].data == 0);
        else
          assert(returned && returned->GetStatusCode().GetStatus() == Status::ResourceExhausted &&
                 handlers[i].held == 0);
      }
      work_status.store(static_cast<int>(Status::Success));
    } else if (mode.substr(0, 5) == "write" || mode == "foreign-decoder" ||
               mode == "startup-write") {
      std::uint8_t bytes[32];
      TLV::TLVWriter writer;
      writer.Init(bytes);
      const bool nullable = mode == "write-null" || mode == "write-invalid" ||
          mode == "startup-write";
      const auto encoded = mode == "write-null" ? writer.PutNull(TLV::AnonymousTag())
          : nullable ? writer.Put(TLV::AnonymousTag(),
                                  static_cast<std::uint8_t>(mode == "startup-write" ? 2 : 3))
                     : writer.Put(TLV::AnonymousTag(), std::uint16_t{25});
      assert(encoded == CHIP_NO_ERROR && writer.Finalize() == CHIP_NO_ERROR);
      TLV::TLVReader reader;
      reader.Init(bytes, writer.GetLengthWritten());
      assert(reader.Next() == CHIP_NO_ERROR);
      auto decoder_principal = principal;
      if (mode == "foreign-decoder") decoder_principal.subject = 43;
      AttributeValueDecoder decoder(reader, decoder_principal);
      ConcreteDataAttributePath path(3, 6, nullable ? 0x4003 : 0x4001);
      if (mode == "write-version") {
        ReadOnlyBufferBuilder<DataModel::ServerClusterEntry> builder;
        assert(provider->ServerClusters(3, builder) == CHIP_NO_ERROR);
        for (const auto &cluster : builder.TakeBuffer())
          if (cluster.clusterId == 6) path.mDataVersion.SetValue(cluster.dataVersion);
        assert(path.mDataVersion.HasValue());
      }
      const DataModel::WriteAttributeRequest request(path, principal);
      const auto result = provider->WriteAttribute(request, decoder);
      work_status.store(static_cast<int>(result.GetStatusCode().GetStatus()));
    } else {
      std::uint8_t bytes[512];
      TLV::TLVWriter writer;
      writer.Init(bytes);
      AttributeReportIBs::Builder reports;
      assert(reports.Init(&writer) == CHIP_NO_ERROR);
      auto subject = principal;
      if (mode == "pase") subject.authMode = Access::AuthMode::kPase;
      const ConcreteAttributePath path(mode == "endpoint" ? 2 : 3, 6, 0);
      AttributeValueEncoder encoder(reports, subject, path, 0);
      DataModel::ReadAttributeRequest request(path, subject);
      request.readFlags.Set(DataModel::ReadFlags::kFabricFiltered);
      const auto result = provider->ReadAttribute(request, encoder);
      work_status.store(static_cast<int>(result.GetStatusCode().GetStatus()));
      if (result.IsSuccess()) {
        assert(reports.EndOfAttributeReportIBs() == CHIP_NO_ERROR &&
               writer.Finalize() == CHIP_NO_ERROR);
        TLV::TLVReader reader;
        reader.Init(bytes, writer.GetLengthWritten());
        assert(reader.Next(TLV::kTLVType_Array, TLV::AnonymousTag()) == CHIP_NO_ERROR);
        TLV::TLVType outer;
        assert(reader.EnterContainer(outer) == CHIP_NO_ERROR && reader.Next() == CHIP_NO_ERROR);
        AttributeReportIB::Parser report;
        AttributeDataIB::Parser data;
        TLV::TLVReader value;
        bool observed = false;
        assert(report.Init(reader) == CHIP_NO_ERROR &&
               report.GetAttributeData(&data) == CHIP_NO_ERROR &&
               data.GetData(&value) == CHIP_NO_ERROR && value.Get(observed) == CHIP_NO_ERROR);
        assert(observed == (mode == "read-observe"));
      }
    }
    work_done.store(true);
  }
  static void WorkEntry(intptr_t context) { reinterpret_cast<Fixture *>(context)->Work(); }
  const std::string_view mode;
  Renderer renderer;
  SdkBridgeConsumerReceiver core;
  SdkBridgeProviderBinding *provider{nullptr};
  SdkBridgeEndpointBinding *endpoints{nullptr};
  BridgeHandoffOwner *owner{nullptr};
  chip::Access::SubjectDescriptor principal;
  std::size_t acl{0};
  std::array<Handler, 17> handlers;
  std::atomic<int> work_status{-1};
  std::atomic<bool> work_done{false}, attached{false};
};
void Await(Fixture &fixture) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (!fixture.work_done.load() && std::chrono::steady_clock::now() < deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(fixture.work_done.load());
}
void AwaitReply(Handler &handler, Status status) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (handler.held.load() != 0 && std::chrono::steady_clock::now() < deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(handler.held == 0 && handler.result == static_cast<int>(status));
}
void CheckFrame(const Json &frame, const Fixture &fixture, std::string_view operation,
                unsigned id) {
  assert(frame.size() == 15 && frame["v"] == 1 && frame["backend"] == "matter-bridge" &&
         frame["type"] == "request" && frame["generation"] == generation &&
         frame["operation"] == operation && frame["id"] == std::to_string(id) &&
         frame["thing"] == "0001" && frame["path"]["endpoint"] == 3);
  assert(frame["principal"]["fabric_index"] == fixture.principal.fabricIndex &&
         frame["principal"]["auth_mode"] == "case" && frame["principal"]["subject"] == "42" &&
         frame["principal"]["cats"][0] == 0x00010002 &&
         frame["fabric_scope"]["fabric_id"] == "17" && frame["fabric_scope"]["bridge_node"] == "1");
}
void Result(int descriptor, unsigned id, std::string_view outcome) {
  Send(descriptor,
       {{"v", 1},
        {"backend", "matter-bridge"},
        {"type", "result"},
        {"generation", generation},
        {"id", std::to_string(id)},
        {"outcome", outcome}});
}
}

int RunSdkReceiverProbe(const std::string &root, std::string_view mode) {
  if (mode == "startup-reopen") {
    // Each child owns exactly one SDK lifetime. Reopen must read the durable
    // value in a fresh process, without relying on a retained SDK cache.
    for (const auto child_mode : {"startup-write", "startup-read"}) {
      if (std::string_view(child_mode) == "startup-read") {
        std::ifstream input(root + "/configuration");
        Json configuration;
        input >> configuration;
        input.close();
        configuration["store_mode"] = "reopen";
        std::ofstream output(root + "/configuration", std::ios::trunc);
        output << configuration.dump();
        output.close();
        assert(output.good());
      }
      const auto child = fork();
      assert(child >= 0);
      if (child == 0) std::_Exit(RunSdkReceiverProbe(root, child_mode));
      int status;
      assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    std::filesystem::remove_all(root);
    std::cout << "guarded SDK receiver and consumer pipes passed\n";
    return 0;
  }
  const std::array<std::string_view, 26> modes{
      "read",          "read-denied",         "read-observe",   "read-timeout",   "write",
      "write-denied",  "write-version",       "write-null",     "write-invalid",  "foreign-decoder",
      "invoke",        "invoke-denied",       "invoke-timeout", "invoke-revoked", "invoke-full",
      "invoke-closed", "invoke-render-error", "pase",           "missing-acl",    "endpoint",
      "read-failed",   "read-unknown",        "invoke-failed",  "invoke-unknown", "startup-write",
      "startup-read"};
  assert(std::find(modes.begin(), modes.end(), mode) != modes.end() || mode == "groups");
  std::signal(SIGPIPE, SIG_IGN);
  Fixture fixture(mode);
  SdkBridgeProcessDriver driver(root + "/configuration", fixture);
  Clock clock;
  std::atomic<bool> cancel{false};
  int input[2], output[2];
  assert(pipe(input) == 0 && pipe(output) == 0);
  std::thread consumer([&] {
    SendControl(input[1], "open");
    assert(Json::parse(Line(output[0]))["type"] == "ready");
    assert(fixture.attached.load());
    assert(chip::DeviceLayer::PlatformMgr().ScheduleWork(
               Fixture::WorkEntry, reinterpret_cast<intptr_t>(&fixture)) == CHIP_NO_ERROR);
    const bool rejected = mode == "pase" || mode == "missing-acl" || mode == "endpoint" ||
        mode == "write-invalid" || mode == "foreign-decoder";
    const bool invoke = mode.substr(0, 6) == "invoke" || mode == "groups";
    const unsigned count = mode == "invoke-full" ? 16 : 1;
    if (mode == "startup-read") {
      Await(fixture);
    } else if (rejected) {
      Await(fixture);
      if (mode == "pase" || mode == "missing-acl")
        assert(fixture.work_status == static_cast<int>(Status::UnsupportedAccess));
      if (mode == "endpoint")
        assert(fixture.work_status == static_cast<int>(Status::UnsupportedEndpoint));
      if (mode == "write-invalid")
        assert(fixture.work_status == static_cast<int>(Status::ConstraintError));
      if (mode == "foreign-decoder")
        assert(fixture.work_status != static_cast<int>(Status::Success));
      Send(input[1],
           {{"v", 1},
            {"backend", "matter-bridge"},
            {"type", "clock-probe"},
            {"generation", generation},
            {"id", "1"}});
      assert(Json::parse(Line(output[0]))["type"] == "clock-sample");
    } else {
      for (unsigned id = 1; id <= count; ++id) {
        const auto frame = Json::parse(Line(output[0]));
        CheckFrame(frame, fixture,
                   invoke                                                        ? "invoke"
                       : mode.substr(0, 5) == "write" || mode == "startup-write" ? "write"
                                                                                 : "read",
                   id);
      }
      if (mode == "read-observe" || mode == "write-version") {
        Send(input[1],
             {{"v", 1},
              {"backend", "matter-bridge"},
              {"type", "observation"},
              {"generation", generation},
              {"id", "1"},
              {"thing", "0001"},
              {"endpoint", 3},
              {"reachable", true},
              {"on_off", true},
              {"temperature", nullptr}});
        const auto receipt = Json::parse(Line(output[0]));
        assert(receipt["type"] == "observation-receipt" && receipt["outcome"] == "applied");
      }
      if (mode == "invoke-revoked") {
        Lock lock;
        assert(chip::Access::GetAccessControl().DeleteEntry(nullptr, fixture.principal.fabricIndex,
                                                            fixture.acl) == CHIP_NO_ERROR);
      }
      if (mode != "read-timeout" && mode != "invoke-timeout" && mode != "invoke-closed")
        for (unsigned id = 1; id <= count; ++id)
          Result(input[1], id,
                 mode == "read-denied" || mode == "write-denied" || mode == "invoke-denied"
                     ? "denied"
                     : mode == "read-failed" || mode == "invoke-failed"   ? "failed"
                     : mode == "read-unknown" || mode == "invoke-unknown" ? "unknown"
                                                                          : "completed");
      if (invoke) {
        Await(fixture);
        if (mode == "invoke-render-error" || mode == "invoke-revoked") {
          assert(Line(output[0]).empty());
          if (mode == "invoke-revoked") AwaitReply(fixture.handlers[0], Status::UnsupportedAccess);
          close(input[1]);
          close(output[0]);
          return;
        }
        if (mode != "invoke-closed")
          for (unsigned id = 0; id < count; ++id)
            AwaitReply(fixture.handlers[id],
                       mode == "invoke-denied"        ? Status::UnsupportedAccess
                           : mode == "invoke-timeout" ? Status::Timeout
                           : mode == "invoke-failed" || mode == "invoke-unknown" ? Status::Failure
                                                                                 : Status::Success);
      } else {
        Await(fixture);
        const auto expected = mode == "read-denied" || mode == "write-denied"
            ? Status::UnsupportedAccess
            : mode == "read-timeout"                          ? Status::Timeout
            : mode == "write-version"                         ? Status::DataVersionMismatch
            : mode == "read-failed" || mode == "read-unknown" ? Status::Failure
                                                              : Status::Success;
        assert(fixture.work_status == static_cast<int>(expected));
      }
    }
    SendControl(input[1], "close");
    assert(Json::parse(Line(output[0])) == Json::parse(Control("closed")) &&
           Line(output[0]).empty());
    close(input[1]);
    close(output[0]);
  });
  const auto status = RunBridgeProcess(input[0], output[1], 5000, clock, driver, cancel);
  close(input[0]);
  close(output[1]);
  consumer.join();
  assert(status ==
         (mode == "invoke-revoked" || mode == "invoke-render-error" ? BridgeProcessExit::Input
                                                                    : BridgeProcessExit::Closed));
  if (mode.substr(0, 8) != "startup-") {
    std::filesystem::remove_all(root);
    std::cout << "guarded SDK receiver and consumer pipes passed\n";
  }
  return 0;
}
} // namespace wotex::matter::testing
