#include "wotex_matter/bridge_requests.hpp"
#include "wotex_matter/bridge_server.hpp"

#include <lib/core/TLVWriter.h>

#include <array>
#include <cstdlib>
#include <new>

namespace wotex::matter {
namespace {

using chip::app::DataModel::InvokeFlags;
using chip::app::DataModel::ReadFlags;
using chip::app::DataModel::WriteFlags;
using Status = chip::Protocols::InteractionModel::Status;

bool SamePrincipal(const chip::Access::SubjectDescriptor &left,
                   const chip::Access::SubjectDescriptor &right) {
  return left.fabricIndex == right.fabricIndex && left.authMode == right.authMode &&
      left.subject == right.subject && left.cats.values == right.cats.values &&
      left.isCommissioning == right.isCommissioning;
}

CHIP_ERROR CopyArguments(chip::TLV::TLVReader arguments, std::vector<std::uint8_t> &result) {
  using Owner = SdkBridgeInvokeContexts;
  if (arguments.GetType() != chip::TLV::kTLVType_Structure) return CHIP_ERROR_INVALID_ARGUMENT;
  // Bound the scan before asking the SDK writer to copy a nested container.
  // A copy of the reader preserves the SDK caller's current position.
  auto scan = arguments;
  const auto start = scan.GetLengthRead();
  std::array<chip::TLV::TLVType, Owner::kMaximumArgumentDepth> containers{};
  std::size_t depth = 1;
  std::size_t nodes = 1;
  CHIP_ERROR error = scan.EnterContainer(containers[0]);
  if (error != CHIP_NO_ERROR) return error;
  while (depth != 0) {
    error = scan.Next();
    if (error == CHIP_END_OF_TLV) {
      error = scan.ExitContainer(containers[--depth]);
      if (error != CHIP_NO_ERROR) return error;
    } else if (error != CHIP_NO_ERROR) {
      return error;
    } else {
      if (++nodes > Owner::kMaximumArgumentNodes ||
          scan.GetLength() > Owner::kMaximumArgumentsBytes)
        return CHIP_ERROR_BUFFER_TOO_SMALL;
      if (scan.GetType() == chip::TLV::kTLVType_Structure ||
          scan.GetType() == chip::TLV::kTLVType_Array ||
          scan.GetType() == chip::TLV::kTLVType_List) {
        if (depth == containers.size()) return CHIP_ERROR_BUFFER_TOO_SMALL;
        error = scan.EnterContainer(containers[depth++]);
        if (error != CHIP_NO_ERROR) return error;
      }
    }
    if (scan.GetLengthRead() - start > Owner::kMaximumArgumentsBytes) {
      return CHIP_ERROR_BUFFER_TOO_SMALL;
    }
  }
  result.resize(Owner::kMaximumArgumentsBytes);
  chip::TLV::TLVWriter writer;
  writer.Init(result.data(), static_cast<std::uint32_t>(result.size()));
  error = writer.CopyElement(chip::TLV::AnonymousTag(), arguments);
  if (error != CHIP_NO_ERROR) return error;
  error = writer.Finalize();
  if (error != CHIP_NO_ERROR) return error;
  result.resize(writer.GetLengthWritten());
  return CHIP_NO_ERROR;
}

CHIP_ERROR AdmissionError(BridgeConsumerHandoff::Admission result) {
  using Admission = BridgeConsumerHandoff::Admission;
  switch (result) {
  case Admission::Reserved:
    return CHIP_NO_ERROR;
  case Admission::Busy:
    return CHIP_ERROR_BUSY;
  case Admission::Exhausted:
    return CHIP_ERROR_INCORRECT_STATE;
  case Admission::Closed:
    return CHIP_ERROR_INCORRECT_STATE;
  case Admission::InvalidClock:
  case Admission::InvalidDeadline:
    return CHIP_ERROR_INVALID_ARGUMENT;
  }
  return CHIP_ERROR_INVALID_ARGUMENT;
}

Status RefusedStatus(BridgeConsumerHandoff::Outcome outcome) {
  using Outcome = BridgeConsumerHandoff::Outcome;
  if (outcome == Outcome::Denied) return Status::UnsupportedAccess;
  if (outcome == Outcome::TimedOut) return Status::Timeout;
  return Status::Failure;
}

Status GuardStatus(CHIP_ERROR error) {
  if (error == CHIP_ERROR_ACCESS_DENIED) return Status::UnsupportedAccess;
  if (error == CHIP_ERROR_ACCESS_RESTRICTED_BY_ARL) return Status::AccessRestricted;
  if (error == CHIP_IM_GLOBAL_STATUS(UnsupportedEndpoint)) return Status::UnsupportedEndpoint;
  if (error == CHIP_IM_GLOBAL_STATUS(UnsupportedCluster)) return Status::UnsupportedCluster;
  if (error == CHIP_IM_GLOBAL_STATUS(UnsupportedCommand)) return Status::UnsupportedCommand;
  if (error == CHIP_IM_GLOBAL_STATUS(NeedsTimedInteraction)) return Status::NeedsTimedInteraction;
  return Status::Failure;
}

} // namespace

BridgeRequestMetadata CaptureBridgeRequest(
    const chip::app::DataModel::ReadAttributeRequest &request) {
  BridgeRequestMetadata result;
  result.operation = BridgeRequestMetadata::Operation::Read;
  result.principal = request.subjectDescriptor;
  result.endpoint = request.path.mEndpointId;
  result.cluster = request.path.mClusterId;
  result.member = request.path.mAttributeId;
  result.expanded = request.path.mExpanded;
  result.fabric_filtered = request.readFlags.Has(ReadFlags::kFabricFiltered);
  result.allows_large_payload = request.readFlags.Has(ReadFlags::kAllowsLargePayload);
  return result;
}

BridgeRequestMetadata CaptureBridgeRequest(
    const chip::app::DataModel::WriteAttributeRequest &request) {
  BridgeRequestMetadata result;
  result.operation = BridgeRequestMetadata::Operation::Write;
  result.principal = request.subjectDescriptor;
  result.endpoint = request.path.mEndpointId;
  result.cluster = request.path.mClusterId;
  result.member = request.path.mAttributeId;
  result.expanded = request.path.mExpanded;
  result.timed = request.writeFlags.Has(WriteFlags::kTimed);
  result.list_operation = request.path.mListOp;
  result.list_index = request.path.mListIndex;
  if (request.path.mDataVersion.HasValue()) result.data_version = request.path.mDataVersion.Value();
  return result;
}

BridgeRequestMetadata CaptureBridgeRequest(const chip::app::DataModel::InvokeRequest &request) {
  BridgeRequestMetadata result;
  result.operation = BridgeRequestMetadata::Operation::Invoke;
  result.principal = request.subjectDescriptor;
  result.endpoint = request.path.mEndpointId;
  result.cluster = request.path.mClusterId;
  result.member = request.path.mCommandId;
  // ConcreteCommandPath does not initialize its unused superclass expansion
  // flag. Only attribute paths define expansion metadata in the SDK request.
  result.timed = request.invokeFlags.Has(InvokeFlags::kTimed);
  return result;
}

class SdkBridgeInvokeContexts::Impl final {
 public:
  Impl(BridgeConsumerHandoff &handoff, BridgeInvokeGuard &guard)
      : handoff_(handoff), guard_(guard) {}
  ~Impl() {
    if (pending_ != 0) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  }

  struct Pending {
    Pending(BridgeInvocation value, BridgeInvokeScope captured, chip::app::CommandHandler &handler)
        : invocation(std::move(value)), scope(captured), handle(&handler) {}
    BridgeInvocation invocation;
    BridgeInvokeScope scope;
    chip::app::CommandHandler::Handle handle;
  };

  Pending *Find(const BridgeConsumerHandoff::Ticket &ticket) {
    for (auto &entry : entries_) {
      if (entry && entry->invocation.ticket.id == ticket.id &&
          entry->invocation.ticket.generation == ticket.generation)
        return &*entry;
    }
    return nullptr;
  }

  CHIP_ERROR Start(const chip::app::DataModel::InvokeRequest &request,
                   chip::TLV::TLVReader &arguments, chip::app::CommandHandler &handler,
                   std::uint64_t now_ms, std::uint64_t deadline_ms,
                   BridgeConsumerHandoff::Ticket &ticket) {
    if (closed_ || handoff_.closed()) return CHIP_ERROR_INCORRECT_STATE;
    if (!request.path.HasValidIds() || !chip::IsValidCommandId(request.path.mCommandId) ||
        !SamePrincipal(request.subjectDescriptor, handler.GetSubjectDescriptor()) ||
        request.invokeFlags.Has(InvokeFlags::kTimed) != handler.IsTimedInvoke()) {
      return CHIP_ERROR_INVALID_ARGUMENT;
    }
    std::size_t slot = 0;
    while (slot < entries_.size() && entries_[slot]) ++slot;
    if (slot == entries_.size()) return CHIP_ERROR_BUSY;
    BridgeInvocation invocation;
    invocation.request = CaptureBridgeRequest(request);
    invocation.deadline_ms = deadline_ms;
    BridgeInvokeScope scope;
    const CHIP_ERROR guarded = guard_.Capture(invocation.request, scope);
    if (guarded != CHIP_NO_ERROR) return guarded;
    const CHIP_ERROR copied = CopyArguments(arguments, invocation.arguments);
    if (copied != CHIP_NO_ERROR) return copied;
    const CHIP_ERROR admitted = AdmissionError(
        handoff_.Reserve(now_ms, deadline_ms, invocation.ticket));
    if (admitted != CHIP_NO_ERROR) return admitted;
    const auto admitted_ticket = invocation.ticket;
    try {
      entries_[slot].emplace(std::move(invocation), scope, handler);
    } catch (...) {
      // Admission already committed the ticket. An incomplete SDK handle
      // acquisition cannot be repaired by returning to request service.
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    }
    ++pending_;
    ticket = admitted_ticket;
    return CHIP_NO_ERROR;
  }

  CHIP_ERROR Respond(const BridgeConsumerHandoff::Ticket &ticket, std::uint64_t now_ms,
                     BridgeInvokeReply &reply) {
    auto *entry = Find(ticket);
    if (entry == nullptr) return CHIP_ERROR_NOT_FOUND;
    BridgeConsumerHandoff::Outcome outcome = BridgeConsumerHandoff::Outcome::Unknown;
    const auto taken = handoff_.Take(ticket, now_ms, outcome);
    if (taken == BridgeConsumerHandoff::Consume::Pending) return CHIP_ERROR_BUSY;
    if (taken == BridgeConsumerHandoff::Consume::InvalidClock) return CHIP_ERROR_INVALID_ARGUMENT;
    if (taken != BridgeConsumerHandoff::Consume::Completed) {
      // Another owner must not consume this owner's ticket behind its handle.
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    }
    CHIP_ERROR error = CHIP_NO_ERROR;
    if (auto *handler = entry->handle.Get()) {
      if (outcome == BridgeConsumerHandoff::Outcome::Completed) {
        error = guard_.Validate(entry->scope);
        if (error == CHIP_NO_ERROR) {
          error = reply.Completed(*handler, entry->invocation);
        } else {
          const chip::app::ConcreteCommandPath path(entry->invocation.request.endpoint,
                                                    entry->invocation.request.cluster,
                                                    entry->invocation.request.member);
          const auto encoded = handler->FallibleAddStatus(path, GuardStatus(error));
          // A written refusal does not erase the guard failure. Encoding
          // failure takes precedence while the consumed handle still drains.
          if (encoded != CHIP_NO_ERROR) error = encoded;
        }
      } else {
        const chip::app::ConcreteCommandPath path(entry->invocation.request.endpoint,
                                                  entry->invocation.request.cluster,
                                                  entry->invocation.request.member);
        error = handler->FallibleAddStatus(path, RefusedStatus(outcome));
      }
    }
    for (auto &candidate : entries_) {
      if (candidate && &*candidate == entry) {
        candidate.reset();
        --pending_;
        break;
      }
    }
    return error;
  }

  BridgeConsumerHandoff &handoff_;
  BridgeInvokeGuard &guard_;
  std::array<std::optional<Pending>, BridgeConsumerHandoff::kCapacity> entries_{};
  std::size_t pending_{0};
  bool closed_{false};
};

SdkBridgeInvokeContexts::SdkBridgeInvokeContexts(BridgeConsumerHandoff &handoff,
                                                 BridgeInvokeGuard &guard)
    : impl_(std::make_unique<Impl>(handoff, guard)) {}
SdkBridgeInvokeContexts::~SdkBridgeInvokeContexts() = default;

CHIP_ERROR SdkBridgeInvokeContexts::Start(const chip::app::DataModel::InvokeRequest &request,
                                          chip::TLV::TLVReader &arguments,
                                          chip::app::CommandHandler &handler, std::uint64_t now_ms,
                                          std::uint64_t deadline_ms,
                                          BridgeConsumerHandoff::Ticket &ticket) {
  try {
    return impl_->Start(request, arguments, handler, now_ms, deadline_ms, ticket);
  } catch (const std::bad_alloc &) {
    // Payload allocation precedes admission. The Impl terminates on an
    // incomplete handle acquisition after admission, independently of any
    // read/write slots sharing the handoff.
    return CHIP_ERROR_NO_MEMORY;
  }
}

CHIP_ERROR SdkBridgeInvokeContexts::Request(const BridgeConsumerHandoff::Ticket &ticket,
                                            BridgeInvocation &invocation) const {
  BridgeFabricScope fabric;
  return Request(ticket, invocation, fabric);
}

CHIP_ERROR SdkBridgeInvokeContexts::Request(const BridgeConsumerHandoff::Ticket &ticket,
                                            BridgeInvocation &invocation,
                                            BridgeFabricScope &fabric) const {
  auto *entry = impl_->Find(ticket);
  if (entry == nullptr) return CHIP_ERROR_NOT_FOUND;
  try {
    auto copy = entry->invocation;
    invocation = std::move(copy);
    fabric = entry->scope.fabric;
    return CHIP_NO_ERROR;
  } catch (const std::bad_alloc &) {
    return CHIP_ERROR_NO_MEMORY;
  }
}

CHIP_ERROR SdkBridgeInvokeContexts::Respond(const BridgeConsumerHandoff::Ticket &ticket,
                                            std::uint64_t now_ms, BridgeInvokeReply &reply) {
  return impl_->Respond(ticket, now_ms, reply);
}

CHIP_ERROR SdkBridgeInvokeContexts::Finish(std::uint64_t now_ms) {
  class NoCompletedReply final : public BridgeInvokeReply {
   public:
    CHIP_ERROR Completed(chip::app::CommandHandler &, const BridgeInvocation &) noexcept override {
      std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
    }
  } closed_reply;
  impl_->closed_ = true;
  impl_->handoff_.Close();
  CHIP_ERROR first = CHIP_NO_ERROR;
  for (auto &entry : impl_->entries_) {
    if (!entry) continue;
    const auto ticket = entry->invocation.ticket;
    const CHIP_ERROR error = impl_->Respond(ticket, now_ms, closed_reply);
    if (error != CHIP_NO_ERROR && first == CHIP_NO_ERROR) first = error;
  }
  return first;
}

std::size_t SdkBridgeInvokeContexts::pending() const { return impl_->pending_; }

} // namespace wotex::matter
