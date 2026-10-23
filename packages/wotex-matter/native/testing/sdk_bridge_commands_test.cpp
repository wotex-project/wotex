#include "sdk_bridge_commands_test.hpp"
#include "wotex_matter/bridge_command_renderer.hpp"
#include "wotex_matter/bridge_sdk_receiver.hpp"
#include "wotex_matter/bridge_light.hpp"

#include <app/MessageDef/AttributeDataIB.h>
#include <app/MessageDef/AttributeReportIB.h>
#include <app/clusters/scenes-server/CodegenIntegration.h>
#include <credentials/GroupDataProvider.h>
#include <credentials/TestOnlyLocalCertificateAuthority.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <lib/support/DefaultStorageKeyAllocator.h>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <csignal>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <poll.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Command rendering fixtures require the separate guarded SDK build.
#endif

namespace wotex::matter::testing {
namespace {
using Json = nlohmann::json;
using Status = chip::Protocols::InteractionModel::Status;
using Action = chip::app::DataModel::ActionReturnStatus;
using Path = chip::app::ConcreteCommandPath;
using ClusterStatus = chip::Protocols::InteractionModel::ClusterStatusCode;
const std::string generation = "01000000000000000000000000000000";
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
void Encode(chip::TLV::TLVWriter &writer, chip::TLV::Tag tag, const Json &value) {
  if (value.is_object() || value.is_array()) {
    chip::TLV::TLVType outer;
    assert(writer.StartContainer(
               tag, value.is_object() ? chip::TLV::kTLVType_Structure : chip::TLV::kTLVType_Array,
               outer) == CHIP_NO_ERROR);
    if (value.is_object()) {
      for (auto field = value.begin(); field != value.end(); ++field)
        Encode(writer, chip::TLV::ContextTag(std::stoul(field.key())), field.value());
    } else
      for (const auto &field : value) Encode(writer, chip::TLV::AnonymousTag(), field);
    assert(writer.EndContainer(outer) == CHIP_NO_ERROR);
  } else if (value.is_string()) {
    const auto &text = value.get_ref<const std::string &>();
    assert(writer.PutString(tag, text.data(), text.size()) == CHIP_NO_ERROR);
  } else if (value.is_null()) assert(writer.PutNull(tag) == CHIP_NO_ERROR);
  else assert(writer.Put(tag, value.get<std::uint64_t>()) == CHIP_NO_ERROR);
}
Json Decode(chip::TLV::TLVReader reader, unsigned depth = 0) {
  assert(depth < 16);
  const auto type = reader.GetType();
  if (type == chip::TLV::kTLVType_Structure || type == chip::TLV::kTLVType_Array) {
    Json result = type == chip::TLV::kTLVType_Structure ? Json::object() : Json::array();
    chip::TLV::TLVType outer;
    assert(reader.EnterContainer(outer) == CHIP_NO_ERROR);
    CHIP_ERROR next;
    while ((next = reader.Next()) == CHIP_NO_ERROR) {
      if (type == chip::TLV::kTLVType_Structure) {
        assert(chip::TLV::IsContextTag(reader.GetTag()));
        result[std::to_string(chip::TLV::TagNumFromTag(reader.GetTag()))] = Decode(reader,
                                                                                   depth + 1);
      } else result.push_back(Decode(reader, depth + 1));
    }
    assert(next == CHIP_END_OF_TLV && reader.ExitContainer(outer) == CHIP_NO_ERROR);
    return result;
  }
  if (type == chip::TLV::kTLVType_UTF8String) {
    chip::CharSpan value;
    assert(reader.Get(value) == CHIP_NO_ERROR);
    return std::string(value.data(), value.size());
  }
  if (type == chip::TLV::kTLVType_Null) return nullptr;
  if (type == chip::TLV::kTLVType_Boolean) {
    bool value;
    assert(reader.Get(value) == CHIP_NO_ERROR);
    return value;
  }
  std::uint64_t value;
  assert(reader.Get(value) == CHIP_NO_ERROR);
  return value;
}
void Send(int descriptor, const Json &frame) {
  const auto bytes = frame.dump() + '\n';
  assert(write(descriptor, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
}
Json Control(std::string_view type) {
  return {{"v", 1}, {"backend", "matter-bridge"}, {"type", type}, {"generation", generation}};
}
std::string Line(int descriptor) {
  std::string bytes;
  const auto limit = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (std::chrono::steady_clock::now() < limit) {
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
  assert(false && "command pipe wait exceeded its bound");
  return {};
}
class Handler final : public chip::app::CommandHandler {
 public:
  chip::Access::SubjectDescriptor principal;
  std::atomic<unsigned> held{0}, statuses{0}, data{0}, attempts{0};
  std::atomic<int> result{-1};
  std::array<std::uint8_t, 8192> bytes{};
  std::size_t length{0};
  chip::CommandId response{chip::kInvalidCommandId};
  bool refuse_data{false};
  void Reset() {
    assert(held == 0);
    statuses = 0;
    data = 0;
    attempts = 0;
    result = -1;
    length = 0;
    response = chip::kInvalidCommandId;
  }
  CHIP_ERROR FallibleAddStatus(const Path &, const ClusterStatus &status, const char *) override {
    result = static_cast<int>(status.GetStatus());
    ++statuses;
    return CHIP_NO_ERROR;
  }
  void AddStatus(const Path &path, const ClusterStatus &status, const char *context) override {
    assert(FallibleAddStatus(path, status, context) == CHIP_NO_ERROR);
  }
  CHIP_ERROR AddResponseData(const Path &, chip::CommandId id,
                             const chip::app::DataModel::EncodableToTLV &value) override {
    ++attempts;
    if (refuse_data) return CHIP_ERROR_NO_MEMORY;
    chip::TLV::TLVWriter writer;
    writer.Init(bytes.data(), bytes.size());
    chip::app::DataModel::FabricAwareTLVWriter fabric(writer, principal.fabricIndex);
    ReturnErrorOnFailure(value.EncodeTo(fabric, chip::TLV::AnonymousTag()));
    ReturnErrorOnFailure(writer.Finalize());
    length = writer.GetLengthWritten();
    response = id;
    ++data;
    result = static_cast<int>(Status::Success);
    return CHIP_NO_ERROR;
  }
  void AddResponse(const Path &path, chip::CommandId id,
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
struct Case {
  unsigned endpoint, cluster, command;
  Json body;
  int response;
  Json expected;
};
Json Pair(unsigned value) { return {{"0", 0}, {"1", value}}; }
Json Extensions(unsigned value) {
  return Json::array({{{"0", 6}, {"1", Json::array({Pair(value)})}}});
}
std::vector<Case> Cases(std::string_view mode) {
  const Case add{3, 4, 0, {{"0", 7}, {"1", ""}}, 0, {{"0", 0}, {"1", 7}}};
  const Case scene{3, 98,
                   0, {{"0", 7}, {"1", 1}, {"2", 0}, {"3", ""}, {"4", Extensions(1)}},
                   0, {{"0", 0}, {"1", 7}, {"2", 1}}};
  const Case view{3, 98,
                  1, {{"0", 7}, {"1", 1}},
                  1, {{"0", 0}, {"1", 7}, {"2", 1}, {"3", 0}, {"4", ""}, {"5", Extensions(1)}}};
  if (mode == "seed") return {add, scene};
  if (mode == "restore") return {view, {3, 98, 5, {{"0", 7}, {"1", 1}}, -1, {}}};
  if (mode == "observations") return {add, scene, {3, 98, 5, {{"0", 7}, {"1", 1}}, -1, {}}};
  if (mode == "unavailable")
    return {{3, 98, 4, {{"0", 0}, {"1", 1}}, 4, {{"0", static_cast<unsigned>(Status::Failure)}}}};
  if (mode == "multi")
    return {add,
            {5, 4, 0, {{"0", 7}, {"1", ""}}, 0, {{"0", 0}, {"1", 7}}},
            {3, 98, 4, {{"0", 7}, {"1", 1}}, 4, {{"0", 0}}},
            {5, 98, 4, {{"0", 7}, {"1", 1}}, 4, {{"0", 0}}},
            {3, 98, 1, {{"0", 7}, {"1", 1}}, 1, {{"0", 0}, {"5", Extensions(0)}}},
            {5, 98, 1, {{"0", 7}, {"1", 1}}, 1, {{"0", 0}, {"5", Extensions(1)}}},
            {5, 98, 5, {{"0", 7}, {"1", 1}}, -1, {}}};
  if (mode != "all" && mode != "timers" && mode != "remove") return {add};
  auto result = std::vector<Case>{
      add,
      {3, 3, 0, {{"0", 10}}, -1, {}},
      {3, 4, 5, {{"0", 8}, {"1", ""}}, -1, {}},
      {3, 4, 1, {{"0", 7}}, 1, {{"0", 0}, {"1", 7}, {"2", ""}}},
      {3, 4, 2, {{"0", Json::array({7, 8})}}, 2, {{"1", Json::array({7, 8})}}},
      {3, 6, 1, Json::object(), -1, {}},
      {3, 6, 0, Json::object(), -1, {}},
      {3, 6, 2, Json::object(), -1, {}},
      {3, 6, 64, {{"0", 0}, {"1", 0}}, -1, {}},
      {3, 6, 65, Json::object(), -1, {}},
      {3, 6, 66, {{"0", 0}, {"1", 30}, {"2", 20}}, -1, {}},
      scene,
      view,
      {3, 98, 4, {{"0", 7}, {"1", 2}}, 4, {{"0", 0}, {"1", 7}, {"2", 2}}},
      {3, 98, 1, {{"0", 7}, {"1", 2}}, 1, {{"0", 0}, {"1", 7}, {"2", 2}, {"5", Extensions(0)}}},
      {3, 98, 5, {{"0", 7}, {"1", 1}, {"2", nullptr}}, -1, {}},
      {3, 98, 6, {{"0", 7}}, 6, {{"0", 0}, {"2", 7}, {"3", Json::array({1, 2})}}},
      {3,
       98,
       64,
       {{"0", 0}, {"1", 7}, {"2", 1}, {"3", 7}, {"4", 3}},
       64,
       {{"0", 0}, {"1", 7}, {"2", 1}}},
      {3, 98, 2, {{"0", 7}, {"1", 3}}, 2, {{"0", 0}, {"1", 7}, {"2", 3}}},
      {3, 98, 3, {{"0", 7}}, 3, {{"0", 0}, {"1", 7}}},
      {3, 98, 6, {{"0", 7}}, 6, {{"0", 0}, {"2", 7}, {"3", Json::array()}}},
      {3, 4, 3, {{"0", 7}}, 3, {{"0", 0}, {"1", 7}}},
      {3, 4, 4, Json::object(), -1, {}},
      {3, 3, 64, {{"0", 0}, {"1", 0}}, -1, {}},
      {4, 3, 0, {{"0", 1}}, -1, {}}};
  if (mode == "timers" || mode == "remove")
    for (auto &test : result) {
      if (test.cluster == 98 && test.command == 5) test.body["2"] = 300;
      if (mode == "timers" && test.cluster == 6 && test.command == 66) {
        test.body["1"] = 3;
        test.body["2"] = 2;
      }
    }
  return result;
}
class Fixture final : public BridgeSdkProcessReceiver {
 public:
  explicit Fixture(std::string_view selected)
      : mode(selected), cases(Cases(selected)), core(renderer) {
    BridgeInvocation none;
    assert(renderer.Completed(handler, none) == CHIP_ERROR_INCORRECT_STATE);
  }
  CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, BridgeConsumerHandoff &shared,
                    BridgeHandoffOwner &owner, BridgeOutputOwner &output,
                    SdkBridgeObservationOwner &observations) noexcept override try {
    provider = runtime.provider();
    endpoints = runtime.endpoints();
    storage = &chip::Server::GetInstance().GetPersistentStorage();
    auto &table = chip::Server::GetInstance().GetFabricTable();
    chip::FabricIndex index = chip::kUndefinedFabricIndex;
    if (mode == "restore") {
      for (const auto &fabric : table) {
        index = fabric.GetFabricIndex();
        break;
      }
      assert(chip::IsValidFabricIndex(index));
    } else {
      chip::Credentials::TestOnlyLocalCertificateAuthority authority;
      authority.Init();
      std::uint8_t bytes[chip::Crypto::kMIN_CSR_Buffer_Size];
      chip::MutableByteSpan csr(bytes);
      assert(table.AllocatePendingOperationalKey(chip::NullOptional, csr) == CHIP_NO_ERROR);
      authority.GenerateNocChain(17, 1, csr);
      assert(authority.GetStatus() == CHIP_NO_ERROR &&
             table.AddNewPendingTrustedRootCert(authority.GetRcac()) == CHIP_NO_ERROR &&
             table.AddNewPendingFabricWithOperationalKeystore(
                 authority.GetNoc(), authority.GetIcac(), static_cast<chip::VendorId>(0xFFF1),
                 &index, chip::FabricTable::AdvertiseIdentity::No) == CHIP_NO_ERROR &&
             table.CommitPendingFabricData() == CHIP_NO_ERROR);
    }
    handler.principal.fabricIndex = index;
    handler.principal.subject = 42;
    handler.principal.authMode = chip::Access::AuthMode::kCase;
    if (mode != "restore") {
      auto &access = chip::Access::GetAccessControl();
      chip::Access::AccessControl::Entry entry;
      assert(access.PrepareEntry(entry) == CHIP_NO_ERROR &&
             entry.SetFabricIndex(index) == CHIP_NO_ERROR &&
             entry.SetPrivilege(chip::Access::Privilege::kAdminister) == CHIP_NO_ERROR &&
             entry.SetAuthMode(chip::Access::AuthMode::kCase) == CHIP_NO_ERROR &&
             entry.AddSubject(nullptr, 42) == CHIP_NO_ERROR &&
             access.CreateEntry(nullptr, index, &acl, entry) == CHIP_NO_ERROR);
      using Groups = chip::Credentials::GroupDataProvider;
      Groups::KeySet keys(1, Groups::SecurityPolicy::kTrustFirst, 1);
      std::fill(std::begin(keys.epoch_keys[0].key), std::end(keys.epoch_keys[0].key), 0x5a);
      std::uint8_t compressed[8];
      chip::MutableByteSpan fabric(compressed);
      assert(table.FindFabricWithIndex(index)->GetCompressedFabricIdBytes(fabric) == CHIP_NO_ERROR);
      auto *groups = chip::Credentials::GetGroupDataProvider();
      assert(groups->SetKeySet(index, fabric, keys) == CHIP_NO_ERROR &&
             groups->SetGroupKey(index, 7, 1) == CHIP_NO_ERROR &&
             groups->SetGroupKey(index, 8, 1) == CHIP_NO_ERROR);
    }
    assert(!ReadOnOff().has_value());
    if (mode != "unavailable")
      assert(endpoints->Observe(std::string("\0\1", 2), 3, {true, false, {}}) == CHIP_NO_ERROR);
    if (mode == "multi") {
      BridgeEndpoint added;
      assert(endpoints->Add(
                 {std::string("\0\3", 2), BridgedDeviceType::OnOffLight, "second light", {}, {}},
                 added) == CHIP_NO_ERROR &&
             added.endpoint == 5);
      assert(endpoints->Observe(std::string("\0\3", 2), 5, {true, true, {}}) == CHIP_NO_ERROR);
    }
    assert(renderer.Attach(*endpoints) == CHIP_NO_ERROR &&
           renderer.Attach(*endpoints) == CHIP_ERROR_INCORRECT_STATE);
    handler.refuse_data = mode == "encoding";
    return core.Attach(runtime, shared, owner, output, observations);
  } catch (...) {
    return CHIP_ERROR_INTERNAL;
  }
  bool ResultReady(const BridgeConsumerHandoff::Ticket &ticket) noexcept override {
    return core.ResultReady(ticket);
  }
  bool Retire() noexcept override { return core.Retire(); }
  CHIP_ERROR Finish() noexcept override try {
    assert(handler.held == 0);
    if (removed || mode == "unavailable") assert(!ReadOnOff().has_value());
    else assert(ReadOnOff() == (mode == "observations"));
    const auto status = core.Finish();
    assert(renderer.Finish() == CHIP_NO_ERROR && renderer.Finish() == CHIP_ERROR_INCORRECT_STATE);
    BridgeInvocation none;
    assert(renderer.Completed(handler, none) == CHIP_ERROR_INCORRECT_STATE);
    return status;
  } catch (...) {
    return CHIP_ERROR_INTERNAL;
  }
  Action Read(BridgeRequestMetadata request, chip::app::AttributeValueEncoder &encoder) override {
    return core.Read(request, encoder);
  }
  Action Write(BridgeRequestMetadata request, chip::app::AttributeValueDecoder &decoder) override {
    return core.Write(request, decoder);
  }
  std::optional<Action> Invoke(BridgeRequestMetadata request, chip::TLV::TLVReader &arguments,
                               chip::app::CommandHandler *response) override {
    return core.Invoke(request, arguments, response);
  }
  void ListNotification(const chip::app::ConcreteAttributePath &path,
                        chip::app::DataModel::ListWriteOperation operation,
                        chip::FabricIndex fabric) override {
    core.ListNotification(path, operation, fabric);
  }
  std::optional<Json> ReadValue(unsigned endpoint, unsigned cluster, unsigned member) {
    std::uint8_t bytes[8192];
    chip::TLV::TLVWriter writer;
    writer.Init(bytes);
    chip::app::AttributeReportIBs::Builder reports;
    assert(reports.Init(&writer) == CHIP_NO_ERROR);
    const chip::app::ConcreteAttributePath path(endpoint, cluster, member);
    chip::app::AttributeValueEncoder encoder(reports, handler.principal, path, 0);
    chip::app::DataModel::ReadAttributeRequest request(path, handler.principal);
    if (!chip::app::CodegenDataModelProvider::Instance().ReadAttribute(request, encoder).IsSuccess())
      return {};
    assert(reports.EndOfAttributeReportIBs() == CHIP_NO_ERROR &&
           writer.Finalize() == CHIP_NO_ERROR);
    chip::TLV::TLVReader reader;
    reader.Init(bytes, writer.GetLengthWritten());
    assert(reader.Next() == CHIP_NO_ERROR);
    chip::TLV::TLVType outer;
    assert(reader.EnterContainer(outer) == CHIP_NO_ERROR && reader.Next() == CHIP_NO_ERROR);
    chip::app::AttributeReportIB::Parser report;
    chip::app::AttributeDataIB::Parser data;
    chip::TLV::TLVReader value;
    assert(report.Init(reader) == CHIP_NO_ERROR &&
           report.GetAttributeData(&data) == CHIP_NO_ERROR &&
           data.GetData(&value) == CHIP_NO_ERROR);
    return Decode(value);
  }
  std::optional<bool> ReadOnOff(unsigned endpoint = 3) {
    const auto value = ReadValue(endpoint, 6, 0);
    if (!value) return {};
    return value->get<bool>();
  }
  void Volatile(unsigned endpoint = 3) {
    const auto key = chip::DefaultStorageKeyAllocator::AttributeValue(endpoint, 6, 0);
    std::uint8_t inferred;
    std::uint16_t size = 1;
    assert(storage->SyncGetKeyValue(key.KeyName(), &inferred, size) ==
           CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND);
  }
  void Work() {
    const auto &test = cases.at(step.load());
    std::uint8_t bytes[8192];
    chip::TLV::TLVWriter writer;
    writer.Init(bytes);
    Encode(writer, chip::TLV::AnonymousTag(), test.body);
    assert(writer.Finalize() == CHIP_NO_ERROR);
    chip::TLV::TLVReader arguments;
    arguments.Init(bytes, writer.GetLengthWritten());
    assert(arguments.Next() == CHIP_NO_ERROR);
    const chip::app::DataModel::InvokeRequest request(
        {static_cast<chip::EndpointId>(test.endpoint), test.cluster, test.command},
        handler.principal);
    const auto result = provider->InvokeCommand(request, arguments, &handler);
    assert(!result && handler.held == 1 && handler.statuses == 0 && handler.data == 0);
    work_done = true;
  }
  static void Entry(intptr_t context) { reinterpret_cast<Fixture *>(context)->Work(); }
  const std::string_view mode;
  const std::vector<Case> cases;
  Handler handler;
  SdkBridgeCommandRenderer renderer;
  SdkBridgeConsumerReceiver core;
  SdkBridgeProviderBinding *provider{nullptr};
  SdkBridgeEndpointBinding *endpoints{nullptr};
  chip::PersistentStorageDelegate *storage{nullptr};
  std::size_t acl{0};
  bool removed{false};
  std::atomic<std::size_t> step{0};
  std::atomic<bool> work_done{false};
};
template <typename F> void Await(F condition) {
  const auto limit = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (!condition() && std::chrono::steady_clock::now() < limit)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(condition());
}
void Subset(const Json &actual, const Json &expected) {
  for (auto field = expected.begin(); field != expected.end(); ++field) {
    if (!actual.contains(field.key()) || actual[field.key()] != field.value())
      std::cerr << "native command response differs at " << field.key() << ": " << actual.dump()
                << '\n';
    assert(actual.contains(field.key()) && actual[field.key()] == field.value());
  }
}
}

int RunSdkCommandsProbe(const std::string &root, std::string_view mode) {
  if (mode == "reopen") {
    for (auto child_mode : {"seed", "restore"}) {
      if (std::string_view(child_mode) == "restore") {
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
      if (child == 0) std::_Exit(RunSdkCommandsProbe(root, child_mode));
      int status;
      assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    std::filesystem::remove_all(root);
    std::cout << "guarded SDK command rendering and canonical observations passed\n";
    return 0;
  }
  assert(mode == "all" || mode == "denied" || mode == "timeout" || mode == "encoding" ||
         mode == "seed" || mode == "restore" || mode == "timers" || mode == "remove" ||
         mode == "revoked" || mode == "observations" || mode == "unavailable" || mode == "multi");
  std::signal(SIGPIPE, SIG_IGN);
  Fixture fixture(mode);
  SdkBridgeProcessDriver driver(root + "/configuration", fixture);
  Clock clock;
  std::atomic<bool> cancel{false};
  int input[2], output[2];
  assert(pipe(input) == 0 && pipe(output) == 0);
  std::thread consumer([&] {
    Send(input[1], Control("open"));
    assert(Json::parse(Line(output[0]))["type"] == "ready");
    for (std::size_t i = 0; i < fixture.cases.size(); ++i) {
      const auto &test = fixture.cases[i];
      {
        Lock lock;
        fixture.handler.Reset();
        fixture.step = i;
        fixture.work_done = false;
        assert(chip::DeviceLayer::PlatformMgr().ScheduleWork(
                   Fixture::Entry, reinterpret_cast<intptr_t>(&fixture)) == CHIP_NO_ERROR);
      }
      const auto request = Json::parse(Line(output[0]));
      assert(
          request["type"] == "request" && request["operation"] == "invoke" &&
          request["generation"] == generation && request["id"] == std::to_string(i + 1) &&
          request["path"]["endpoint"] == test.endpoint &&
          request["path"]["cluster"] == test.cluster && request["path"]["member"] == test.command &&
          request["thing"] ==
              (test.endpoint == 3       ? "0001"
                   : test.endpoint == 4 ? "0002"
                                        : "0003") &&
          request["principal"]["fabric_index"] == fixture.handler.principal.fabricIndex &&
          request["principal"]["subject"] == "42" && request["fabric_scope"]["fabric_id"] == "17");
      Await([&] { return fixture.work_done.load(); });
      {
        Lock lock;
        assert(fixture.handler.held == 1 && fixture.handler.statuses == 0 &&
               fixture.handler.data == 0);
        if (mode == "unavailable") assert(!fixture.ReadOnOff());
        else assert(fixture.ReadOnOff() == false);
        if (mode == "revoked")
          assert(chip::Access::GetAccessControl().DeleteEntry(
                     nullptr, fixture.handler.principal.fabricIndex, fixture.acl) == CHIP_NO_ERROR);
      }
      if (mode != "timeout")
        Send(input[1],
             {{"v", 1},
              {"backend", "matter-bridge"},
              {"type", "result"},
              {"generation", generation},
              {"id", std::to_string(i + 1)},
              {"outcome", mode == "denied" ? "denied" : "completed"}});
      Await([&] { return fixture.handler.held.load() == 0; });
      {
        Lock lock;
        if (mode == "unavailable") assert(!fixture.ReadOnOff());
        else assert(fixture.ReadOnOff() == false);
        if (mode == "multi") assert(fixture.ReadOnOff(5) == true);
        auto *groups = chip::Credentials::GetGroupDataProvider();
        if (mode == "denied" || mode == "timeout" || mode == "revoked") {
          assert(fixture.handler.result ==
                     static_cast<int>(mode == "timeout" ? Status::Timeout
                                                        : Status::UnsupportedAccess) &&
                 !groups->HasEndpoint(fixture.handler.principal.fabricIndex, 7, 3));
        } else if (mode == "encoding") {
          assert(fixture.handler.attempts == 1 && fixture.handler.data == 0 &&
                 fixture.handler.statuses == 1 &&
                 fixture.handler.result == static_cast<int>(Status::Failure) &&
                 groups->HasEndpoint(fixture.handler.principal.fabricIndex, 7, 3));
        } else if (test.response < 0) {
          assert(fixture.handler.statuses == 1 && fixture.handler.data == 0 &&
                 fixture.handler.result == static_cast<int>(Status::Success));
        } else {
          assert(fixture.handler.statuses == 0 && fixture.handler.data == 1 &&
                 fixture.handler.response == static_cast<chip::CommandId>(test.response));
          chip::TLV::TLVReader reply;
          reply.Init(fixture.handler.bytes.data(), fixture.handler.length);
          assert(reply.Next() == CHIP_NO_ERROR);
          Subset(Decode(reply), test.expected);
        }
        if (mode == "all" || mode == "timers" || mode == "remove") {
          if (test.cluster == 3 && test.command == 0)
            assert(fixture.ReadValue(test.endpoint, 3, 0) == Json(test.body["0"]) &&
                   fixture.ReadValue(test.endpoint, 3, 1) == Json(0));
          if (test.cluster == 3 && test.command == 64)
            assert(fixture.ReadValue(3, 3, 0) == Json(0));
          if (test.cluster == 6 && test.command <= 2) {
            auto *cluster = chip::app::CodegenDataModelProvider::Instance().Registry().Get({3, 6});
            assert(cluster &&
                   static_cast<SdkBridgeLightCluster *>(cluster)->GetOnOff() ==
                       (test.command != 0));
          }
          if (test.cluster == 6 && test.command == 64)
            assert(fixture.ReadValue(3, 6, 0x4000) == Json(false));
          if (test.cluster == 6 && test.command == 65)
            assert(fixture.ReadValue(3, 6, 0x4000) == Json(true));
          if (test.cluster == 6 && test.command == 66) {
            const auto on_time = fixture.ReadValue(3, 6, 0x4001);
            assert(on_time && on_time->get<unsigned>() > 0 &&
                   on_time->get<unsigned>() <= test.body["1"].get<unsigned>() &&
                   fixture.ReadValue(3, 6, 0x4002) == test.body["2"]);
          }
        }
        fixture.Volatile();
        if (mode == "multi") fixture.Volatile(5);
      }
    }
    if (mode == "all" || mode == "timers" || mode == "remove") {
      Lock lock;
      const auto fabric = fixture.handler.principal.fabricIndex;
      auto *groups = chip::Credentials::GetGroupDataProvider();
      assert(!groups->HasEndpoint(fabric, 7, 3) && !groups->HasEndpoint(fabric, 8, 3));
    }
    if (mode == "observations") {
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
      Lock lock;
      assert(fixture.ReadOnOff() == true);
      const auto info = fixture.ReadValue(3, 98, 2);
      assert(info && info->is_array() && info->size() == 1 && (*info)[0]["3"] == false);
      fixture.Volatile();
    }
    if (mode == "timers") {
      std::this_thread::sleep_for(std::chrono::milliseconds(800));
      Lock lock;
      assert(fixture.ReadOnOff() == false && fixture.ReadValue(3, 6, 0x4001) == Json(0) &&
             fixture.ReadValue(3, 6, 0x4002) == Json(0));
      fixture.Volatile();
    }
    if (mode == "remove") {
      {
        Lock lock;
        assert(fixture.endpoints->Remove(std::string("\0\1", 2)) == CHIP_NO_ERROR &&
               fixture.endpoints->Remove(std::string("\0\2", 2)) == CHIP_NO_ERROR);
        fixture.removed = true;
        BridgeEndpoint replacement;
        assert(fixture.endpoints->Add(
                   {"replacement", BridgedDeviceType::OnOffLight, "replacement", {}, {}},
                   replacement) == CHIP_NO_ERROR &&
               replacement.endpoint == 5 && !fixture.ReadOnOff(5));
        assert(fixture.endpoints->Remove("replacement") == CHIP_NO_ERROR);
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1100));
      Lock lock;
      for (unsigned endpoint : {3, 4, 5}) {
        auto clusters =
            chip::app::CodegenDataModelProvider::Instance().Registry().ClustersOnEndpoint(endpoint);
        assert(clusters.begin() == clusters.end() && !fixture.ReadOnOff(endpoint));
      }
    }
    if (mode == "encoding" || mode == "revoked") assert(Line(output[0]).empty());
    else {
      Send(input[1], Control("close"));
      assert(Json::parse(Line(output[0])) == Control("closed") && Line(output[0]).empty());
    }
    close(input[1]);
    close(output[0]);
  });
  const auto result = RunBridgeProcess(input[0], output[1], 5000, clock, driver, cancel);
  close(input[0]);
  close(output[1]);
  consumer.join();
  assert(result ==
         (mode == "encoding" || mode == "revoked" ? BridgeProcessExit::Input
                                                  : BridgeProcessExit::Closed));
  if (mode != "seed" && mode != "restore") {
    std::filesystem::remove_all(root);
    std::cout << "guarded SDK command rendering and canonical observations passed\n";
  }
  return 0;
}
}
