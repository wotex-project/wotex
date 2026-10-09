#include "sdk_bridge_wait_test.hpp"

#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_handoff_owner.hpp"
#include "wotex_matter/bridge_input.hpp"

#include <app/MessageDef/AttributeReportIBs.h>
#include <platform/CHIPDeviceLayer.h>
#include <chrono>
#include <future>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>

namespace wotex::matter {

struct BridgeHandoffOwnerTestAccess {
  static unsigned Waiters(BridgeHandoffOwner &owner) {
    std::lock_guard<std::mutex> lock(owner.mutex_);
    return owner.waiting_;
  }
};

namespace testing {
namespace {

using Status = chip::Protocols::InteractionModel::Status;
using Handoff = BridgeConsumerHandoff;

void Require(bool condition, const char *stage) {
  if (!condition) throw std::runtime_error(stage);
}

class SteadyClock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
};

class InputSink final : public BridgeResultSink {
 public:
  bool Ready(const Handoff::Ticket &) noexcept override {
    ++ready;
    return true;
  }
  void Closed() noexcept override { ++closed; }
  std::atomic<unsigned> ready{0}, closed{0};
};

std::string Frame(const Handoff::Ticket &ticket, const char *outcome) {
  const char digits[] = "0123456789abcdef";
  std::string generation;
  for (auto byte : ticket.generation) {
    generation += digits[byte >> 4];
    generation += digits[byte & 15];
  }
  return "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"result\",\"generation\":\"" +
      generation + "\",\"id\":\"" + std::to_string(ticket.id) + "\",\"outcome\":\"" + outcome +
      "\"}\n";
}

class ReceiverProbe final : public WaitProbe {
 public:
  ReceiverProbe(Handoff &handoff, chip::app::DataModel::Provider &delegate, WaitInput input)
      : owner_(handoff, clock_), delegate_(delegate), input_mode_(input) {}

  chip::app::DataModel::ActionReturnStatus Read(
      BridgeRequestMetadata metadata, chip::app::AttributeValueEncoder &encoder) override {
    last_ = metadata;
    Handoff::Ticket ticket;
    owner_.With([&](Handoff &custody, std::uint64_t now) {
      Require(custody.Reserve(now, now + Handoff::kMaximumDurationMs, ticket) ==
                  Handoff::Admission::Reserved,
              "SDK read request not admitted");
    });
    admitted_.set_value(ticket);
    Handoff::Outcome result = Handoff::Outcome::Unknown;
    Require(owner_.Wait(ticket, result) == Handoff::Consume::Completed,
            "SDK read context not consumed");
    if (result == Handoff::Outcome::Denied) return Status::UnsupportedAccess;
    if (result == Handoff::Outcome::TimedOut) return Status::Timeout;
    if (result != Handoff::Outcome::Completed) return Status::Failure;
    chip::app::DataModel::ReadAttributeRequest request(
        chip::app::ConcreteAttributePath(metadata.endpoint, metadata.cluster, metadata.member),
        metadata.principal);
    request.readFlags.Set(chip::app::DataModel::ReadFlags::kFabricFiltered,
                          metadata.fabric_filtered);
    // Explicit fixture completion reads an already approved value. It makes
    // no consumer-policy, authenticated admission or physical-effect claim.
    return delegate_.ReadAttribute(request, encoder);
  }

  chip::app::DataModel::ActionReturnStatus Write(BridgeRequestMetadata,
                                                 chip::app::AttributeValueDecoder &) override {
    return Status::UnsupportedWrite;
  }
  std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(
      BridgeRequestMetadata, chip::TLV::TLVReader &, chip::app::CommandHandler *) override {
    return chip::app::DataModel::ActionReturnStatus(Status::UnsupportedCommand);
  }
  void ListNotification(const chip::app::ConcreteAttributePath &,
                        chip::app::DataModel::ListWriteOperation, chip::FabricIndex) override {}

  void Prepare(SdkBridgeServerBinding &server, SdkBridgeProviderBinding &provider) override {
    provider_ = &provider;
    children_ = std::make_unique<SdkBridgeEndpointBinding>(server);
    Require(children_->Init({}) == CHIP_NO_ERROR, "SDK waiting child init");
    BridgeEndpoint child;
    Require(
        children_->Add({"waiting-light", BridgedDeviceType::OnOffLight, "Waiting light", {}, {}},
                       child) == CHIP_NO_ERROR,
        "SDK waiting child added");
    Require(child.endpoint == 3 &&
                children_->Observe("waiting-light", 3, {true, false, {}}) == CHIP_NO_ERROR,
            "SDK waiting approved state");
  }

  void DuringLoop() override {
    InputSink sink;
    BridgeResultInput input(owner_, {1}, sink);
    std::atomic<bool> stop{false};
    BridgeResultInput::State terminal = BridgeResultInput::State::Open;
    int descriptors[2]{-1, -1};
    int original_flags = 0;
    std::thread reader;
    if (input_mode_ != WaitInput::Direct) {
      Require(pipe(descriptors) == 0, "SDK result pipe create");
      original_flags = fcntl(descriptors[0], F_GETFL);
      Require(original_flags >= 0, "SDK result pipe flags");
      reader = std::thread([&] { terminal = input.Run(descriptors[0], stop); });
    }
    // Join even on an assertion failure, before borrowed input/custody leave
    // scope. The caller closes descriptors only after the reader returns.
    struct ReaderCleanup {
      std::thread &reader;
      std::atomic<bool> &stop;
      int *descriptors;
      ~ReaderCleanup() {
        stop = true;
        if (reader.joinable()) reader.join();
        for (unsigned i = 0; i < 2; ++i)
          if (descriptors[i] >= 0) close(descriptors[i]);
      }
    } cleanup{reader, stop, descriptors};
    const auto send = [&](const std::string &bytes) {
      for (char byte : bytes)
        Require(write(descriptors[1], &byte, 1) == 1, "SDK fragmented result write");
    };
    for (unsigned phase = 0; phase < 4; ++phase) {
      admitted_ = std::promise<Handoff::Ticket>();
      auto admitted = admitted_.get_future();
      finished_ = std::promise<Status>();
      auto finished = finished_.get_future();
      Require(chip::DeviceLayer::PlatformMgr().ScheduleWork(
                  [](intptr_t context) { reinterpret_cast<ReceiverProbe *>(context)->Read(); },
                  reinterpret_cast<intptr_t>(this)) == CHIP_NO_ERROR,
              "waiting read scheduled");
      Require(admitted.wait_for(std::chrono::seconds(2)) == std::future_status::ready,
              "SDK read admission deadline");
      const auto ticket = admitted.get();
      if (phase != 2) {
        // Observe the actual condition-variable wait, rather than a flag set
        // before the SDK callback releases the custody mutex.
        while (BridgeHandoffOwnerTestAccess::Waiters(owner_) == 0 &&
               finished.wait_for(std::chrono::milliseconds(0)) != std::future_status::ready)
          std::this_thread::yield();
        Require(BridgeHandoffOwnerTestAccess::Waiters(owner_) != 0,
                "SDK waiter expired before input resolution");
        Require(last_.principal.fabricIndex == 2 && last_.principal.subject == 42,
                "waiting receiver principal not copied");
        if (input_mode_ != WaitInput::Direct) {
          if (phase != 3) send(Frame(ticket, phase == 0 ? "completed" : "denied"));
          else if (input_mode_ == WaitInput::Cancelled) stop = true;
          else {
            if (input_mode_ == WaitInput::Malformed) send("{}\n");
            if (input_mode_ == WaitInput::Partial) send("{");
            Require(close(descriptors[1]) == 0, "SDK result pipe writer close");
            descriptors[1] = -1;
          }
        } else if (phase == 3) owner_.Close();
        else
          Require(owner_.Resolve(ticket,
                                 phase == 0 ? Handoff::Outcome::Completed
                                            : Handoff::Outcome::Denied) == Handoff::Reply::Stored,
                  "input reader failed while SDK stack lock held");
      }
      Require(finished.wait_for(std::chrono::seconds(2)) == std::future_status::ready,
              "waiting read event-loop deadline");
      const auto expected = phase == 0 ? Status::Success
          : phase == 1                 ? Status::UnsupportedAccess
          : phase == 2                 ? Status::Timeout
                                       : Status::Failure;
      Require(finished.get() == expected, "waiting read outcome changed");
      if (phase == 2 && input_mode_ != WaitInput::Direct)
        send(Frame(ticket, "completed")); // A timed-out, consumed identity cannot revive.
      owner_.With([](Handoff &custody, std::uint64_t) {
        Require(custody.pending() == 0, "SDK waiting credit leaked");
      });
    }
    if (input_mode_ == WaitInput::Direct)
      std::cout << "SDK read waiting, input resolution, timeout and closure passed\n" << std::flush;
    else {
      reader.join();
      const auto expected = input_mode_ == WaitInput::Ended ? BridgeResultInput::State::Ended
          : input_mode_ == WaitInput::Malformed             ? BridgeResultInput::State::Malformed
          : input_mode_ == WaitInput::Partial               ? BridgeResultInput::State::Partial
                                                            : BridgeResultInput::State::Cancelled;
      Require(terminal == expected && sink.ready == 2 && sink.closed == 1,
              "SDK result pipe terminal custody");
      Require(fcntl(descriptors[0], F_GETFL) == original_flags, "SDK result pipe flags restore");
      std::cout << "SDK bounded result pipe, timeout and "
                << (input_mode_ == WaitInput::Ended           ? "EOF"
                        : input_mode_ == WaitInput::Malformed ? "malformed"
                        : input_mode_ == WaitInput::Partial   ? "partial"
                                                              : "cancellation")
                << " wake passed\n"
                << std::flush;
    }
  }

  void Finish() override { children_->Finish(); }

 private:
  void Read() {
    // Runs under the real SDK event-loop stack lock. The input/main thread
    // resolves custody independently while this synchronous callback waits.
    std::uint8_t bytes[512];
    chip::TLV::TLVWriter writer;
    writer.Init(bytes);
    chip::app::AttributeReportIBs::Builder reports;
    Require(reports.Init(&writer) == CHIP_NO_ERROR, "waiting reports init");
    chip::Access::SubjectDescriptor principal;
    principal.fabricIndex = 2;
    principal.authMode = chip::Access::AuthMode::kCase;
    principal.subject = 42;
    const chip::app::ConcreteAttributePath path(3, 6, 0);
    chip::app::AttributeValueEncoder encoder(reports, principal, path, 0);
    chip::app::DataModel::ReadAttributeRequest request(path, principal);
    const auto result = provider_->ReadAttribute(request, encoder);
    finished_.set_value(result.GetStatusCode().GetStatus());
  }

  SteadyClock clock_;
  BridgeHandoffOwner owner_;
  chip::app::DataModel::Provider &delegate_;
  SdkBridgeProviderBinding *provider_{nullptr};
  std::unique_ptr<SdkBridgeEndpointBinding> children_;
  std::promise<Handoff::Ticket> admitted_;
  std::promise<Status> finished_;
  BridgeRequestMetadata last_;
  const WaitInput input_mode_;
};

} // namespace

std::unique_ptr<WaitProbe> PrepareWait(BridgeConsumerHandoff &handoff,
                                       chip::app::DataModel::Provider &delegate, WaitInput input) {
  return std::make_unique<ReceiverProbe>(handoff, delegate, input);
}

} // namespace testing
} // namespace wotex::matter
