#include "sdk_bridge_process_test.hpp"
#include "wotex_matter/bridge_sdk_process.hpp"

#include <app/server/Server.h>
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
    if (mode == "result" || mode == "result-refuse" || mode == "pending") {
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
}

int RunSdkProcessProbe(const std::string &root, std::string_view mode) {
  const std::array<std::string_view, 16> modes{
      "normal",    "reopen",     "missing-config", "bad-interface", "bad-open", "missing-open",
      "input-eof", "cancel",     "attach-fail",    "finish-fail",   "result",   "result-refuse",
      "pending",   "generation", "output-lost",    "credentials"};
  assert(std::find(modes.begin(), modes.end(), mode) != modes.end());
  std::signal(SIGPIPE, SIG_IGN);
  const auto previous = std::filesystem::current_path();
  const auto configuration = root + "/configuration";
  if (mode == "missing-config") assert(unlink(configuration.c_str()) == 0);
  if (mode == "credentials") assert(unlink((root + "/key").c_str()) == 0);
  if (mode == "bad-interface" || mode == "reopen") {
    Json value;
    std::ifstream(configuration) >> value;
    if (mode == "bad-interface") value["interface"] = "missing0";
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
               "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-probe\",\"generation\":\"" +
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
          mode == "result-refuse"
      ? Exit::Input
      : mode == "missing-open" || mode == "missing-config" || mode == "credentials" ||
          mode == "bad-interface" || mode == "attach-fail"
      ? Exit::Startup
      : mode == "cancel"      ? Exit::Cancelled
      : mode == "output-lost" ? Exit::Output
                              : Exit::Closed;
  assert(status == expected);
  const bool never_attached = mode == "bad-open" || mode == "missing-open" ||
      mode == "missing-config" || mode == "credentials" || mode == "bad-interface";
  assert(receiver.attached == (never_attached ? 0 : 1) && receiver.finished == receiver.attached);
  assert(receiver.results == (mode == "result" || mode == "result-refuse" ? 1 : 0));
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
