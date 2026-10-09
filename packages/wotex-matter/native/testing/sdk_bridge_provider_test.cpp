#include "sdk_bridge_provider_test.hpp"
#include "sdk_bridge_fixture_guard.hpp"
#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_replies.hpp"

#include <app/MessageDef/AttributeReportIBs.h>
#include <app/InteractionModelEngine.h>
#include <app/EventManagement.h>
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

void ProviderRequire(bool value, const char *stage) {
  if (!value) {
    std::cerr << "bridge provider test failed: " << stage << '\n';
    throw std::runtime_error(stage);
  }
}
void ProviderCheck(CHIP_ERROR error, const char *stage) {
  ProviderRequire(error == CHIP_NO_ERROR, stage);
}

class AsyncHandler final : public CommandHandler {
 public:
  chip::Access::SubjectDescriptor principal;
  std::vector<Handle *> handles;
  unsigned status_replies{0};
  CommandPath last_path{0, 0, 0};
  Status last_status{Status::Failure};

  CHIP_ERROR FallibleAddStatus(const CommandPath &path, const ClusterStatus &status,
                               const char *) override {
    ++status_replies;
    last_path = path;
    last_status = status.GetStatus();
    return CHIP_NO_ERROR;
  }
  void AddStatus(const CommandPath &, const ClusterStatus &, const char *) override {
    throw std::runtime_error("unchecked status forwarded");
  }
  CHIP_ERROR AddResponseData(const CommandPath &, chip::CommandId, const Encodable &) override {
    throw std::runtime_error("unexpected provider data response");
  }
  void AddResponse(const CommandPath &, chip::CommandId, const Encodable &) override {
    throw std::runtime_error("unchecked response forwarded");
  }
  chip::FabricIndex GetAccessingFabricIndex() const override {
    ProviderRequire(handles.empty(), "async fabric query forwarded");
    return principal.fabricIndex;
  }
  chip::Access::SubjectDescriptor GetSubjectDescriptor() const override {
    ProviderRequire(handles.empty(), "async principal query forwarded");
    return principal;
  }
  bool IsTimedInvoke() const override {
    ProviderRequire(handles.empty(), "async timed query forwarded");
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
    ProviderRequire(found != handles.end(), "reply handle released twice");
    handles.erase(found);
  }
};

class ReceiverProbe final : public BridgeReceiver, public ProviderProbe {
 public:
  BridgeConsumerHandoff &handoff;
  FixtureInvokeGuard guard;
  SdkBridgeInvokeContexts contexts;
  BridgeRequestMetadata last;
  BridgeConsumerHandoff::Ticket ticket;
  unsigned reads{0}, writes{0}, invokes{0}, lists{0};
  BridgeReceiver &receiver() override { return *this; }
  void Verify(SdkBridgeServerBinding &server, SdkBridgeProviderBinding &provider,
              chip::app::DataModel::Provider &delegate, const std::string &mode) override;
  explicit ReceiverProbe(BridgeConsumerHandoff &owner) : handoff(owner), contexts(owner, guard) {}
  chip::app::DataModel::ActionReturnStatus Read(BridgeRequestMetadata request,
                                                chip::app::AttributeValueEncoder &) override {
    ++reads;
    last = request;
    return Status::UnsupportedAccess;
  }
  chip::app::DataModel::ActionReturnStatus Write(BridgeRequestMetadata request,
                                                 chip::app::AttributeValueDecoder &) override {
    ++writes;
    last = request;
    return Status::UnsupportedAccess;
  }
  std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(BridgeRequestMetadata metadata,
                                                                 chip::TLV::TLVReader &arguments,
                                                                 CommandHandler *handler) override {
    ++invokes;
    last = metadata;
    if (!handler) return chip::app::DataModel::ActionReturnStatus(CHIP_ERROR_INVALID_ARGUMENT);
    chip::app::DataModel::InvokeRequest request(
        CommandPath(metadata.endpoint, metadata.cluster, metadata.member), metadata.principal);
    request.invokeFlags.Set(chip::app::DataModel::InvokeFlags::kTimed, metadata.timed);
    const auto admitted = contexts.Start(request, arguments, *handler, 100, 600, ticket);
    if (admitted != CHIP_NO_ERROR) return chip::app::DataModel::ActionReturnStatus(admitted);
    return std::nullopt;
  }
  void ListNotification(const chip::app::ConcreteAttributePath &,
                        chip::app::DataModel::ListWriteOperation, chip::FabricIndex) override {
    ++lists;
  }
};

class RoutedCompletion final : public BridgeInvokeReply {
 public:
  CHIP_ERROR Completed(CommandHandler &handler,
                       const BridgeInvocation &invocation) noexcept override {
    SdkBridgeCommandReply reply(handler, invocation.request, chip::Span<const chip::CommandId>());
    reply.AddStatus(CommandPath(invocation.request.endpoint, invocation.request.cluster,
                                invocation.request.member),
                    ClusterStatus(Status::Success));
    return reply.result();
  }
};

class ListenerProbe final : public chip::app::DataModel::AttributeChangeListener {
 public:
  unsigned attributes{0}, endpoints{0};
  void OnAttributeChanged(const chip::app::ConcreteAttributePath &,
                          chip::app::DataModel::AttributeChangeType) override {
    ++attributes;
  }
  void OnEndpointChanged(chip::EndpointId, chip::app::DataModel::EndpointChangeType) override {
    ++endpoints;
  }
};

// This fixture does not start another SDK data model. It supplies explicit
// lifecycle and metadata failures at the borrowed provider boundary.
class FaultDelegate final : public chip::app::CodegenDataModelProvider {
 public:
  CHIP_ERROR startup_error{CHIP_NO_ERROR};
  CHIP_ERROR shutdown_error{CHIP_NO_ERROR};
  unsigned starts{0}, stops{0};
  CHIP_ERROR Startup(chip::app::DataModel::InteractionModelContext) override {
    ++starts;
    return startup_error;
  }
  CHIP_ERROR Shutdown() override {
    ++stops;
    return shutdown_error;
  }
  CHIP_ERROR Endpoints(chip::ReadOnlyBufferBuilder<chip::app::DataModel::EndpointEntry> &) override {
    return CHIP_ERROR_NO_MEMORY;
  }
};

class NoExchangeContext final : public chip::app::DataModel::ActionContext {
 public:
  chip::Messaging::ExchangeContext *CurrentExchange() override { return nullptr; }
};

void ProviderFaults(ReceiverProbe &receiver, chip::app::AttributeValueEncoder &encoder,
                    chip::app::AttributeValueDecoder &decoder,
                    const chip::Access::SubjectDescriptor &principal, chip::TLV::TLVReader &reader,
                    AsyncHandler &handler, const std::string &mode) {
  using namespace chip;
  using namespace chip::app;
  FaultDelegate delegate;
  SdkBridgeProviderBinding provider(delegate, receiver);
  ListenerProbe listener;
  provider.RegisterAttributeChangeListener(listener);
  NoExchangeContext action;
  const DataModel::InteractionModelContext context{EventManagement::GetInstance(), action};
  DataModel::ReadAttributeRequest read(ConcreteAttributePath(3, 6, 0), principal);
  DataModel::WriteAttributeRequest write(ConcreteDataAttributePath(3, 6, 0x4001), principal);
  DataModel::InvokeRequest invoke(CommandPath(3, 6, 1), principal);
  const auto reads = receiver.reads, writes = receiver.writes, invokes = receiver.invokes,
             lists = receiver.lists;
  const auto closed = [&] {
    ProviderRequire(
        provider.ReadAttribute(read, encoder).GetUnderlyingError() == CHIP_ERROR_INCORRECT_STATE &&
            provider.WriteAttribute(write, decoder).GetUnderlyingError() ==
                CHIP_ERROR_INCORRECT_STATE,
        "inactive provider served child attributes");
    const auto status = provider.InvokeCommand(invoke, reader, &handler);
    ProviderRequire(status && status->GetUnderlyingError() == CHIP_ERROR_INCORRECT_STATE,
                    "inactive provider admitted child invoke");
    provider.ListAttributeWriteNotification(read.path,
                                            DataModel::ListWriteOperation::kListWriteBegin, 2);
    ProviderRequire(receiver.reads == reads && receiver.writes == writes &&
                        receiver.invokes == invokes && receiver.lists == lists,
                    "refused provider reached receiver");
  };
  closed();
  if (mode == "provider_startup_failure") {
    delegate.startup_error = CHIP_ERROR_NO_MEMORY;
    std::cout << "bridge provider partial startup refusal prepared\n" << std::flush;
  }
  ProviderCheck(provider.Startup(context), "fault provider startup");
  ProviderRequire(provider.Startup(context) == CHIP_ERROR_INCORRECT_STATE && delegate.starts == 1,
                  "active provider restarted delegate");
  delegate.NotifyAttributeChanged(read.path, DataModel::AttributeChangeType::kReportable);
  ProviderRequire(listener.attributes == 1, "active provider did not forward notification");
  ProviderRequire(
      provider.ReadAttribute(read, encoder).GetUnderlyingError() == CHIP_ERROR_NO_MEMORY &&
          provider.WriteAttribute(write, decoder).GetUnderlyingError() == CHIP_ERROR_NO_MEMORY,
      "metadata allocation failure became endpoint absence");
  const auto status = provider.InvokeCommand(invoke, reader, &handler);
  ProviderRequire(status && status->GetUnderlyingError() == CHIP_ERROR_NO_MEMORY,
                  "metadata allocation failure admitted child invoke");
  provider.ListAttributeWriteNotification(read.path, DataModel::ListWriteOperation::kListWriteBegin,
                                          2);
  ProviderRequire(receiver.reads == reads && receiver.writes == writes &&
                      receiver.invokes == invokes && receiver.lists == lists,
                  "metadata failure reached receiver");
  if (mode == "provider_missing_finish") {
    std::cout << "bridge provider missing shutdown refusal prepared\n" << std::flush;
    return;
  }
  if (mode == "provider_shutdown_failure") {
    delegate.shutdown_error = CHIP_ERROR_INTERNAL;
    std::cout << "bridge provider failed shutdown refusal prepared\n" << std::flush;
  }
  ProviderCheck(provider.Shutdown(), "fault provider shutdown");
  ProviderCheck(provider.Shutdown(), "idempotent provider shutdown");
  ProviderRequire(delegate.stops == 1 && provider.Startup(context) == CHIP_ERROR_INCORRECT_STATE &&
                      delegate.starts == 1,
                  "closed provider reopened its borrowed context");
  delegate.NotifyAttributeChanged(read.path, DataModel::AttributeChangeType::kReportable);
  ProviderRequire(listener.attributes == 1, "closed provider retained delegate listener");
  closed();
  provider.UnregisterAttributeChangeListener(listener);
}

void VerifyProviderFixture(SdkBridgeServerBinding &server, SdkBridgeProviderBinding &provider,
                           chip::app::DataModel::Provider &underlying, ReceiverProbe &receiver,
                           const std::string &mode) {
  using namespace chip;
  using namespace chip::app;
  ProviderRequire(InteractionModelEngine::GetInstance()->GetDataModelProvider() == &provider,
                  "wrapper is not the installed SDK provider");
  SdkBridgeEndpointBinding children(server);
  ProviderCheck(children.Init({}), "provider children initialized");
  BridgeEndpoint endpoint;
  ProviderCheck(
      children.Add({"provider-light", BridgedDeviceType::OnOffLight, "Provider light", {}, {}},
                   endpoint),
      "provider child added");
  ProviderCheck(children.Observe("provider-light", endpoint.endpoint, {true, false, {}}),
                "provider approved state");
  ListenerProbe listener;
  provider.RegisterAttributeChangeListener(listener);
  underlying.NotifyAttributeChanged({3, 6, 0}, DataModel::AttributeChangeType::kReportable);
  underlying.NotifyEndpointChanged(3, DataModel::EndpointChangeType::kAdded);
  ProviderRequire(listener.attributes == 1 && listener.endpoints == 1,
                  "delegate notifications did not cross wrapper");

  std::uint8_t bytes[512];
  TLV::TLVWriter writer;
  writer.Init(bytes);
  AttributeReportIBs::Builder reports;
  ProviderCheck(reports.Init(&writer), "provider reports");
  Access::SubjectDescriptor principal;
  principal.fabricIndex = 2;
  principal.authMode = Access::AuthMode::kCase;
  principal.subject = 42;
  const ConcreteAttributePath path(3, 6, 0);
  AttributeValueEncoder encoder(reports, principal, path, 0);
  DataModel::ReadAttributeRequest read(path, principal);
  read.readFlags.Set(DataModel::ReadFlags::kFabricFiltered);
  ProviderRequire(provider.ReadAttribute(read, encoder).GetStatusCode().GetStatus() ==
                          Status::UnsupportedAccess &&
                      receiver.reads == 1 && receiver.last.principal.fabricIndex == 2 &&
                      receiver.last.fabric_filtered,
                  "child read bypassed explicit receiver");
  principal.fabricIndex = 9;
  ProviderRequire(receiver.last.principal.fabricIndex == 2, "receiver borrowed principal");
  DataModel::ReadAttributeRequest unknown(ConcreteAttributePath(4, 6, 0), principal);
  ProviderRequire(provider.ReadAttribute(unknown, encoder).GetStatusCode().GetStatus() ==
                          Status::UnsupportedEndpoint &&
                      receiver.reads == 1,
                  "unknown endpoint reached receiver");
  DataModel::ReadAttributeRequest dummy(ConcreteAttributePath(2, 6, 0), principal);
  ProviderRequire(provider.ReadAttribute(dummy, encoder).GetStatusCode().GetStatus() ==
                          Status::UnsupportedEndpoint &&
                      receiver.reads == 1,
                  "disabled model endpoint reached receiver");
  const ConcreteAttributePath root_path(1, 0x001d, 0xfffd);
  AttributeValueEncoder root_encoder(reports, principal, root_path, 0);
  DataModel::ReadAttributeRequest root_read(root_path, principal);
  ProviderRequire(
      provider.ReadAttribute(root_read, root_encoder).IsSuccess() && receiver.reads == 1,
      "root metadata did not delegate");

  const std::uint8_t scalar[]{0x04, 1};
  TLV::TLVReader scalar_reader;
  scalar_reader.Init(scalar);
  ProviderCheck(scalar_reader.Next(), "write scalar");
  AttributeValueDecoder decoder(scalar_reader, principal);
  DataModel::WriteAttributeRequest write(ConcreteDataAttributePath(3, 6, 0x4001), principal);
  write.writeFlags.Set(DataModel::WriteFlags::kTimed);
  ProviderRequire(provider.WriteAttribute(write, decoder).GetStatusCode().GetStatus() ==
                          Status::UnsupportedAccess &&
                      receiver.writes == 1 && receiver.last.timed && !decoder.TriedDecode(),
                  "child write reached native storage before receiver admission");
  provider.ListAttributeWriteNotification(path, DataModel::ListWriteOperation::kListWriteBegin, 2);
  ProviderRequire(receiver.lists == 1, "child list lifecycle lost");

  AsyncHandler handler;
  handler.principal.fabricIndex = 2;
  handler.principal.subject = 42;
  handler.principal.authMode = Access::AuthMode::kCase;
  DataModel::InvokeRequest invoke(CommandPath(3, 6, 1), handler.principal);
  const std::uint8_t arguments[]{0x15, 0x18};
  TLV::TLVReader reader;
  reader.Init(arguments);
  ProviderCheck(reader.Next(), "invoke arguments");
  ProviderRequire(!provider.InvokeCommand(invoke, reader, &handler) && receiver.invokes == 1 &&
                      handler.handles.size() == 1 && handler.status_replies == 0,
                  "retained child invocation returned automatic Success");
  ProviderRequire(
      receiver.handoff.Resolve(receiver.ticket, BridgeConsumerHandoff::Outcome::Completed, 101) ==
          BridgeConsumerHandoff::Reply::Stored,
      "explicit consumer fixture resolution failed");
  RoutedCompletion completion;
  ProviderCheck(receiver.contexts.Respond(receiver.ticket, 101, completion), "routed completion");
  ProviderRequire(handler.handles.empty() && handler.status_replies == 1,
                  "routed handle not released");
  EmberAfAttributeMetadata attribute{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
  attribute.attributeId = 0;
  std::uint8_t approved = 0xA5;
  ProviderRequire(
      SdkBridgeEndpointBinding::ReadExternal(3, 6, &attribute, &approved, 1) == Status::Success &&
          approved == 0,
      "queued command or status reply changed approved Property state");
  ProviderFaults(receiver, encoder, decoder, principal, reader, handler, mode);
  provider.UnregisterAttributeChangeListener(listener);
  ProviderCheck(receiver.contexts.Finish(101), "provider request shutdown");
  children.Finish();
  std::cout << "installed SDK provider routing and notifications passed\n" << std::flush;
}


void ReceiverProbe::Verify(SdkBridgeServerBinding &server, SdkBridgeProviderBinding &provider,
                           chip::app::DataModel::Provider &delegate, const std::string &mode) {
  VerifyProviderFixture(server, provider, delegate, *this, mode);
}

} // namespace

std::unique_ptr<ProviderProbe> PrepareProvider(BridgeConsumerHandoff &handoff) {
  return std::make_unique<ReceiverProbe>(handoff);
}

} // namespace wotex::matter::testing
