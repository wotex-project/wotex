#include "sdk_bridge_process_test.hpp"
#include "wotex_matter/bridge_sdk_process.hpp"

#include <app/server/Server.h>
#include <app/AttributeValueEncoder.h>
#include <app/MessageDef/AttributeDataIB.h>
#include <app/MessageDef/AttributeReportIB.h>
#include <credentials/DeviceAttestationCredsProvider.h>
#include <lib/support/CHIPMem.h>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <csignal>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <poll.h>
#include <thread>
#include <unistd.h>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error SDK process fixtures must remain separate from production execution.
#endif

namespace wotex::matter::testing {
namespace {
using Json = nlohmann::json;
using Handoff = BridgeConsumerHandoff;
using Status = chip::Protocols::InteractionModel::Status;
using Exit = BridgeProcessExit;
const std::string generation = "01000000000000000000000000000000";
std::string Control(std::string_view role) {
  return "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"" + std::string(role) +
      "\",\"generation\":\"" + generation + "\"}\n";
}
void Send(int descriptor, std::string_view frame) {
  assert(write(descriptor, frame.data(), frame.size()) == static_cast<ssize_t>(frame.size()));
}
std::string Line(int descriptor) {
  std::string frame;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (std::chrono::steady_clock::now() < deadline) {
    pollfd source{descriptor, POLLIN, 0};
    assert(poll(&source, 1, 100) >= 0);
    if (!(source.revents & (POLLIN | POLLHUP))) continue;
    char byte = 0;
    const auto count = read(descriptor, &byte, 1);
    if (count == 0) return frame;
    assert(count == 1 && frame.size() < 1024);
    frame += byte;
    if (byte == '\n') return frame;
  }
  assert(false && "SDK process pipe wait exceeded its bound");
  return {};
}
class StackLock final {
 public:
  StackLock() { chip::DeviceLayer::PlatformMgr().LockChipStack(); }
  ~StackLock() { chip::DeviceLayer::PlatformMgr().UnlockChipStack(); }
};
void CheckLight(std::optional<bool> expected) {
  EmberAfAttributeMetadata attribute{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
  attribute.attributeId = 0;
  std::uint8_t value = 0xA5;
  const auto status = SdkBridgeEndpointBinding::ReadExternal(3, 6, &attribute, &value, 1);
  if (expected) assert(status == Status::Success && value == (*expected ? 1 : 0));
  else assert(status == Status::Failure && value == 0xA5);
}
template <typename Value>
void CheckValue(chip::EndpointId endpoint, chip::ClusterId cluster, chip::AttributeId attribute,
                std::optional<Value> expected) {
  using namespace chip;
  using namespace chip::app;
  std::uint8_t bytes[512];
  TLV::TLVWriter writer;
  writer.Init(bytes);
  AttributeReportIBs::Builder reports;
  assert(reports.Init(&writer) == CHIP_NO_ERROR);
  Access::SubjectDescriptor subject;
  const ConcreteAttributePath path(endpoint, cluster, attribute);
  AttributeValueEncoder encoder(reports, subject, path, 0);
  const DataModel::ReadAttributeRequest request(path, subject);
  assert(CodegenDataModelProvider::Instance().ReadAttribute(request, encoder).IsSuccess());
  assert(reports.EndOfAttributeReportIBs() == CHIP_NO_ERROR && writer.Finalize() == CHIP_NO_ERROR);
  TLV::TLVReader reader;
  reader.Init(bytes, writer.GetLengthWritten());
  assert(reader.Next(TLV::kTLVType_Array, TLV::AnonymousTag()) == CHIP_NO_ERROR);
  TLV::TLVType outer;
  assert(reader.EnterContainer(outer) == CHIP_NO_ERROR);
  assert(reader.Next(TLV::kTLVType_Structure, TLV::AnonymousTag()) == CHIP_NO_ERROR);
  AttributeReportIB::Parser report;
  AttributeDataIB::Parser data;
  TLV::TLVReader value;
  assert(report.Init(reader) == CHIP_NO_ERROR && report.GetAttributeData(&data) == CHIP_NO_ERROR &&
         data.GetData(&value) == CHIP_NO_ERROR);
  if (!expected) assert(value.GetType() == TLV::kTLVType_Null);
  else {
    Value actual{};
    assert(value.Get(actual) == CHIP_NO_ERROR && actual == *expected);
  }
}
Json Observation(std::uint64_t id, std::string_view thing = "0001", std::uint16_t endpoint = 3,
                 Json on_off = true, Json temperature = nullptr, bool reachable = true) {
  return {{"v", 1},
          {"backend", "matter-bridge"},
          {"type", "observation"},
          {"generation", generation},
          {"id", std::to_string(id)},
          {"thing", thing},
          {"endpoint", endpoint},
          {"reachable", reachable},
          {"on_off", on_off},
          {"temperature", temperature}};
}
void Receipt(int descriptor, std::uint64_t id, bool applied = true) {
  const auto received = Json::parse(Line(descriptor));
  assert(received ==
         Json({{"v", 1},
               {"backend", "matter-bridge"},
               {"type", "observation-receipt"},
               {"generation", generation},
               {"id", std::to_string(id)},
               {"outcome", applied ? "applied" : "refused"}}));
}
void AwaitClosed(BridgeHandoffOwner &owner) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
  while (std::chrono::steady_clock::now() < deadline) {
    if (owner.With([](auto &custody, auto) { return custody.closed(); })) return;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(false && "observation closure did not retire input");
}
class Clock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
};
class Receiver final : public BridgeSdkProcessReceiver {
 public:
  explicit Receiver(std::string_view selection) : mode(selection) {}
  CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, BridgeConsumerHandoff &shared,
                    BridgeHandoffOwner &custody, BridgeOutputOwner &output) noexcept override try {
    assert(attached == 0 && finished == 0 && runtime.provider() && runtime.endpoints());
    assert(!shared.closed() && shared.pending() == 0);
    ++attached;
    owner = &custody;
    assert(
        !chip::Server::GetInstance().GetCommissioningWindowManager().IsCommissioningWindowOpen());
    chip::ReadOnlyBufferBuilder<chip::app::DataModel::EndpointEntry> builder;
    assert(runtime.provider()->Endpoints(builder) == CHIP_NO_ERROR);
    const auto entries = builder.TakeBuffer();
    assert(entries.size() == 4);
    for (const auto endpoint : {0, 1, 3, 4}) {
      bool found = false;
      for (const auto &entry : entries)
        if (entry.id == endpoint) found = true;
      assert(found);
    }
    if (mode == "attach-fail") return CHIP_ERROR_INCORRECT_STATE;
    if (mode == "result" || mode == "result-refuse" || mode == "pending" ||
        mode == "observation-result") {
      custody.With([&](auto &handoff, auto now) {
        assert(handoff.Reserve(now, now + 500, ticket) == Handoff::Admission::Reserved);
        assert(output.Push(BridgeOutputOwner::Kind::Request, "{\"fixture\":\"request\"}\n") ==
               BridgeOutputOwner::Admission::Accepted);
      });
    }
    return CHIP_NO_ERROR;
  } catch (...) {
    return CHIP_ERROR_NO_MEMORY;
  }
  bool ResultReady(const Handoff::Ticket &received) noexcept override {
    assert(owner && received.id == ticket.id && received.generation == ticket.generation);
    owner->With([&](auto &handoff, auto now) {
      Handoff::Outcome outcome;
      assert(handoff.Take(received, now, outcome) == Handoff::Consume::Completed);
      assert(outcome == Handoff::Outcome::Completed);
    });
    ++results;
    return mode != "result-refuse";
  }
  CHIP_ERROR Finish() noexcept override {
    assert(attached == 1 && finished == 0);
    ++finished;
    if (mode == "finish-fail") return CHIP_ERROR_INCORRECT_STATE;
    owner->With([&](auto &handoff, auto now) {
      assert(handoff.closed());
      if (ticket.id && results.load() == 0) {
        Handoff::Outcome outcome;
        assert(handoff.Take(ticket, now, outcome) == Handoff::Consume::Completed);
        assert(outcome == Handoff::Outcome::Closed);
      }
      assert(handoff.pending() == 0);
    });
    if (mode.substr(0, 11) == "observation") {
      const bool known_light = mode == "observation-long" || mode == "observation-refused" ||
          mode == "observation-credit" || mode == "observation-result" ||
          mode == "observation-replay";
      CheckLight(known_light ? std::optional<bool>(true) : std::nullopt);
      CheckValue<std::int16_t>(4, 1026, 0,
                               mode == "observations" ? std::optional<std::int16_t>(4000)
                                   : mode == "observation-refused"
                                   ? std::optional<std::int16_t>(1000)
                                   : std::nullopt);
    }
    return CHIP_NO_ERROR;
  }
  chip::app::DataModel::ActionReturnStatus Read(BridgeRequestMetadata,
                                                chip::app::AttributeValueEncoder &) override {
    return Status::UnsupportedAccess;
  }
  chip::app::DataModel::ActionReturnStatus Write(BridgeRequestMetadata,
                                                 chip::app::AttributeValueDecoder &) override {
    return Status::UnsupportedAccess;
  }
  std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(
      BridgeRequestMetadata, chip::TLV::TLVReader &, chip::app::CommandHandler *) override {
    return chip::app::DataModel::ActionReturnStatus(Status::UnsupportedAccess);
  }
  void ListNotification(const chip::app::ConcreteAttributePath &,
                        chip::app::DataModel::ListWriteOperation, chip::FabricIndex) override {}
  const std::string_view mode;
  BridgeHandoffOwner *owner{nullptr};
  Handoff::Ticket ticket;
  std::atomic<unsigned> attached{0}, finished{0}, results{0};
};

void ExerciseObservations(std::string_view mode, int input, int output, Receiver &receiver,
                          std::atomic<bool> &cancel) {
  const auto send = [&](const Json &frame) { Send(input, frame.dump() + '\n'); };
  if (mode == "observation-long") {
    send(Observation(1, std::string(512, 'a')));
    Receipt(output, 1);
    StackLock lock;
    CheckLight(true);
  } else if (mode == "observations") {
    send(Observation(1));
    Receipt(output, 1);
    {
      StackLock lock;
      CheckLight(true);
      CheckValue<bool>(3, 57, 17, true);
    }
    send(Observation(2, "0002", 4, nullptr, 2350));
    Receipt(output, 2);
    {
      StackLock lock;
      CheckValue<std::int16_t>(4, 1026, 0, 2350);
      CheckValue<bool>(4, 57, 17, true);
    }
    send(Observation(3, "0001", 3, false, nullptr, false));
    Receipt(output, 3);
    {
      StackLock lock;
      CheckLight(false);
      CheckValue<bool>(3, 57, 17, false);
    }
    send(Observation(4, "0001", 3, nullptr));
    Receipt(output, 4);
    {
      StackLock lock;
      CheckLight(std::nullopt);
    }
    send(Observation(5, "0002", 4, nullptr, nullptr, false));
    Receipt(output, 5);
    {
      StackLock lock;
      CheckValue<std::int16_t>(4, 1026, 0, std::nullopt);
      CheckValue<bool>(4, 57, 17, false);
    }
    send(Observation(6, "0002", 4, nullptr, -1000));
    Receipt(output, 6);
    {
      StackLock lock;
      CheckValue<std::int16_t>(4, 1026, 0, -1000);
    }
    send(Observation(7, "0002", 4, nullptr, 4000));
    Receipt(output, 7);
  } else if (mode == "observation-refused") {
    send(Observation(1));
    Receipt(output, 1);
    send(Observation(2, "0002", 4, nullptr, 1000));
    Receipt(output, 2);
    const std::array<Json, 6> refused{Observation(3, "0003"),
                                      Observation(4, "0001", 4),
                                      Observation(5, "0001", 3, false, 50, false),
                                      Observation(6, "0002", 4, false, 50, false),
                                      Observation(7, "0002", 4, nullptr, 5000, false),
                                      Observation(8, "0002", 4, nullptr, -27316, false)};
    for (const auto &frame : refused) {
      send(frame);
      Receipt(output, std::stoull(frame["id"].get<std::string>()), false);
      StackLock lock;
      CheckLight(true);
      CheckValue<std::int16_t>(4, 1026, 0, 1000);
      CheckValue<bool>(3, 57, 17, true);
      CheckValue<bool>(4, 57, 17, true);
    }
  } else if (mode == "observation-replay") {
    send(Observation(1));
    Receipt(output, 1);
    send(Observation(1, "0001", 3, false));
    assert(Line(output).empty());
    return;
  } else if (mode == "observation-generation" || mode == "observation-malformed") {
    auto frame = Observation(1);
    if (mode == "observation-generation") {
      frame["generation"] = "02000000000000000000000000000000";
      send(frame);
    } else {
      auto duplicate = frame.dump();
      duplicate.insert(1, "\"id\":\"2\",");
      Send(input, duplicate + '\n');
    }
    assert(Line(output).empty());
    return;
  } else {
    const bool result = mode == "observation-result";
    const unsigned count = mode == "observation-credit" || mode == "observation-full" ? 64 : 1;
    if (result) assert(Line(output) == "{\"fixture\":\"request\"}\n");
    {
      StackLock lock;
      for (unsigned id = 1; id <= count; ++id)
        send(Observation(id, "0001", 3, count == 1 || id % 2 == 0));
      if (result)
        Send(input,
             "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"result\",\"generation\":\"" +
                 generation + "\",\"id\":\"1\",\"outcome\":\"completed\"}\n");
      Send(input,
           "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-probe\",\"generation\":\"" +
               generation + "\",\"id\":\"1\"}\n");
      const auto sampled = Json::parse(Line(output));
      assert(sampled["type"] == "clock-sample" && sampled["id"] == "1");
      if (result) assert(receiver.results == 1);
      if (mode == "observation-full") {
        send(Observation(65));
        AwaitClosed(*receiver.owner);
      }
      if (mode == "observation-cancel") {
        cancel.store(true);
        AwaitClosed(*receiver.owner);
      }
      if (mode == "observation-close") {
        Send(input, Control("close"));
        AwaitClosed(*receiver.owner);
      }
    }
    if (mode == "observation-full" || mode == "observation-cancel") {
      assert(Line(output).empty());
      return;
    }
    if (mode == "observation-close") {
      assert(Line(output) == Control("closed") && Line(output).empty());
      return;
    }
    for (unsigned id = 1; id <= count; ++id) Receipt(output, id);
  }
  Send(input, Control("close"));
  assert(Line(output) == Control("closed") && Line(output).empty());
}
}

int RunSdkProcessProbe(const std::string &root, std::string_view mode) {
  const std::array<std::string_view, 27> modes{"normal",
                                               "reopen",
                                               "missing-config",
                                               "bad-interface",
                                               "bad-open",
                                               "missing-open",
                                               "input-eof",
                                               "cancel",
                                               "attach-fail",
                                               "finish-fail",
                                               "result",
                                               "result-refuse",
                                               "pending",
                                               "generation",
                                               "output-lost",
                                               "credentials",
                                               "observations",
                                               "observation-refused",
                                               "observation-credit",
                                               "observation-result",
                                               "observation-replay",
                                               "observation-generation",
                                               "observation-malformed",
                                               "observation-close",
                                               "observation-full",
                                               "observation-cancel",
                                               "observation-long"};
  assert(std::find(modes.begin(), modes.end(), mode) != modes.end());
  std::signal(SIGPIPE, SIG_IGN);
  const auto previous = std::filesystem::current_path();
  const auto configuration = root + "/configuration";
  if (mode == "missing-config") assert(unlink(configuration.c_str()) == 0);
  if (mode == "credentials") assert(unlink((root + "/key").c_str()) == 0);
  if (mode == "bad-interface" || mode == "reopen" || mode == "observation-long") {
    Json value;
    std::ifstream(configuration) >> value;
    if (mode == "bad-interface") value["interface"] = "missing0";
    else if (mode == "observation-long") value["devices"][0]["thing_id"] = std::string(512, 'a');
    else {
      assert(chip::Platform::MemoryInit() == CHIP_NO_ERROR);
      std::unique_ptr<BridgeBootstrap> loaded;
      assert(LoadBootstrap(configuration, loaded) == BootstrapLoad::Loaded);
      std::unique_ptr<BridgeStorage> store;
      assert(BridgeStorage::Open(loaded->configuration->store_path, StorageMode::CreateNew,
                                 loaded->configuration->identity, store) == CHIP_NO_ERROR);
      for (const auto &device : loaded->configuration->devices) {
        BridgeEndpoint endpoint;
        assert(store->Allocate(device.thing_id, device.device_type, endpoint) == CHIP_NO_ERROR);
      }
      store.reset();
      loaded.reset();
      chip::Platform::MemoryShutdown();
      value["store_mode"] = "reopen";
    }
    std::ofstream(configuration) << value.dump();
  }
  Receiver receiver(mode);
  SdkBridgeProcessDriver driver(configuration, receiver);
  assert(!driver.Ready({{1}, 1}));
  assert(std::filesystem::current_path() == previous);
  int input[2], output[2];
  assert(pipe(input) == 0 && pipe(output) == 0);
  Clock clock;
  std::atomic<bool> cancel{false};
  std::atomic<bool> returned{false};
  std::thread consumer([&] {
    if (mode == "missing-open") {
      assert(Line(output[0]).empty());
    } else {
      Send(input[1], mode == "bad-open" ? "{}\n" : Control("open"));
      if (mode == "bad-open" || mode == "missing-config" || mode == "credentials" ||
          mode == "bad-interface" || mode == "attach-fail")
        assert(Line(output[0]).empty());
      else {
        const auto ready = Json::parse(Line(output[0]));
        assert(ready.size() == 6 && ready["type"] == "ready" && ready["generation"] == generation);
        assert(ready["sdk_revision"] == "250a9e6c50ee2068107f3c4808b680f5f2925415");
        assert(ready["model_sha256"] ==
               "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671");
        if (mode.substr(0, 11) == "observation") {
          ExerciseObservations(mode, input[1], output[0], receiver, cancel);
        } else {
          if (mode == "result" || mode == "result-refuse" || mode == "pending") {
            assert(Line(output[0]) == "{\"fixture\":\"request\"}\n");
            if (mode != "pending")
              Send(input[1],
                   "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"result\",\"generation\":\"" +
                       generation + "\",\"id\":\"1\",\"outcome\":\"completed\"}\n");
          }
          if (mode == "input-eof") {
            close(input[1]);
            input[1] = -1;
          } else if (mode == "cancel") cancel.store(true);
          else if (mode == "generation")
            Send(input[1],
                 "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"close\",\"generation\":"
                 "\"02000000000000000000000000000000\"}\n");
          else if (mode == "output-lost") {
            close(output[0]);
            output[0] = -1;
            // Keep input alive so output loss is the sole shutdown trigger.
            const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
            while (!returned.load() && std::chrono::steady_clock::now() < deadline)
              std::this_thread::sleep_for(std::chrono::milliseconds(1));
            assert(returned.load());
          } else if (mode != "result-refuse") {
            Send(input[1],
                 "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-probe\",\"generation\":"
                 "\"" +
                     generation + "\",\"id\":\"1\"}\n");
            const auto sample = Json::parse(Line(output[0]));
            assert(sample.size() == 6 && sample["type"] == "clock-sample" && sample["id"] == "1" &&
                   sample["generation"] == generation);
            Send(input[1], Control("close"));
            assert(Line(output[0]) == Control("closed"));
          }
          if (output[0] >= 0) assert(Line(output[0]).empty());
        }
      }
    }
    if (input[1] >= 0) close(input[1]);
    if (output[0] >= 0) close(output[0]);
  });
  const auto status = RunBridgeProcess(input[0], output[1], mode == "missing-open" ? 50 : 5000,
                                       clock, driver, cancel);
  returned.store(true);
  close(input[0]);
  close(output[1]);
  consumer.join();
  const auto expected = mode == "bad-open" || mode == "input-eof" || mode == "generation" ||
          mode == "result-refuse" || mode == "observation-replay" ||
          mode == "observation-generation" || mode == "observation-malformed" ||
          mode == "observation-full"
      ? Exit::Input
      : mode == "missing-open" || mode == "missing-config" || mode == "credentials" ||
          mode == "bad-interface" || mode == "attach-fail"
      ? Exit::Startup
      : mode == "cancel" || mode == "observation-cancel" ? Exit::Cancelled
      : mode == "output-lost"                            ? Exit::Output
                                                         : Exit::Closed;
  assert(status == expected);
  const bool never_attached = mode == "bad-open" || mode == "missing-open" ||
      mode == "missing-config" || mode == "credentials" || mode == "bad-interface";
  assert(receiver.attached == (never_attached ? 0 : 1) && receiver.finished == receiver.attached);
  assert(receiver.results ==
         (mode == "result" || mode == "result-refuse" || mode == "observation-result" ? 1 : 0));
  assert(!driver.Ready({{1}, 1}) && !driver.Stop());
  assert(std::filesystem::current_path() == previous);
  if (!never_attached) {
    std::uint32_t pin = 0;
    assert(chip::DeviceLayer::GetCommissionableDataProvider()->GetSetupPasscode(pin) ==
           CHIP_ERROR_INCORRECT_STATE);
    std::unique_ptr<BridgeStorage> reopened;
    BridgeIdentity identity{std::string("\0\xff", 2),
                            "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671",
                            0xFFF1, 0x8001};
    assert(BridgeStorage::Open(root + "/store", StorageMode::OpenExisting, identity, reopened) ==
           CHIP_NO_ERROR);
  }
  std::filesystem::remove_all(root);
  std::cout << "owned SDK process driver and pipes passed\n";
  return 0;
}
} // namespace wotex::matter::testing
