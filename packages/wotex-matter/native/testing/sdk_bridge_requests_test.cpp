#include "sdk_bridge_requests_test.hpp"
#include "wotex_matter/bridge_requests.hpp"

#include <lib/core/TLVWriter.h>

#include <algorithm>
#include <iostream>
#include <stdexcept>

namespace wotex::matter::testing {
namespace {

using Handoff = BridgeConsumerHandoff;
using chip::app::CommandHandler;
using chip::app::ConcreteCommandPath;
using chip::app::DataModel::InvokeFlags;
using chip::app::DataModel::InvokeRequest;
using Status = chip::Protocols::InteractionModel::Status;

void Require(bool value, const char *stage) {
  if (!value) {
    std::cerr << "request test failed: " << stage << '\n';
    throw std::runtime_error(stage);
  }
}
void Check(CHIP_ERROR error, const char *stage) { Require(error == CHIP_NO_ERROR, stage); }

// Uses the actual SDK Handle interface; principal/path inputs are explicit
// synthetic fixtures, not evidence of commissioning or authenticated admission.
class Handler final : public CommandHandler {
 public:
  chip::Access::SubjectDescriptor principal;
  std::vector<Handle *> retained;
  unsigned replies{0};
  ConcreteCommandPath last_path{0, 0, 0};
  Status last_status{Status::Failure};
  bool timed{false};
  bool refuse_status{false};

  Handler() { retained.reserve(Handoff::kCapacity); }
  CHIP_ERROR FallibleAddStatus(const ConcreteCommandPath &path,
                               const chip::Protocols::InteractionModel::ClusterStatusCode &status,
                               const char *) override {
    if (refuse_status) return CHIP_ERROR_BUFFER_TOO_SMALL;
    ++replies;
    last_path = path;
    last_status = status.GetStatus();
    return CHIP_NO_ERROR;
  }
  void AddStatus(const ConcreteCommandPath &path,
                 const chip::Protocols::InteractionModel::ClusterStatusCode &status,
                 const char *context) override {
    Check(FallibleAddStatus(path, status, context), "synthetic response status");
  }
  chip::FabricIndex GetAccessingFabricIndex() const override {
    Require(retained.empty(), "async fabric lookup forbidden");
    return principal.fabricIndex;
  }
  CHIP_ERROR AddResponseData(const ConcreteCommandPath &, chip::CommandId,
                             const chip::app::DataModel::EncodableToTLV &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  void AddResponse(const ConcreteCommandPath &, chip::CommandId,
                   const chip::app::DataModel::EncodableToTLV &) override {
    throw std::runtime_error("unexpected response data");
  }
  bool IsTimedInvoke() const override { return timed; }
  void FlushAcksRightAwayOnSlowCommand() override {}
  chip::Access::SubjectDescriptor GetSubjectDescriptor() const override { return principal; }
  chip::Messaging::ExchangeContext *GetExchangeContext() const override { return nullptr; }
  void InvalidateAll() {
    for (auto *handle : retained) handle->Invalidate();
    retained.clear();
  }

 protected:
  void IncrementHoldOff(Handle *handle) override { retained.push_back(handle); }
  void DecrementHoldOff(Handle *handle) override {
    const auto found = std::find(retained.begin(), retained.end(), handle);
    Require(found != retained.end(), "handle released twice");
    retained.erase(found);
  }
};

class Reply final : public BridgeInvokeReply {
 public:
  unsigned calls{0};
  CHIP_ERROR Completed(CommandHandler &handler,
                       const BridgeInvocation &invocation) noexcept override {
    ++calls;
    return handler.FallibleAddStatus(
        ConcreteCommandPath(invocation.request.endpoint, invocation.request.cluster,
                            invocation.request.member),
        Status::Success);
  }
};

std::vector<std::uint8_t> Arguments(std::size_t bytes = 0) {
  std::vector<std::uint8_t> output(bytes + 64);
  chip::TLV::TLVWriter writer;
  writer.Init(output.data(), static_cast<std::uint32_t>(output.size()));
  chip::TLV::TLVType outer;
  chip::TLV::TLVType envelope;
  Check(writer.StartContainer(chip::TLV::AnonymousTag(), chip::TLV::kTLVType_Structure, envelope),
        "arguments envelope");
  Check(writer.StartContainer(chip::TLV::ContextTag(2), chip::TLV::kTLVType_Structure, outer),
        "arguments root");
  Check(writer.Put(chip::TLV::ContextTag(0), static_cast<std::uint16_t>(123)), "arguments scalar");
  if (bytes != 0) {
    std::vector<std::uint8_t> payload(bytes, 0x5A);
    Check(writer.PutBytes(chip::TLV::ContextTag(1), payload.data(),
                          static_cast<std::uint32_t>(payload.size())),
          "arguments bytes");
  }
  Check(writer.EndContainer(outer), "arguments end");
  Check(writer.EndContainer(envelope), "arguments envelope end");
  Check(writer.Finalize(), "arguments finalize");
  output.resize(writer.GetLengthWritten());
  return output;
}

chip::TLV::TLVReader Reader(const std::vector<std::uint8_t> &bytes) {
  chip::TLV::TLVReader reader;
  reader.Init(bytes.data(), bytes.size());
  Check(reader.Next(), "arguments reader");
  return reader;
}

chip::TLV::TLVReader ArgumentReader(const std::vector<std::uint8_t> &bytes) {
  auto reader = Reader(bytes);
  chip::TLV::TLVType envelope;
  Check(reader.EnterContainer(envelope), "argument envelope reader");
  Check(reader.Next(), "argument fields reader");
  return reader;
}

std::vector<std::uint8_t> SizedArguments(std::size_t encoded_bytes) {
  const auto probe = Arguments(60000);
  // The enclosing structure is two bytes; an anonymous argument root saves one.
  const auto overhead = probe.size() - 60000 - 3;
  auto result = Arguments(encoded_bytes - overhead);
  Require(result.size() - 3 == encoded_bytes, "encoded argument boundary fixture");
  return result;
}

std::vector<std::uint8_t> NestedArguments(std::size_t depth, std::size_t leaves) {
  std::vector<std::uint8_t> output(65536);
  chip::TLV::TLVWriter writer;
  writer.Init(output.data(), static_cast<std::uint32_t>(output.size()));
  chip::TLV::TLVType envelope;
  Check(writer.StartContainer(chip::TLV::AnonymousTag(), chip::TLV::kTLVType_Structure, envelope),
        "nested argument envelope");
  std::vector<chip::TLV::TLVType> containers(depth);
  for (std::size_t index = 0; index < depth; ++index) {
    Check(writer.StartContainer(chip::TLV::ContextTag(index == 0 ? 2 : 0),
                                chip::TLV::kTLVType_Structure, containers[index]),
          "nested argument fixture");
  }
  for (std::size_t index = 0; index < leaves; ++index) {
    Check(writer.Put(chip::TLV::ContextTag(1), true), "argument node fixture");
  }
  for (auto index = depth; index != 0; --index) {
    Check(writer.EndContainer(containers[index - 1]), "nested argument end");
  }
  Check(writer.EndContainer(envelope), "nested argument envelope end");
  Check(writer.Finalize(), "nested arguments finalize");
  output.resize(writer.GetLengthWritten());
  return output;
}

void Boundaries() {
  Handoff handoff({2});
  Handler handler;
  handler.principal.fabricIndex = 1;
  handler.principal.authMode = chip::Access::AuthMode::kCase;
  handler.principal.subject = 1;
  SdkBridgeInvokeContexts contexts(handoff);
  Reply reply;
  InvokeRequest request(ConcreteCommandPath(3, 6, 1), handler.principal);
  Handoff::Ticket ticket{{9}, 99};
  for (const auto &arguments :
       {SizedArguments(65536), NestedArguments(24, 1), NestedArguments(1, 4095)}) {
    auto reader = ArgumentReader(arguments);
    Check(contexts.Start(request, reader, handler, 100, 600, ticket),
          "inclusive argument boundary refused");
    BridgeInvocation captured;
    Check(contexts.Request(ticket, captured), "boundary payload capture");
    Require(captured.arguments.size() == arguments.size() - 3, "boundary payload bytes changed");
    Require(handoff.Resolve(ticket, Handoff::Outcome::Denied, 100) == Handoff::Reply::Stored,
            "boundary fixture resolution");
    Check(contexts.Respond(ticket, 100, reply), "boundary handle release");
  }
  for (const auto &arguments :
       {SizedArguments(65537), NestedArguments(25, 1), NestedArguments(1, 4096)}) {
    auto reader = ArgumentReader(arguments);
    Handoff::Ticket unchanged{{9}, 99};
    Require(contexts.Start(request, reader, handler, 100, 600, unchanged) ==
                    CHIP_ERROR_BUFFER_TOO_SMALL &&
                unchanged.id == 99 && unchanged.generation[0] == 9 && contexts.pending() == 0 &&
                handoff.pending() == 0 && handler.retained.empty(),
            "excessive argument boundary acquired a context");
  }
  const std::vector<std::uint8_t> scalar{0x04, 1};
  auto scalar_reader = Reader(scalar);
  Require(contexts.Start(request, scalar_reader, handler, 100, 600, ticket) ==
              CHIP_ERROR_INVALID_ARGUMENT,
          "non-structure command arguments admitted");
  auto arguments = Arguments();
  auto reader = ArgumentReader(arguments);
  for (const auto &path : {ConcreteCommandPath(chip::kInvalidEndpointId, 6, 1),
                           ConcreteCommandPath(3, chip::kInvalidClusterId, 1),
                           ConcreteCommandPath(3, 6, chip::kInvalidCommandId)}) {
    InvokeRequest invalid(path, handler.principal);
    Require(
        contexts.Start(invalid, reader, handler, 100, 600, ticket) == CHIP_ERROR_INVALID_ARGUMENT &&
            contexts.pending() == 0,
        "invalid concrete command path admitted");
  }
  const auto original = handler.principal;
  std::array<chip::Access::SubjectDescriptor, 5> foreign{};
  foreign.fill(original);
  foreign[0].fabricIndex = 2;
  foreign[1].authMode = chip::Access::AuthMode::kGroup;
  foreign[2].subject = 2;
  foreign[3].cats.values[2] = 0x00030001;
  foreign[4].isCommissioning = true;
  for (const auto &principal : foreign) {
    InvokeRequest invalid(ConcreteCommandPath(3, 6, 1), principal);
    Require(
        contexts.Start(invalid, reader, handler, 100, 600, ticket) == CHIP_ERROR_INVALID_ARGUMENT &&
            contexts.pending() == 0 && handler.retained.empty(),
        "request and handler principal differ");
  }
  Check(contexts.Start(request, reader, handler, 100, 600, ticket), "response failure fixture");
  Require(handoff.Resolve(ticket, Handoff::Outcome::Completed, 101) == Handoff::Reply::Stored,
          "response failure staged result");
  Require(contexts.Respond(ticket, 100, reply) == CHIP_ERROR_INVALID_ARGUMENT &&
              contexts.pending() == 1 && handler.retained.size() == 1 && reply.calls == 0,
          "clock regression consumed a handle or response");
  handler.refuse_status = true;
  Require(contexts.Respond(ticket, 101, reply) == CHIP_ERROR_BUFFER_TOO_SMALL &&
              contexts.pending() == 0 && handoff.pending() == 0 && handler.retained.empty() &&
              reply.calls == 1,
          "completed encoding failure leaked a handle or became success");
  const auto old = ticket;
  Check(contexts.Start(request, reader, handler, 101, 601, ticket), "replacement context");
  BridgeInvocation unchanged;
  unchanged.deadline_ms = 99;
  Require(ticket.id > old.id && contexts.Request(old, unchanged) == CHIP_ERROR_NOT_FOUND &&
              unchanged.deadline_ms == 99 &&
              contexts.Respond(old, 101, reply) == CHIP_ERROR_NOT_FOUND,
          "released context resurrected or reused its identity");
  Require(handoff.Resolve(ticket, Handoff::Outcome::Denied, 102) == Handoff::Reply::Stored,
          "refused encoding fixture");
  Require(contexts.Respond(ticket, 102, reply) == CHIP_ERROR_BUFFER_TOO_SMALL &&
              contexts.pending() == 0 && handler.retained.empty() && reply.calls == 1,
          "refused encoding failure leaked a handle or called completed renderer");
  handler.refuse_status = false;
  Handoff::Ticket other;
  Require(handoff.Reserve(102, 602, other) == Handoff::Admission::Reserved,
          "shared read/write context fixture");
  Check(contexts.Start(request, reader, handler, 102, 602, ticket), "shared context admission");
  Require(handoff.Resolve(ticket, Handoff::Outcome::Completed, 103) == Handoff::Reply::Stored,
          "shutdown staged completion fixture");
  Check(contexts.Finish(103), "shared context shutdown");
  Require(contexts.pending() == 0 && handoff.pending() == 1 && handler.retained.empty() &&
              handler.last_status == Status::Failure && reply.calls == 1,
          "shutdown consumed another owner's credit or published staged success");
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(handoff.Take(other, 103, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Closed,
          "shared context owner lost its closure result");
  ticket = {{9}, 99};
  Require(
      contexts.Start(request, reader, handler, 103, 603, ticket) == CHIP_ERROR_INCORRECT_STATE &&
          ticket.id == 99 && ticket.generation[0] == 9,
      "closed context owner admitted another request");
}

class Probe final : public RequestProbe {
 public:
  Probe(Handoff &handoff, bool invalidate)
      : handoff_(handoff), contexts_(handoff), invalidate_(invalidate) {
    handler_.principal.fabricIndex = 2;
    handler_.principal.authMode = chip::Access::AuthMode::kCase;
    handler_.principal.subject = 0x1234;
    handler_.principal.cats.values[0] = 0x00010002;
    handler_.principal.cats.values[2] = 0x00030004;
    handler_.timed = true;
    Boundaries();
    Metadata();
    RefusedInputs();
    for (std::size_t index = 0; index < tickets_.size(); ++index) {
      auto arguments = Arguments();
      auto reader = ArgumentReader(arguments);
      const auto position = reader.GetReadPoint();
      InvokeRequest request(ConcreteCommandPath(static_cast<chip::EndpointId>(3 + index), 6, 1),
                            handler_.principal);
      request.invokeFlags.Set(InvokeFlags::kTimed);
      Check(contexts_.Start(request, reader, handler_, 100, 600, tickets_[index]),
            "sixteen SDK contexts");
      Require(reader.GetReadPoint() == position && reader.GetTag() == chip::TLV::ContextTag(2),
              "capture advanced borrowed reader");
      std::fill(arguments.begin(), arguments.end(), 0xFF);
    }
    Require(handler_.retained.size() == 16 && contexts_.pending() == 16 && handoff_.pending() == 16,
            "SDK handle credit differs from request credit");
    auto arguments = Arguments();
    auto reader = ArgumentReader(arguments);
    InvokeRequest request(ConcreteCommandPath(3, 6, 1), handler_.principal);
    request.invokeFlags.Set(InvokeFlags::kTimed);
    Handoff::Ticket unchanged{{9}, 99};
    Require(contexts_.Start(request, reader, handler_, 100, 600, unchanged) == CHIP_ERROR_BUSY &&
                unchanged.id == 99 && unchanged.generation[0] == 9,
            "seventeenth context changed output");
    handler_.principal = {};
    for (std::size_t index = 0; index < tickets_.size(); ++index) {
      BridgeInvocation captured;
      Check(contexts_.Request(tickets_[index], captured), "owned request copy");
      Require(captured.request.principal.fabricIndex == 2 &&
                  captured.request.principal.authMode == chip::Access::AuthMode::kCase &&
                  captured.request.principal.subject == 0x1234 &&
                  captured.request.principal.cats.values[0] == 0x00010002 &&
                  captured.request.principal.cats.values[2] == 0x00030004 &&
                  captured.request.timed && captured.request.endpoint == 3 + index &&
                  captured.request.cluster == 6 && captured.request.member == 1 &&
                  captured.deadline_ms == 600,
              "request retained a borrowed principal/path/deadline");
      auto copied = Reader(captured.arguments);
      Require(copied.GetTag() == chip::TLV::AnonymousTag(), "owned arguments root not anonymous");
      chip::TLV::TLVType outer;
      Check(copied.EnterContainer(outer), "copied arguments container");
      Check(copied.Next(), "copied arguments scalar");
      std::uint16_t value = 0;
      Check(copied.Get(value), "copied arguments value");
      Require(value == 123, "request retained borrowed arguments");
    }
    std::cout << "bridge owned request metadata and arguments passed\n" << std::flush;
  }

  void DuringLoop() override {
    Require(contexts_.Respond(tickets_[0], 101, reply_) == CHIP_ERROR_BUSY &&
                handler_.replies == 0 && reply_.calls == 0,
            "admission produced command success");
    Require(
        handoff_.Resolve(tickets_[0], Handoff::Outcome::Completed, 102) == Handoff::Reply::Stored,
        "completed request result");
    Check(contexts_.Respond(tickets_[0], 102, reply_), "explicit command response renderer");
    Require(reply_.calls == 1 && handler_.replies == 1 &&
                handler_.last_path == ConcreteCommandPath(3, 6, 1),
            "completed response lost command context");
    for (auto outcome :
         {Handoff::Outcome::Denied, Handoff::Outcome::Failed, Handoff::Outcome::Unknown}) {
      const std::size_t index = outcome == Handoff::Outcome::Denied ? 1
          : outcome == Handoff::Outcome::Failed                     ? 2
                                                                    : 3;
      Require(handoff_.Resolve(tickets_[index], outcome, 103) == Handoff::Reply::Stored,
              "refused request result");
      Check(contexts_.Respond(tickets_[index], 103, reply_), "refused SDK response");
      Require(handler_.last_status ==
                      (outcome == Handoff::Outcome::Denied ? Status::UnsupportedAccess
                                                           : Status::Failure) &&
                  reply_.calls == 1,
              "refused response invoked completed renderer");
    }
    auto foreign = tickets_[4];
    foreign.generation[15] = 1;
    BridgeInvocation unchanged;
    unchanged.deadline_ms = 99;
    Require(contexts_.Request(foreign, unchanged) == CHIP_ERROR_NOT_FOUND &&
                unchanged.deadline_ms == 99 &&
                contexts_.Respond(foreign, 103, reply_) == CHIP_ERROR_NOT_FOUND,
            "foreign context changed output or responded");
    Require(
        handoff_.Resolve(tickets_[4], Handoff::Outcome::Completed, 599) == Handoff::Reply::Stored,
        "staged delayed result");
    Check(contexts_.Respond(tickets_[4], 600, reply_), "delayed response expiry");
    Require(handler_.last_status == Status::Timeout && reply_.calls == 1,
            "delayed response published staged success");
    Require(contexts_.Respond(tickets_[4], 600, reply_) == CHIP_ERROR_NOT_FOUND &&
                contexts_.pending() == 11 && handler_.retained.size() == 11,
            "SDK context released or responded twice");
    if (invalidate_) handler_.InvalidateAll();
    Require(handoff_.Resolve(tickets_[5], Handoff::Outcome::Completed, 600) == Handoff::Reply::Late,
            "late invalidated context fixture");
    const auto replies = handler_.replies;
    Check(contexts_.Respond(tickets_[5], 600, reply_), "invalidated SDK handle consumed");
    Require(handler_.replies == replies + (invalidate_ ? 0U : 1U) && contexts_.pending() == 10 &&
                handoff_.pending() == 10,
            "SDK handle invalidation or late reply mishandled");
    std::cout << "bridge request event loop responses passed\n" << std::flush;
  }

  void Finish() override {
    const auto replies = handler_.replies;
    Check(contexts_.Finish(600), "request contexts shutdown");
    Check(contexts_.Finish(600), "repeated request contexts shutdown");
    Require(contexts_.pending() == 0 && handoff_.pending() == 0 && handler_.retained.empty(),
            "shutdown leaked SDK context or credit");
    Require(handler_.replies == replies + (invalidate_ ? 0U : 10U) && reply_.calls == 1,
            "shutdown produced success or used an invalidated handler");
    std::cout << "bridge request handles, responses and shutdown passed\n" << std::flush;
  }

 private:
  void Metadata() {
    const auto original = handler_.principal;
    for (const auto mode : {chip::Access::AuthMode::kGroup, chip::Access::AuthMode::kPase}) {
      chip::Access::SubjectDescriptor principal;
      principal.authMode = mode;
      principal.fabricIndex = mode == chip::Access::AuthMode::kGroup ? 3 : 0;
      principal.subject = mode == chip::Access::AuthMode::kGroup ? 0x123 : 0;
      principal.isCommissioning = mode == chip::Access::AuthMode::kPase;
      const auto expected = principal;
      InvokeRequest request(ConcreteCommandPath(3, 6, 1), principal);
      auto captured = CaptureBridgeRequest(request);
      principal = {};
      Require(captured.principal.authMode == expected.authMode &&
                  captured.principal.fabricIndex == expected.fabricIndex &&
                  captured.principal.subject == expected.subject &&
                  captured.principal.isCommissioning == expected.isCommissioning &&
                  !captured.timed && !captured.expanded &&
                  captured.operation == BridgeRequestMetadata::Operation::Invoke,
              "group or commissioning principal metadata changed");
    }
    chip::app::ConcreteAttributePath path(3, 6, 0);
    path.mExpanded = true;
    chip::app::DataModel::ReadAttributeRequest read(path, handler_.principal);
    read.readFlags.Set(chip::app::DataModel::ReadFlags::kFabricFiltered)
        .Set(chip::app::DataModel::ReadFlags::kAllowsLargePayload);
    auto captured = CaptureBridgeRequest(read);
    handler_.principal = {};
    Require(captured.principal.subject == original.subject && captured.expanded &&
                captured.fabric_filtered && captured.allows_large_payload &&
                captured.operation == BridgeRequestMetadata::Operation::Read,
            "read metadata lost owned principal/flags");
    handler_.principal = original;
    chip::app::ConcreteDataAttributePath data(3, 6, 0x4001);
    data.mExpanded = true;
    data.mListOp = chip::app::ConcreteDataAttributePath::ListOperation::ReplaceItem;
    data.mListIndex = 7;
    data.mDataVersion.SetValue(22);
    chip::app::DataModel::WriteAttributeRequest write(data, handler_.principal);
    write.writeFlags.Set(chip::app::DataModel::WriteFlags::kTimed);
    captured = CaptureBridgeRequest(write);
    handler_.principal = {};
    Require(captured.principal.fabricIndex == original.fabricIndex && captured.expanded &&
                captured.timed && captured.list_operation == data.mListOp &&
                captured.list_index == 7 && captured.data_version == 22 &&
                captured.member == 0x4001 &&
                captured.operation == BridgeRequestMetadata::Operation::Write,
            "write metadata lost list/version/timing");
    handler_.principal = original;
  }

  void RefusedInputs() {
    auto arguments = Arguments();
    auto reader = ArgumentReader(arguments);
    InvokeRequest request(ConcreteCommandPath(3, 6, 1), handler_.principal);
    Handoff::Ticket unchanged{{9}, 99};
    Require(contexts_.Start(request, reader, handler_, 100, 600, unchanged) ==
                CHIP_ERROR_INVALID_ARGUMENT,
            "mismatched timed context admitted");
    request.invokeFlags.Set(InvokeFlags::kTimed);
    handler_.principal.subject = 0x5678;
    auto request_principal = handler_.principal;
    request_principal.subject = 0x1234;
    InvokeRequest foreign(ConcreteCommandPath(3, 6, 1), request_principal);
    foreign.invokeFlags.Set(InvokeFlags::kTimed);
    Require(contexts_.Start(foreign, reader, handler_, 100, 600, unchanged) ==
                CHIP_ERROR_INVALID_ARGUMENT,
            "mismatched handler principal admitted");
    handler_.principal.subject = 0x1234;
    Require(contexts_.Start(request, reader, handler_, 100, 601, unchanged) ==
                    CHIP_ERROR_INVALID_ARGUMENT &&
                unchanged.id == 99 && handoff_.pending() == 0 && handler_.retained.empty(),
            "oversized handoff deadline acquired SDK handle");
    auto large = Arguments(SdkBridgeInvokeContexts::kMaximumArgumentsBytes);
    auto large_reader = ArgumentReader(large);
    Require(contexts_.Start(request, large_reader, handler_, 100, 600, unchanged) ==
                    CHIP_ERROR_BUFFER_TOO_SMALL &&
                unchanged.id == 99 && handoff_.pending() == 0 && handler_.retained.empty(),
            "oversized arguments acquired SDK handle");
    auto malformed = arguments;
    malformed.resize(malformed.size() - 2);
    auto malformed_reader = ArgumentReader(malformed);
    Require(contexts_.Start(request, malformed_reader, handler_, 100, 600, unchanged) !=
                    CHIP_NO_ERROR &&
                unchanged.id == 99 && handoff_.pending() == 0,
            "truncated arguments admitted");
  }

  Handoff &handoff_;
  Handler handler_;
  SdkBridgeInvokeContexts contexts_;
  Reply reply_;
  std::array<Handoff::Ticket, Handoff::kCapacity> tickets_{};
  bool invalidate_;
};

} // namespace

std::unique_ptr<RequestProbe> PrepareRequests(BridgeConsumerHandoff &handoff, bool invalidate) {
  return std::make_unique<Probe>(handoff, invalidate);
}

} // namespace wotex::matter::testing
