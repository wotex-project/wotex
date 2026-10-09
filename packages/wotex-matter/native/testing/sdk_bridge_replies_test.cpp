#include "sdk_bridge_replies_test.hpp"
#include "sdk_bridge_fixture_guard.hpp"
#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_replies.hpp"

#include <credentials/GroupDataProvider.h>
#include <app/clusters/scenes-server/SceneTableImpl.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>

#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace wotex::matter::testing {
namespace {

using CommandPath = chip::app::ConcreteCommandPath;
using Status = chip::Protocols::InteractionModel::Status;
using ClusterStatus = chip::Protocols::InteractionModel::ClusterStatusCode;
using CommandHandler = chip::app::CommandHandler;
using Encodable = chip::app::DataModel::EncodableToTLV;

void ReplyRequire(bool value, const char *stage) {
  if (!value) {
    std::cerr << "bridge reply test failed: " << stage << '\n';
    throw std::runtime_error(stage);
  }
}
void ReplyCheck(CHIP_ERROR error, const char *stage) {
  ReplyRequire(error == CHIP_NO_ERROR, stage);
}

class AsyncHandler final : public CommandHandler {
 public:
  chip::Access::SubjectDescriptor principal;
  std::vector<Handle *> handles;
  unsigned status_replies{0};
  unsigned data_replies{0};
  CHIP_ERROR data_error{CHIP_NO_ERROR};
  CHIP_ERROR status_error{CHIP_NO_ERROR};
  CommandPath last_path{0, 0, 0};
  Status last_status{Status::Failure};
  std::vector<std::uint8_t> response;

  CHIP_ERROR FallibleAddStatus(const CommandPath &path, const ClusterStatus &status,
                               const char *) override {
    if (status_error != CHIP_NO_ERROR) return status_error;
    ++status_replies;
    last_path = path;
    last_status = status.GetStatus();
    return CHIP_NO_ERROR;
  }
  void AddStatus(const CommandPath &, const ClusterStatus &, const char *) override {
    throw std::runtime_error("unchecked status forwarded");
  }
  CHIP_ERROR AddResponseData(const CommandPath &path, chip::CommandId,
                             const Encodable &value) override {
    if (data_error != CHIP_NO_ERROR) return data_error;
    response.resize(8192);
    chip::TLV::TLVWriter writer;
    writer.Init(response.data(), response.size());
    chip::TLV::TLVType envelope;
    ReplyCheck(
        writer.StartContainer(chip::TLV::AnonymousTag(), chip::TLV::kTLVType_Structure, envelope),
        "reply envelope");
    chip::app::DataModel::FabricAwareTLVWriter fabric_writer(writer, 2);
    ReplyCheck(value.EncodeTo(fabric_writer, chip::TLV::ContextTag(2)), "reply encoding");
    ReplyCheck(writer.EndContainer(envelope), "reply envelope end");
    ReplyCheck(writer.Finalize(), "reply finalize");
    response.resize(writer.GetLengthWritten());
    ++data_replies;
    last_path = path;
    return CHIP_NO_ERROR;
  }
  void AddResponse(const CommandPath &, chip::CommandId, const Encodable &) override {
    throw std::runtime_error("unchecked response forwarded");
  }
  chip::FabricIndex GetAccessingFabricIndex() const override {
    ReplyRequire(handles.empty(), "async fabric query forwarded");
    return principal.fabricIndex;
  }
  chip::Access::SubjectDescriptor GetSubjectDescriptor() const override {
    ReplyRequire(handles.empty(), "async principal query forwarded");
    return principal;
  }
  bool IsTimedInvoke() const override {
    ReplyRequire(handles.empty(), "async timed query forwarded");
    return false;
  }
  chip::Messaging::ExchangeContext *GetExchangeContext() const override {
    throw std::runtime_error("async exchange query forwarded");
  }
  void FlushAcksRightAwayOnSlowCommand() override {
    throw std::runtime_error("async acknowledgement forwarded");
  }
 protected:
  void IncrementHoldOff(Handle *handle) override { handles.push_back(handle); }
  void DecrementHoldOff(Handle *handle) override {
    const auto found = std::find(handles.begin(), handles.end(), handle);
    ReplyRequire(found != handles.end(), "reply handle released twice");
    handles.erase(found);
  }
};

class DelegateReply final : public BridgeInvokeReply {
 public:
  CHIP_ERROR Completed(CommandHandler &handler,
                       const BridgeInvocation &invocation) noexcept override {
    const chip::CommandId id = 0;
    SdkBridgeCommandReply reply(handler, invocation.request,
                                chip::Span<const chip::CommandId>(&id, 1));
    if (reply.configuration_status() != CHIP_NO_ERROR) return reply.configuration_status();
    chip::TLV::TLVReader reader;
    reader.Init(invocation.arguments.data(), invocation.arguments.size());
    auto error = reader.Next();
    if (error != CHIP_NO_ERROR) return error;
    chip::app::DataModel::InvokeRequest request(
        CommandPath(invocation.request.endpoint, invocation.request.cluster,
                    invocation.request.member),
        invocation.request.principal);
    request.invokeFlags.Set(chip::app::DataModel::InvokeFlags::kTimed, invocation.request.timed);
    const auto returned = chip::app::CodegenDataModelProvider::Instance().InvokeCommand(
        request, reader, &reply);
    if (returned) (void)reply.FallibleAddStatus(request.path, returned->GetStatusCode(), nullptr);
    return reply.result();
  }
};

class EmptyReply final : public Encodable {
 public:
  CHIP_ERROR EncodeTo(chip::TLV::TLVWriter &writer, chip::TLV::Tag tag) const override {
    chip::TLV::TLVType structure;
    const auto error = writer.StartContainer(tag, chip::TLV::kTLVType_Structure, structure);
    return error == CHIP_NO_ERROR ? writer.EndContainer(structure) : error;
  }
};

void ReplyBoundaries() {
  AsyncHandler handler;
  BridgeRequestMetadata request;
  request.operation = BridgeRequestMetadata::Operation::Invoke;
  request.endpoint = 3;
  request.cluster = 4;
  request.member = 0;
  request.principal.fabricIndex = 2;
  request.principal.subject = 0x1234;
  const CommandPath path(3, 4, 0);
  const ClusterStatus success(Status::Success);
  EmptyReply payload;
  SdkBridgeCommandReply empty(handler, request, chip::Span<const chip::CommandId>());
  ReplyRequire(
      empty.configuration_status() == CHIP_NO_ERROR && empty.result() == CHIP_ERROR_INCORRECT_STATE,
      "missing reply treated as completion");
  for (const auto &path_input :
       {CommandPath(chip::kInvalidEndpointId, 4, 0), CommandPath(3, chip::kInvalidClusterId, 0),
        CommandPath(3, 4, chip::kInvalidCommandId)}) {
    auto invalid = request;
    invalid.endpoint = path_input.mEndpointId;
    invalid.cluster = path_input.mClusterId;
    invalid.member = path_input.mCommandId;
    SdkBridgeCommandReply reply(handler, invalid, chip::Span<const chip::CommandId>());
    ReplyRequire(reply.configuration_status() == CHIP_ERROR_INVALID_ARGUMENT &&
                     reply.result() == CHIP_ERROR_INVALID_ARGUMENT,
                 "invalid request path admitted");
  }
  auto wrong_operation = request;
  wrong_operation.operation = BridgeRequestMetadata::Operation::Read;
  SdkBridgeCommandReply non_invoke(handler, wrong_operation, chip::Span<const chip::CommandId>());
  ReplyRequire(non_invoke.configuration_status() == CHIP_ERROR_INVALID_ARGUMENT,
               "attribute context used as command reply");
  const std::array<chip::CommandId, 8> exact{0, 1, 2, 3, 4, 5, 6, 7};
  SdkBridgeCommandReply maximum(handler, request, chip::Span<const chip::CommandId>(exact));
  ReplyCheck(maximum.configuration_status(), "inclusive response scope refused");
  std::array<chip::CommandId, 9> excess{0, 1, 2, 3, 4, 5, 6, 7, 8};
  SdkBridgeCommandReply oversized(handler, request, chip::Span<const chip::CommandId>(excess));
  ReplyRequire(
      oversized.configuration_status() == CHIP_ERROR_INVALID_ARGUMENT &&
          oversized.FallibleAddStatus(path, success, nullptr) == CHIP_ERROR_INVALID_ARGUMENT &&
          handler.status_replies == 0,
      "invalid response scope admitted");
  const chip::CommandId duplicate[]{0, 0};
  SdkBridgeCommandReply repeated(handler, request, chip::Span<const chip::CommandId>(duplicate));
  ReplyRequire(repeated.configuration_status() == CHIP_ERROR_INVALID_ARGUMENT,
               "duplicate response scope admitted");
  chip::CommandId response[]{0};
  SdkBridgeCommandReply copied(handler, request, chip::Span<const chip::CommandId>(response));
  response[0] = 9;
  request.principal.fabricIndex = 9;
  ReplyRequire(copied.GetAccessingFabricIndex() == 2, "principal scope borrowed");
  ReplyRequire(copied.AddResponseData(path, 9, payload) == CHIP_ERROR_INVALID_ARGUMENT &&
                   handler.data_replies == 0,
               "response scope borrowed");
  for (const auto &wrong : {CommandPath(4, 4, 0), CommandPath(3, 5, 0), CommandPath(3, 4, 1)}) {
    SdkBridgeCommandReply foreign(handler, request, chip::Span<const chip::CommandId>());
    ReplyRequire(
        foreign.FallibleAddStatus(wrong, success, nullptr) == CHIP_ERROR_INVALID_ARGUMENT &&
            handler.status_replies == 0,
        "foreign response path admitted");
    ReplyRequire(foreign.FallibleAddStatus(path, success, nullptr) == CHIP_ERROR_INVALID_ARGUMENT &&
                     handler.status_replies == 0,
                 "invalidated reply adapter resumed service");
  }
  SdkBridgeCommandReply single(handler, request, chip::Span<const chip::CommandId>());
  ReplyCheck(single.FallibleAddStatus(path, success, nullptr), "one status reply");
  ReplyRequire(single.FallibleAddStatus(path, success, nullptr) == CHIP_ERROR_INCORRECT_STATE &&
                   handler.status_replies == 1,
               "duplicate logical reply admitted");
  const chip::CommandId data_id = 0;
  unsigned expected_statuses = 1;
  for (const auto error :
       {CHIP_ERROR_BUFFER_TOO_SMALL, CHIP_ERROR_NO_MEMORY, CHIP_ERROR_INVALID_ARGUMENT}) {
    SdkBridgeCommandReply failure(handler, request, chip::Span<const chip::CommandId>(&data_id, 1));
    handler.data_error = error;
    failure.AddResponse(path, 0, payload);
    ReplyRequire(failure.result() == error && failure.replied() &&
                     handler.status_replies == ++expected_statuses &&
                     handler.last_status == Status::Failure && handler.data_replies == 0,
                 "encoding failure hidden by fallback status");
  }
  SdkBridgeCommandReply failed_fallback(handler, request,
                                        chip::Span<const chip::CommandId>(&data_id, 1));
  handler.data_error = CHIP_ERROR_BUFFER_TOO_SMALL;
  handler.status_error = CHIP_ERROR_NO_MEMORY;
  failed_fallback.AddResponse(path, 0, payload);
  ReplyRequire(failed_fallback.result() == CHIP_ERROR_BUFFER_TOO_SMALL &&
                   !failed_fallback.replied() && handler.status_replies == expected_statuses,
               "failed fallback reported as a written reply");
  std::cout << "bridge reply scope and encoding boundaries passed\n" << std::flush;
}

std::vector<std::uint8_t> LogicalArguments(bool scene) {
  std::vector<std::uint8_t> bytes(512);
  chip::TLV::TLVWriter writer;
  writer.Init(bytes.data(), bytes.size());
  chip::TLV::TLVType root;
  ReplyCheck(writer.StartContainer(chip::TLV::AnonymousTag(), chip::TLV::kTLVType_Structure, root),
             "logical arguments");
  ReplyCheck(writer.Put(chip::TLV::ContextTag(0), std::uint16_t(7)), "group argument");
  if (scene) {
    ReplyCheck(writer.Put(chip::TLV::ContextTag(1), std::uint8_t(1)), "scene argument");
    ReplyCheck(writer.Put(chip::TLV::ContextTag(2), std::uint32_t(0)), "transition argument");
    ReplyCheck(writer.PutString(chip::TLV::ContextTag(3), ""), "scene name");
    chip::TLV::TLVType fields;
    ReplyCheck(writer.StartContainer(chip::TLV::ContextTag(4), chip::TLV::kTLVType_Array, fields),
               "scene fields");
    ReplyCheck(writer.EndContainer(fields), "scene fields end");
  } else {
    ReplyCheck(writer.PutString(chip::TLV::ContextTag(1), ""), "group name");
  }
  ReplyCheck(writer.EndContainer(root), "logical arguments end");
  ReplyCheck(writer.Finalize(), "logical arguments finalize");
  bytes.resize(writer.GetLengthWritten());
  return bytes;
}

} // namespace

void VerifyBridgeReplies(SdkBridgeServerBinding &server, BridgeConsumerHandoff &handoff,
                         bool retain_adapter) {
  SdkBridgeEndpointBinding children(server);
  ReplyBoundaries();
  ReplyCheck(children.Init({}), "reply endpoint initialization");
  BridgeEndpoint endpoint;
  ReplyCheck(children.Add({"logical-reply", BridgedDeviceType::OnOffLight, "Logical reply", {}, {}},
                          endpoint),
             "reply endpoint addition");
  ReplyRequire(endpoint.endpoint == 3, "reply endpoint identity");
  auto *group_provider = chip::Credentials::GetGroupDataProvider();
  using Groups = chip::Credentials::GroupDataProvider;
  Groups::KeySet keys(1, Groups::SecurityPolicy::kTrustFirst, 1);
  std::fill(std::begin(keys.epoch_keys[0].key), std::end(keys.epoch_keys[0].key), 0x5a);
  const std::uint8_t compressed_fabric[8]{1, 2, 3, 4, 5, 6, 7, 8};
  ReplyCheck(group_provider->SetKeySet(2, chip::ByteSpan(compressed_fabric), keys),
             "logical fixture keyset");
  ReplyCheck(group_provider->SetGroupKey(2, 7, 1), "logical fixture group key");
  AsyncHandler handler;
  DelegateReply delegate;
  FixtureInvokeGuard guard;
  SdkBridgeInvokeContexts contexts(handoff, guard);
  // Inputs are synthetic principal fixtures. Direct provider calls below do
  // not establish authenticated fabric/ACL or consumer-policy admission.
  for (unsigned phase = 0; phase != 3; ++phase) {
    const bool scene = phase == 1;
    const std::uint64_t now = 100 + phase * 2;
    handler.principal.fabricIndex = 2;
    handler.principal.authMode = chip::Access::AuthMode::kCase;
    handler.principal.subject = 0x1234;
    handler.principal.cats.values[0] = 0x00010002;
    const auto owned_principal = handler.principal;
    chip::app::DataModel::InvokeRequest request(CommandPath(3, scene ? 0x0062 : 0x0004, 0),
                                                handler.principal);
    auto bytes = LogicalArguments(scene);
    chip::TLV::TLVReader reader;
    reader.Init(bytes.data(), bytes.size());
    ReplyCheck(reader.Next(), "logical argument reader");
    BridgeConsumerHandoff::Ticket ticket;
    ReplyCheck(contexts.Start(request, reader, handler, now, now + 500, ticket),
               "logical request retained");
    BridgeInvocation invocation;
    ReplyCheck(contexts.Request(ticket, invocation), "logical request copied");
    handler.principal.fabricIndex = 9;
    handler.principal.subject = 0x9999;
    std::fill(bytes.begin(), bytes.end(), 0xff);
    const chip::CommandId response = 0;
    SdkBridgeCommandReply probe(handler, invocation.request,
                                chip::Span<const chip::CommandId>(&response, 1));
    ReplyRequire(
        probe.GetAccessingFabricIndex() == 2 &&
            probe.GetSubjectDescriptor().subject == owned_principal.subject &&
            probe.GetSubjectDescriptor().cats.values[0] == owned_principal.cats.values[0] &&
            !probe.IsTimedInvoke() && probe.GetExchangeContext() == nullptr,
        "captured metadata replaced");
    probe.FlushAcksRightAwayOnSlowCommand();
    if (retain_adapter) {
      std::cout << "bridge reply child-handle refusal prepared\n" << std::flush;
      CommandHandler::Handle forbidden(&probe);
      throw std::runtime_error("scoped reply retained");
    }
    ReplyRequire(handoff.Resolve(ticket, BridgeConsumerHandoff::Outcome::Completed, now + 1) ==
                     BridgeConsumerHandoff::Reply::Stored,
                 "logical request resolution");
    handler.data_error = phase == 2 ? CHIP_ERROR_BUFFER_TOO_SMALL : CHIP_NO_ERROR;
    const auto responded = contexts.Respond(ticket, now + 1, delegate);
    ReplyRequire(responded == handler.data_error && handler.handles.empty() &&
                     contexts.pending() == 0 && handoff.pending() == 0,
                 "delegated response error or context custody changed");
    if (phase == 2) {
      ReplyRequire(handler.data_replies == 2 && handler.status_replies == 1 &&
                       handler.last_status == Status::Failure,
                   "delegated encoding failure hidden");
      continue;
    }
    ReplyRequire(handler.data_replies == (scene ? 2u : 1u) && handler.status_replies == 0 &&
                     handler.last_path.mEndpointId == 3 &&
                     handler.last_path.mClusterId == request.path.mClusterId &&
                     handler.last_path.mCommandId == 0,
                 "logical command reply changed");
    chip::TLV::TLVReader decoded;
    decoded.Init(handler.response.data(), handler.response.size());
    ReplyCheck(decoded.Next(), "response root");
    chip::TLV::TLVType outer;
    ReplyCheck(decoded.EnterContainer(outer), "response envelope");
    ReplyCheck(decoded.Next(), "response structure");
    chip::TLV::TLVType structure;
    ReplyCheck(decoded.EnterContainer(structure), "response data");
    ReplyCheck(decoded.Next(), "response status");
    std::uint8_t status;
    ReplyCheck(decoded.Get(status), "response status scalar");
    ReplyRequire(status == 0, "logical command refused");
    auto *groups = chip::Credentials::GetGroupDataProvider();
    ReplyRequire(groups->HasEndpoint(2, 7, 3) && !groups->HasEndpoint(9, 7, 3),
                 "logical group stored under wrong fabric");
    if (scene) {
      using Table = chip::scenes::SceneTableBase;
      const Table::SceneStorageId id(1, 7);
      Table::SceneTableEntry entry(id);
      auto *table = chip::scenes::GetSceneTableImpl(3);
      ReplyCheck(table->GetSceneTableEntry(2, id, entry), "captured fabric scene custody");
      ReplyRequire(table->GetSceneTableEntry(9, id, entry) == CHIP_ERROR_NOT_FOUND,
                   "scene stored under asynchronous handler fabric");
    }
  }
  ReplyCheck(contexts.Finish(105), "logical reply shutdown");
  children.Finish();
  std::cout << "bridge captured principal Groups and Scenes replies passed\n" << std::flush;
}

} // namespace wotex::matter::testing
