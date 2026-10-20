#include "wotex_matter/bridge_sdk_receiver.hpp"
#include "wotex_matter/bridge_guard.hpp"
#include "wotex_matter/bridge_request_frame.hpp"

#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <lib/core/TLVWriter.h>
#include <chrono>
#include <cstdlib>
#include <limits>
#include <thread>

namespace wotex::matter {
namespace {
using Handoff = BridgeConsumerHandoff;
using Action = chip::app::DataModel::ActionReturnStatus;
using Status = chip::Protocols::InteractionModel::Status;
Action Error(CHIP_ERROR error) {
  if (error == CHIP_ERROR_ACCESS_DENIED) return Status::UnsupportedAccess;
  if (error == CHIP_ERROR_ACCESS_RESTRICTED_BY_ARL) return Status::AccessRestricted;
  if (error == CHIP_ERROR_BUSY || error == CHIP_ERROR_NO_MEMORY) return Status::ResourceExhausted;
  return error;
}
CHIP_ERROR Reserve(Handoff &custody, std::uint64_t now, Handoff::Ticket &ticket) {
  if (now > std::numeric_limits<std::uint64_t>::max() - Handoff::kMaximumDurationMs)
    return CHIP_ERROR_INVALID_ARGUMENT;
  switch (custody.Reserve(now, now + Handoff::kMaximumDurationMs, ticket)) {
  case Handoff::Admission::Reserved:
    return CHIP_NO_ERROR;
  case Handoff::Admission::Busy:
    return CHIP_ERROR_BUSY;
  default:
    return CHIP_ERROR_INCORRECT_STATE;
  }
}
Action Outcome(Handoff::Outcome result) {
  if (result == Handoff::Outcome::Completed) return Status::Success;
  if (result == Handoff::Outcome::Denied) return Status::UnsupportedAccess;
  if (result == Handoff::Outcome::TimedOut) return Status::Timeout;
  return Status::Failure;
}
Action ApplyWrite(const BridgeAttributeWrite &write) {
  const auto &metadata = write.request;
  std::uint8_t bytes[16];
  chip::TLV::TLVWriter writer;
  writer.Init(bytes);
  CHIP_ERROR encoded;
  if (const auto *value = std::get_if<std::uint16_t>(&write.value))
    encoded = writer.Put(chip::TLV::AnonymousTag(), *value);
  else {
    const auto &nullable = std::get<std::optional<std::uint8_t>>(write.value);
    encoded = nullable ? writer.Put(chip::TLV::AnonymousTag(), *nullable)
                       : writer.PutNull(chip::TLV::AnonymousTag());
  }
  if (encoded != CHIP_NO_ERROR || writer.Finalize() != CHIP_NO_ERROR) return Status::Failure;
  chip::TLV::TLVReader reader;
  reader.Init(bytes, writer.GetLengthWritten());
  if (reader.Next() != CHIP_NO_ERROR) return Status::Failure;
  chip::app::ConcreteDataAttributePath path(metadata.endpoint, metadata.cluster, metadata.member);
  path.mExpanded = metadata.expanded;
  if (metadata.data_version) path.mDataVersion.SetValue(*metadata.data_version);
  chip::app::DataModel::WriteAttributeRequest request(path, metadata.principal);
  request.writeFlags.Set(chip::app::DataModel::WriteFlags::kTimed, metadata.timed);
  chip::app::AttributeValueDecoder decoder(reader, metadata.principal);
  return chip::app::CodegenDataModelProvider::Instance().WriteAttribute(request, decoder);
}
}

class SdkBridgeConsumerReceiver::Impl final {
 public:
  explicit Impl(BridgeInvokeReply &renderer) : renderer_(renderer) {}
  ~Impl() {
    if (worker_.joinable() || scopes_ || contexts_) std::_Exit(70);
  }
  CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, Handoff &shared, BridgeHandoffOwner &custody,
                    BridgeOutputOwner &output, SdkBridgeObservationOwner &observations) {
    if (used_) return CHIP_ERROR_INCORRECT_STATE;
    used_ = true;
    custody_ = &custody;
    output_ = &output;
    observations_ = &observations;
    endpoints_ = runtime.endpoints();
    if (!endpoints_ || !runtime.provider() || shared.closed() || shared.pending() != 0)
      return CHIP_ERROR_INCORRECT_STATE;
    scopes_ = std::make_unique<SdkBridgeFabricScopes>(chip::Server::GetInstance().GetFabricTable());
    ReturnErrorOnFailure(scopes_->Init());
    auto &provider = chip::app::CodegenDataModelProvider::Instance();
    attributes_ = std::make_unique<SdkBridgeAttributeGuard>(*scopes_, provider);
    commands_ = std::make_unique<SdkBridgeInvokeGuard>(*scopes_, provider);
    contexts_ = std::make_unique<SdkBridgeInvokeContexts>(shared, *commands_);
    active_.store(true);
    worker_ = std::thread([this] { Run(); });
    return CHIP_NO_ERROR;
  }
  void Fail() noexcept try { output_->Close(); } catch (...) {
    std::_Exit(70);
  }
  bool Retire() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      active_.store(false);
      changed_.notify_all();
    }
    if (worker_.joinable()) worker_.join();
    retired_ = true;
    return true;
  }
  CHIP_ERROR Finish() {
    if (!used_ || finished_ || !retired_) return CHIP_ERROR_INCORRECT_STATE;
    finished_ = true;
    CHIP_ERROR status = CHIP_NO_ERROR;
    if (contexts_) {
      status = custody_->With([&](auto &, auto now) { return contexts_->Finish(now); });
      contexts_.reset();
    }
    commands_.reset();
    attributes_.reset();
    if (scopes_) scopes_->Finish();
    scopes_.reset();
    const bool drained = custody_->With(
        [](auto &shared, auto) { return shared.closed() && shared.pending() == 0; });
    tickets_ = {};
    pending_.store(0);
    return drained ? status : CHIP_ERROR_INCORRECT_STATE;
  }
  Action Wait(const Handoff::Ticket &ticket) {
    Handoff::Outcome outcome;
    if (custody_->Wait(ticket, outcome, *observations_) != Handoff::Consume::Completed) {
      Fail();
      return Status::Failure;
    }
    return Outcome(outcome);
  }
  bool Current(const BridgeAttributeScope &scope, const std::string &thing) {
    if (!active_.load()) return false;
    std::string live;
    return endpoints_->ResolveThing(scope.request.endpoint, live) == CHIP_NO_ERROR && live == thing;
  }
  Action Read(BridgeRequestMetadata request, chip::app::AttributeValueEncoder &encoder) {
    if (!active_.load()) return Status::Failure;
    BridgeAttributeScope scope;
    const auto guarded = attributes_->Capture(request, scope);
    if (guarded != CHIP_NO_ERROR) return Error(guarded);
    std::string thing;
    const auto resolved = endpoints_->ResolveThing(request.endpoint, thing);
    if (resolved != CHIP_NO_ERROR) return Error(resolved);
    Handoff::Ticket ticket;
    bool delivered = false;
    const auto admitted = custody_->With([&](auto &shared, auto now) {
      const auto status = Reserve(shared, now, ticket);
      if (status != CHIP_NO_ERROR) return status;
      std::string frame;
      delivered = EncodeBridgeReadFrame(ticket, request, scope.fabric, now + 500, thing, frame) ==
              BridgeRequestEncode::Encoded &&
          output_->Push(BridgeOutputOwner::Kind::Request, frame) ==
              BridgeOutputOwner::Admission::Accepted;
      return CHIP_NO_ERROR;
    });
    if (admitted != CHIP_NO_ERROR) return Error(admitted);
    if (!delivered) Fail();
    const auto outcome = Wait(ticket);
    if (!outcome.IsSuccess()) return outcome;
    const auto current = attributes_->Validate(scope);
    if (current != CHIP_NO_ERROR) return Error(current);
    if (!Current(scope, thing)) return Status::Failure;
    chip::app::ConcreteAttributePath path(request.endpoint, request.cluster, request.member);
    path.mExpanded = request.expanded;
    chip::app::DataModel::ReadAttributeRequest native(path, request.principal);
    native.readFlags.Set(chip::app::DataModel::ReadFlags::kFabricFiltered, request.fabric_filtered);
    native.readFlags.Set(chip::app::DataModel::ReadFlags::kAllowsLargePayload,
                         request.allows_large_payload);
    return chip::app::CodegenDataModelProvider::Instance().ReadAttribute(native, encoder);
  }
  Action Write(BridgeRequestMetadata request, chip::app::AttributeValueDecoder &decoder) {
    if (!active_.load()) return Status::Failure;
    BridgeAttributeScope scope;
    const auto guarded = attributes_->Capture(request, scope);
    if (guarded != CHIP_NO_ERROR) return Error(guarded);
    std::string thing;
    const auto resolved = endpoints_->ResolveThing(request.endpoint, thing);
    if (resolved != CHIP_NO_ERROR) return Error(resolved);
    BridgeAttributeWrite write;
    bool delivered = false;
    const auto admitted = custody_->With([&](auto &shared, auto now) {
      if (now > std::numeric_limits<std::uint64_t>::max() - 500) return CHIP_ERROR_INVALID_ARGUMENT;
      const auto status = StartBridgeWrite(shared, request, decoder, now, now + 500, write);
      if (status != CHIP_NO_ERROR) return status;
      std::string frame;
      delivered = EncodeBridgeWriteFrame(write, scope.fabric, thing, frame) ==
              BridgeRequestEncode::Encoded &&
          output_->Push(BridgeOutputOwner::Kind::Request, frame) ==
              BridgeOutputOwner::Admission::Accepted;
      return CHIP_NO_ERROR;
    });
    if (admitted != CHIP_NO_ERROR) return Error(admitted);
    if (!delivered) Fail();
    const auto outcome = Wait(write.ticket);
    if (!outcome.IsSuccess()) return outcome;
    const auto current = attributes_->Validate(scope);
    if (current != CHIP_NO_ERROR) return Error(current);
    if (!Current(scope, thing)) return Status::Failure;
    return ApplyWrite(write);
  }
  std::optional<Action> Invoke(BridgeRequestMetadata request, chip::TLV::TLVReader &arguments,
                               chip::app::CommandHandler *handler) {
    if (!active_.load()) return Action(Status::Failure);
    if (!handler || request.operation != BridgeRequestMetadata::Operation::Invoke ||
        request.expanded || request.fabric_filtered || request.allows_large_payload ||
        request.data_version ||
        request.list_operation != chip::app::ConcreteDataAttributePath::ListOperation::NotList ||
        request.list_index != 0)
      return Error(CHIP_ERROR_INVALID_ARGUMENT);
    std::string thing;
    const auto resolved = endpoints_->ResolveThing(request.endpoint, thing);
    if (resolved != CHIP_NO_ERROR) return Error(resolved);
    std::size_t slot = 0;
    while (slot < tickets_.size() && tickets_[slot].id != 0) ++slot;
    if (slot == tickets_.size()) return Action(Status::ResourceExhausted);
    chip::app::DataModel::InvokeRequest native(
        chip::app::ConcreteCommandPath(request.endpoint, request.cluster, request.member),
        request.principal);
    native.invokeFlags.Set(chip::app::DataModel::InvokeFlags::kTimed, request.timed);
    Handoff::Ticket ticket;
    bool delivered = false;
    const auto admitted = custody_->With([&](auto &, auto now) {
      if (now > std::numeric_limits<std::uint64_t>::max() - 500) return CHIP_ERROR_INVALID_ARGUMENT;
      const auto status = contexts_->Start(native, arguments, *handler, now, now + 500, ticket);
      if (status != CHIP_NO_ERROR) return status;
      tickets_[slot] = ticket;
      pending_.fetch_add(1);
      BridgeInvocation invocation;
      BridgeFabricScope fabric;
      std::string frame;
      delivered = contexts_->Request(ticket, invocation, fabric) == CHIP_NO_ERROR &&
          EncodeBridgeInvokeFrame(invocation, fabric, thing, frame) ==
              BridgeRequestEncode::Encoded &&
          output_->Push(BridgeOutputOwner::Kind::Request, frame) ==
              BridgeOutputOwner::Admission::Accepted;
      return CHIP_NO_ERROR;
    });
    if (admitted != CHIP_NO_ERROR) return Error(admitted);
    if (!delivered) Fail();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      changed_.notify_one();
    }
    return std::nullopt; // This owner retained the handler; no automatic Success.
  }
  bool ResultReady() noexcept try {
    if (!active_.load()) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    changed_.notify_one();
    return true;
  } catch (...) {
    return false;
  }
  void Run() noexcept try {
    while (active_.load()) {
      {
        std::unique_lock<std::mutex> lock(mutex_);
        changed_.wait(lock, [&] { return !active_.load() || pending_.load() != 0; });
      }
      if (!active_.load()) return;
      if (chip::DeviceLayer::PlatformMgr().TryLockChipStack()) {
        bool failed = false;
        try {
          if (active_.load()) {
            for (auto &ticket : tickets_) {
              if (ticket.id == 0) continue;
              const auto status = contexts_->Respond(*custody_, ticket, renderer_);
              if (status == CHIP_ERROR_BUSY) continue;
              if (status != CHIP_NO_ERROR) {
                failed = true;
                break;
              }
              ticket = {};
              pending_.fetch_sub(1);
            }
          }
        } catch (...) {
          failed = true;
        }
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        if (failed) {
          Fail();
          return;
        }
      }
      std::unique_lock<std::mutex> lock(mutex_);
      changed_.wait_for(lock, std::chrono::milliseconds(5));
    }
  } catch (...) {
    Fail();
  }

  BridgeInvokeReply &renderer_;
  BridgeHandoffOwner *custody_{nullptr};
  BridgeOutputOwner *output_{nullptr};
  SdkBridgeObservationOwner *observations_{nullptr};
  SdkBridgeEndpointBinding *endpoints_{nullptr};
  std::unique_ptr<SdkBridgeFabricScopes> scopes_;
  std::unique_ptr<SdkBridgeAttributeGuard> attributes_;
  std::unique_ptr<SdkBridgeInvokeGuard> commands_;
  std::unique_ptr<SdkBridgeInvokeContexts> contexts_;
  std::array<Handoff::Ticket, Handoff::kCapacity> tickets_{};
  std::atomic<bool> active_{false};
  std::atomic<unsigned> pending_{0};
  bool used_{false}, retired_{false}, finished_{false};
  std::mutex mutex_;
  std::condition_variable changed_;
  std::thread worker_;
};

SdkBridgeConsumerReceiver::SdkBridgeConsumerReceiver(BridgeInvokeReply &renderer)
    : impl_(std::make_unique<Impl>(renderer)) {}
SdkBridgeConsumerReceiver::~SdkBridgeConsumerReceiver() = default;
CHIP_ERROR SdkBridgeConsumerReceiver::Attach(SdkBridgeBootstrap &runtime, Handoff &shared,
                                             BridgeHandoffOwner &custody, BridgeOutputOwner &output,
                                             SdkBridgeObservationOwner &observations) noexcept try {
  return impl_->Attach(runtime, shared, custody, output, observations);
} catch (...) {
  return CHIP_ERROR_NO_MEMORY;
}
bool SdkBridgeConsumerReceiver::ResultReady(const Handoff::Ticket &) noexcept {
  return impl_->ResultReady();
}
bool SdkBridgeConsumerReceiver::Retire() noexcept try { return impl_->Retire(); } catch (...) {
  return false;
}
CHIP_ERROR SdkBridgeConsumerReceiver::Finish() noexcept try {
  return impl_->Finish();
} catch (...) {
  return CHIP_ERROR_INCORRECT_STATE;
}
Action SdkBridgeConsumerReceiver::Read(BridgeRequestMetadata request,
                                       chip::app::AttributeValueEncoder &encoder) try {
  return impl_->Read(request, encoder);
} catch (...) {
  impl_->Fail();
  return Status::Failure;
}
Action SdkBridgeConsumerReceiver::Write(BridgeRequestMetadata request,
                                        chip::app::AttributeValueDecoder &decoder) try {
  return impl_->Write(request, decoder);
} catch (...) {
  impl_->Fail();
  return Status::Failure;
}
std::optional<Action> SdkBridgeConsumerReceiver::Invoke(BridgeRequestMetadata request,
                                                        chip::TLV::TLVReader &arguments,
                                                        chip::app::CommandHandler *handler) try {
  return impl_->Invoke(request, arguments, handler);
} catch (...) {
  impl_->Fail();
  return Action(Status::Failure);
}
void SdkBridgeConsumerReceiver::ListNotification(const chip::app::ConcreteAttributePath &,
                                                 chip::app::DataModel::ListWriteOperation,
                                                 chip::FabricIndex) {}
} // namespace wotex::matter
