#include "wotex_matter/protocol.hpp"
#include "wotex_matter/subscription.hpp"

#include <cassert>
#include <optional>
#include <string>
#include <vector>

namespace {

using namespace wotex::matter;

constexpr char kSessionGeneration[] =
    "0123456789abcdef0123456789abcdef";
constexpr char kSubscriptionId[] =
    "abcdef0123456789abcdef0123456789";

ConcretePath Path() { return {1, 3, 1, 0x0201, 0}; }

PathSelector Selector() {
  return {1, 3, std::uint16_t{1}, std::uint32_t{0x0201}, std::uint32_t{0}};
}

Element Temperature() {
  Element value;
  value.type = ElementType::I16;
  value.signed_value = 2150;
  return value;
}

PathResult Attribute(std::uint32_t version) {
  PathResult result;
  result.path = Path();
  result.attribute = AttributeData{result.path, Temperature(), version};
  return result;
}

PathResult Event(std::uint64_t number) {
  PathResult result;
  result.path = {1, 3, 2, 0x0039, 3};
  Element value;
  value.type = ElementType::Structure;
  result.event = EventData{result.path, value, number, 1,
                           EventData::TimestampKind::System, 10};
  return result;
}

SubscriptionRequest Request() {
  SubscriptionRequest request;
  request.subscription_id = kSubscriptionId;
  request.kind = SubscriptionKind::Attribute;
  request.fabric_id = 1;
  request.node_id = 3;
  request.paths = {Selector()};
  request.min_interval_s = 1;
  request.max_interval_s = 60;
  request.queue_limit = 64;
  request.timeout_ms = 1000;
  return request;
}

class RecordingBackend final : public ControllerBackend {
 public:
  BackendResult Open(const NativeOpenOptions &) override {
    open = true;
    return {true, {}};
  }

  InteractionResponse Interact(const InteractionRequest &) override {
    return {false, InteractionError{"unexpected"}};
  }

  void SetSubscriptionSinks(ReportSink report, StatusSink status,
                            FailureSink failure) override {
    report_sink = std::move(report);
    status_sink = std::move(status);
    failure_sink = std::move(failure);
  }

  SubscriptionResponse Subscribe(const SubscriptionRequest &request) override {
    ++subscribe_calls;
    last = request;
    return {true, {}, request.subscription_id, 1, 2, 45, 73};
  }

  bool ActivateSubscription(const std::string &id,
                            std::uint64_t generation) override {
    ++activate_calls;
    if (id != kSubscriptionId || generation != 1 || !report_sink) {
      return false;
    }
    SubscriptionReport first{id, generation, SubscriptionKind::Attribute,
                             Attribute(7), true, 1, 2, 45, 73};
    SubscriptionReport second{id, generation, SubscriptionKind::Attribute,
                              Attribute(8), false, 2, 2, 45, 73};
    return report_sink(first) && report_sink(second);
  }

  BackendResult CancelSubscription(const std::string &id,
                                   std::uint64_t generation,
                                   std::uint32_t) override {
    ++cancel_calls;
    return {id == kSubscriptionId && generation > 0,
            id == kSubscriptionId && generation > 0 ? "" : "invalid_subscription"};
  }

  void Close() override { open = false; }
  bool IsOpen() const override { return open; }

  ReportSink report_sink;
  StatusSink status_sink;
  FailureSink failure_sink;
  SubscriptionRequest last;
  unsigned subscribe_calls{0};
  unsigned activate_calls{0};
  unsigned cancel_calls{0};
  bool open{false};
};

std::string OpenFrame() {
  return R"({"version":1,"id":"1","operation":"open","parameters":{"lifecycle":"persistent","storage_path":"/tmp/store","storage_mode":"create_new","authority":"generate_root","vendor_id":65521,"fabric_id":1,"controller_node_id":2,"paa_trust_store":"/tmp/paa"},"timeout_ms":1000})";
}

void Open(HostProtocol &protocol) {
  assert(protocol.ProcessLine(
      R"({"version":1,"event":"flow_open","session_generation":"0123456789abcdef0123456789abcdef"})")
             .keep_running);
  assert(protocol.ProcessLine(OpenFrame()).frame->find(R"("ok":true)") !=
         std::string::npos);
}

void InitialReportsPreserveIdentityAndCancel() {
  SubscriptionBuffer buffer(Request());
  assert(buffer.Establish(73, 2, 45));
  buffer.Activate();
  buffer.BeginReport();
  assert(buffer.Add(Attribute(7)));
  buffer.EndReport();
  buffer.BeginReport();
  assert(buffer.Add(Attribute(8)));
  buffer.EndReport();
  auto reports = buffer.TakeReady();
  assert(reports.size() == 2);
  assert(reports[0].result.attribute->value.signed_value == 2150);
  assert(reports[1].result.attribute->value.signed_value == 2150);
  assert(reports[0].report_id == 1 && reports[1].report_id == 2);
  assert(reports[0].result.attribute->data_version == 7);
  assert(reports[1].result.attribute->data_version == 8);
  assert(reports[0].min_interval_s == 2 && reports[0].max_interval_s == 45);

  buffer.Cancel();
  buffer.BeginReport();
  assert(!buffer.Add(Attribute(9)));
  assert(buffer.TakeReady().empty());
}

void InitialSnapshotAndEventDuplicatesAreSuppressedByIdentity() {
  SubscriptionBuffer initial(Request());
  initial.BeginReport();
  assert(initial.Add(Attribute(7)));
  initial.EndReport();
  initial.BeginReport();
  assert(initial.Add(Attribute(8)));
  initial.EndReport();
  assert(initial.Establish(73, 2, 45));
  initial.Activate();
  assert(initial.TakeReady().size() == 1);

  SubscriptionRequest request = Request();
  request.kind = SubscriptionKind::Event;
  request.paths = {{1, 3, std::uint16_t{2}, std::uint32_t{0x0039},
                    std::uint32_t{3}}};
  SubscriptionBuffer events(request);
  assert(events.Establish(74, 1, 60));
  events.Activate();
  PathResult event;
  event.path = {1, 3, 2, 0x0039, 3};
  Element value;
  value.type = ElementType::Structure;
  event.event = EventData{event.path, value, 9, 1,
                          EventData::TimestampKind::System, 10};
  events.BeginReport();
  assert(events.Add(event));
  events.EndReport();
  events.BeginReport();
  assert(events.Add(event));
  events.EndReport();
  assert(events.TakeReady().size() == 1);
}

void RecoveryGenerationResetsSnapshotIdentityButRetainsEventIdentity() {
  SubscriptionBuffer buffer(Request());
  assert(buffer.Establish(73, 2, 45));
  buffer.Activate();
  assert(buffer.PrepareRecovery(2));
  buffer.BeginReport();
  assert(buffer.Add(Attribute(8)));
  buffer.EndReport();
  assert(buffer.TakeReady().empty());
  assert(buffer.Establish(74, 3, 30));
  buffer.Activate();
  auto reports = buffer.TakeReady();
  assert(reports.size() == 1);
  assert(reports[0].generation == 2);
  assert(reports[0].initial);
  assert(reports[0].report_id == 1);
  assert(reports[0].min_interval_s == 3);
  assert(reports[0].max_interval_s == 30);
  assert(reports[0].sdk_subscription_id == 74);

  SubscriptionRequest event_request = Request();
  event_request.kind = SubscriptionKind::Event;
  event_request.paths = {{1, 3, std::uint16_t{2}, std::uint32_t{0x0039},
                          std::uint32_t{3}}};
  SubscriptionBuffer events(event_request);
  assert(events.Establish(75, 1, 60));
  events.Activate();
  events.BeginReport();
  assert(events.Add(Event(9)));
  events.EndReport();
  assert(events.TakeReady().size() == 1);
  assert(events.PrepareRecovery(2));
  events.BeginReport();
  assert(events.Add(Event(9)));
  assert(events.Add(Event(10)));
  events.EndReport();
  assert(events.Establish(76, 2, 40));
  events.Activate();
  auto recovered_events = events.TakeReady();
  assert(recovered_events.size() == 1);
  assert(recovered_events[0].result.event->event_number == 10);
  assert(recovered_events[0].generation == 2);
}

void RecoveryBudgetIsOptInAndBounded() {
  SubscriptionRecovery disabled(false);
  assert(disabled.Next(100).action == SubscriptionRecovery::Action::Disabled);

  SubscriptionRecovery recovery(true);
  for (std::uint8_t attempt = 1; attempt <= 5; ++attempt) {
    const auto decision = recovery.Next(100 + attempt - 1);
    assert(decision.action == SubscriptionRecovery::Action::Retry);
    assert(decision.generation == 2);
    assert(decision.attempt == attempt);
    assert(decision.remaining_ms ==
           60001U - static_cast<std::uint32_t>(attempt));
  }
  assert(recovery.Next(105).action == SubscriptionRecovery::Action::Exhausted);

  SubscriptionRecovery deadline(true);
  assert(deadline.Next(500).action == SubscriptionRecovery::Action::Retry);
  assert(deadline.Next(60500).action == SubscriptionRecovery::Action::Exhausted);

  SubscriptionRecovery successive(true);
  assert(successive.Next(1).generation == 2);
  successive.Established();
  const auto next = successive.Next(2);
  assert(next.action == SubscriptionRecovery::Action::Retry);
  assert(next.generation == 3);
  assert(next.attempt == 1);
}

void CreditsBoundAndAcknowledgeExactBytes() {
  std::vector<std::string> transmitted;
  ReportCreditManager flow(kSessionGeneration, [&](const std::string &frame) {
    transmitted.push_back(frame);
    return true;
  });
  assert(flow.AddStream("s1", 1, 64));
  for (unsigned index = 0; index < 17; ++index) {
    const auto result = flow.Submit("s1", 1, [](std::uint64_t) {
      return std::string(127, 'x');
    });
    assert(result == (index < 16 ? ReportCreditManager::SubmitResult::Transmitted
                                 : ReportCreditManager::SubmitResult::Queued));
  }
  assert(transmitted.size() == 16);
  assert(!flow.Acknowledge(1, 129));
  assert(flow.Acknowledge(1, 128));
  assert(transmitted.size() == 17);
  assert(!flow.Acknowledge(1, 128));
}

void RetiringQueuedReportsDoesNotCreateASequenceGap() {
  std::vector<std::string> transmitted;
  ReportCreditManager flow(kSessionGeneration, [&](const std::string &frame) {
    transmitted.push_back(frame);
    return true;
  });
  assert(flow.AddStream("s1", 1, 1));
  assert(flow.AddStream("s2", 1, 1));
  auto encode = [](std::uint64_t sequence) { return std::to_string(sequence); };
  assert(flow.Submit("s1", 1, encode) ==
         ReportCreditManager::SubmitResult::Transmitted);
  assert(flow.Submit("s1", 1, encode) ==
         ReportCreditManager::SubmitResult::Queued);
  assert(flow.Submit("s2", 1, encode) ==
         ReportCreditManager::SubmitResult::Queued);
  assert(flow.Retire("s1", 1, "barrier"));
  assert(transmitted == std::vector<std::string>({"1", "barrier", "2"}));
}

void ProtocolEstablishesBeforeDeliveryAndRetires() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  std::vector<std::string> asynchronous;
  protocol.SetOutputSink([&](const std::string &frame) {
    asynchronous.push_back(frame);
    return true;
  });
  Open(protocol);

  auto subscribed = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"subscribe","parameters":{"subscription_id":"abcdef0123456789abcdef0123456789","kind":"attribute","paths":[{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0}],"min_interval_s":1,"max_interval_s":60,"resubscribe":true,"queue_limit":64},"timeout_ms":1000})");
  assert(subscribed.keep_running && subscribed.frame.has_value());
  assert(subscribed.frame->find(R"("min_interval_s":2)") != std::string::npos);
  assert(asynchronous.empty());
  assert(subscribed.activate_subscription.has_value());
  assert(protocol.ActivateSubscription(subscribed.activate_subscription->first,
                                       subscribed.activate_subscription->second));
  assert(asynchronous.size() == 2);
  assert(asynchronous[0].find(R"("data_version":7)") != std::string::npos);
  assert(asynchronous[1].find(R"("data_version":8)") != std::string::npos);
  assert(asynchronous[0].find(R"("value":2150)") != std::string::npos);
  assert(asynchronous[1].find(R"("value":2150)") != std::string::npos);

  std::uint64_t acknowledged = asynchronous[0].size() + 1;
  auto ack = protocol.ProcessLine(
      std::string(R"({"version":1,"event":"report_ack","session_generation":"0123456789abcdef0123456789abcdef","report_sequence":1,"acknowledged_bytes":)") +
      std::to_string(acknowledged) + "}");
  assert(ack.keep_running && !ack.frame.has_value());

  acknowledged += asynchronous[1].size() + 1;
  ack = protocol.ProcessLine(
      std::string(R"({"version":1,"event":"report_ack","session_generation":"0123456789abcdef0123456789abcdef","report_sequence":2,"acknowledged_bytes":)") +
      std::to_string(acknowledged) + "}");
  assert(ack.keep_running);

  assert(backend.status_sink(
      {kSubscriptionId, 2, SubscriptionStatusKind::Resubscribing,
       SubscriptionContinuity::Lost, 1}));
  assert(asynchronous.size() == 4);
  assert(asynchronous[2].find(R"("status":"resubscribing")") !=
         std::string::npos);
  assert(asynchronous[2].find(R"("generation":2)") != std::string::npos);
  assert(asynchronous[3].find(R"("event":"stream_retired")") !=
         std::string::npos);
  assert(asynchronous[3].find(R"("generation":1)") != std::string::npos);

  assert(!backend.status_sink(
      {kSubscriptionId, 2, SubscriptionStatusKind::Resubscribing,
       SubscriptionContinuity::Lost, 3}));
  assert(backend.status_sink(
      {kSubscriptionId, 2, SubscriptionStatusKind::Resubscribing,
       SubscriptionContinuity::Lost, 2}));
  assert(asynchronous.size() == 5);
  assert(asynchronous.back().find(R"("attempt":2)") != std::string::npos);

  assert(backend.status_sink(
      {kSubscriptionId, 2, SubscriptionStatusKind::Resubscribed,
       SubscriptionContinuity::Unknown, 2, 3, 30, 74}));
  assert(asynchronous.size() == 6);
  assert(asynchronous.back().find(R"("status":"resubscribed")") !=
         std::string::npos);
  assert(asynchronous.back().find(R"("continuity":"unknown")") !=
         std::string::npos);

  SubscriptionReport recovered{kSubscriptionId, 2,
                               SubscriptionKind::Attribute, Attribute(9),
                               true, 1, 3, 30, 74};
  assert(backend.report_sink(recovered));
  assert(asynchronous.size() == 7);
  assert(asynchronous.back().find(R"("generation":2)") != std::string::npos);

  auto cancelled = protocol.ProcessLine(
      R"({"version":1,"id":"3","operation":"unsubscribe","parameters":{"subscription_id":"abcdef0123456789abcdef0123456789","generation":2},"timeout_ms":1000})");
  assert(cancelled.keep_running && cancelled.frame->find(R"("ok":true)") !=
         std::string::npos);
  assert(asynchronous.size() == 8);
  assert(asynchronous.back().find(R"("event":"stream_retired")") !=
         std::string::npos);
  assert(backend.cancel_calls == 1);

  SubscriptionReport late{kSubscriptionId, 2, SubscriptionKind::Attribute,
                          Attribute(9), false, 3, 2, 45, 73};
  assert(!backend.report_sink(late));
}

void DefaultLossIsTerminalWithoutRecovery() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  std::vector<std::string> asynchronous;
  protocol.SetOutputSink([&](const std::string &frame) {
    asynchronous.push_back(frame);
    return true;
  });
  Open(protocol);

  auto subscribed = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"subscribe","parameters":{"subscription_id":"abcdef0123456789abcdef0123456789","kind":"attribute","paths":[{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0}],"min_interval_s":1,"max_interval_s":60,"resubscribe":false,"queue_limit":64},"timeout_ms":1000})");
  assert(subscribed.keep_running && subscribed.frame.has_value());
  assert(!backend.last.resubscribe);
  assert(!backend.status_sink(
      {kSubscriptionId, 2, SubscriptionStatusKind::Resubscribing,
       SubscriptionContinuity::Lost, 1}));
  backend.failure_sink(kSubscriptionId, 1, InteractionError{"session_lost"});
  assert(asynchronous.size() == 2);
  assert(asynchronous[0].find(R"("event":"subscription_error")") !=
         std::string::npos);
  assert(asynchronous[0].find(R"("code":"session_lost")") !=
         std::string::npos);
  assert(asynchronous[1].find(R"("event":"stream_retired")") !=
         std::string::npos);
  SubscriptionReport late{kSubscriptionId, 1, SubscriptionKind::Attribute,
                          Attribute(9), false, 1, 2, 45, 73};
  assert(!backend.report_sink(late));
}

void InvalidSubscriptionNeverEntersBackend() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  Open(protocol);
  auto invalid = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"subscribe","parameters":{"subscription_id":"abcdef0123456789abcdef0123456789","kind":"attribute","paths":[{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0}],"min_interval_s":61,"max_interval_s":60,"resubscribe":false,"queue_limit":64},"timeout_ms":1000})");
  assert(invalid.frame->find("invalid_request") != std::string::npos);
  assert(backend.subscribe_calls == 0);
}

} // namespace

int main() {
  InitialReportsPreserveIdentityAndCancel();
  InitialSnapshotAndEventDuplicatesAreSuppressedByIdentity();
  RecoveryGenerationResetsSnapshotIdentityButRetainsEventIdentity();
  RecoveryBudgetIsOptInAndBounded();
  CreditsBoundAndAcknowledgeExactBytes();
  RetiringQueuedReportsDoesNotCreateASequenceGap();
  ProtocolEstablishesBeforeDeliveryAndRetires();
  DefaultLossIsTerminalWithoutRecovery();
  InvalidSubscriptionNeverEntersBackend();
  return 0;
}
