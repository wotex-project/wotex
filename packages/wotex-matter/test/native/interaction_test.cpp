#include "wotex_matter/interaction.hpp"
#include "wotex_matter/protocol.hpp"

#include <cassert>
#include <optional>
#include <string>

namespace {

using namespace wotex::matter;

class RecordingBackend final : public ControllerBackend {
 public:
  BackendResult Open(const NativeOpenOptions &) override {
    open = true;
    return {true, {}};
  }

  InteractionResponse Interact(const InteractionRequest &request) override {
    ++interactions;
    last = request;
    return response;
  }

  void Close() override { open = false; }
  bool IsOpen() const override { return open; }

  InteractionResponse response;
  std::optional<InteractionRequest> last;
  unsigned interactions{0};
  bool open{false};
};

std::string OpenFrame() {
  return R"({"version":1,"id":"1","operation":"open","parameters":{"lifecycle":"persistent","storage_path":"/tmp/store","storage_mode":"create_new","authority":"generate_root","vendor_id":65521,"fabric_id":1,"controller_node_id":2,"paa_trust_store":"/tmp/paa"},"timeout_ms":1000})";
}

void Open(HostProtocol &protocol) {
  assert(protocol.ProcessLine(
      R"({"version":1,"event":"flow_open","session_generation":"0123456789abcdef0123456789abcdef"})")
             .keep_running);
  const auto opened = protocol.ProcessLine(OpenFrame());
  assert(opened.keep_running && opened.frame->find(R"("ok":true)") != std::string::npos);
}

ConcretePath Path(std::uint16_t endpoint, std::uint32_t cluster,
                  std::uint32_t member) {
  return {1, 3, endpoint, cluster, member};
}

Element Boolean(bool value) {
  Element element;
  element.type = ElementType::Boolean;
  element.boolean_value = value;
  return element;
}

Element I16(std::int16_t value) {
  Element element;
  element.type = ElementType::I16;
  element.signed_value = value;
  return element;
}

Element Reachable(bool value) {
  Element element;
  element.type = ElementType::Structure;
  Element child = Boolean(value);
  child.tag = {TagKind::Context, 0};
  element.children.push_back(child);
  return element;
}

void TimedWriteAndLocalRejection() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  Open(protocol);

  backend.response.ok = true;
  backend.response.response_path = Path(1, 0x0201, 0x0012);
  auto written = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":18,"value":{"tag":"anonymous","type":"i16","value":2000},"expected_data_version":4294967295,"timed_request_timeout_ms":60000},"timeout_ms":60000})");
  assert(written.keep_running && written.frame->find(R"("status":0)") != std::string::npos);
  assert(backend.interactions == 1 && backend.last->kind == InteractionKind::Write);
  assert(backend.last->expected_data_version == 0xFFFFFFFFU);
  assert(backend.last->timed_request_timeout_ms == 60000U);
  assert(backend.last->timeout_ms == 60000U);

  auto onoff = protocol.ProcessLine(
      R"({"version":1,"id":"3","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":6,"member":0,"value":{"tag":"anonymous","type":"boolean","value":true}},"timeout_ms":1000})");
  assert(onoff.frame->find("invalid_request") != std::string::npos);
  assert(backend.interactions == 1);

  auto expired = protocol.ProcessLine(
      R"({"version":1,"id":"4","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":18,"value":{"tag":"anonymous","type":"i16","value":2000},"timed_request_timeout_ms":1001},"timeout_ms":1000})");
  assert(expired.frame->find("invalid_request") != std::string::npos);
  assert(backend.interactions == 1);

  auto tagged = protocol.ProcessLine(
      R"({"version":1,"id":"5","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":18,"value":{"tag":["context",0],"type":"i16","value":2000}},"timeout_ms":1000})");
  assert(tagged.frame->find("invalid_request") != std::string::npos);
  assert(backend.interactions == 1);
}

void AttributeStatusAndDataVersion() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  Open(protocol);

  backend.response.ok = true;
  backend.response.results = {
      {Path(1, 0x0201, 0), AttributeData{Path(1, 0x0201, 0), I16(2150), 0},
       std::nullopt, std::nullopt},
      {Path(2, 6, 0), std::nullopt, std::nullopt,
       InteractionError{"interaction_status", 0x7EU, 0x80U,
                        InteractionEffect::None}}};

  auto read = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"read_paths","parameters":{"paths":[{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0},{"fabric_id":1,"node_id":3,"endpoint":2,"cluster":6,"member":0}]},"timeout_ms":1000})");
  assert(read.keep_running);
  assert(read.frame->find(R"("data_version":0)") != std::string::npos);
  assert(read.frame->find(R"("status":126)") != std::string::npos);
  assert(read.frame->find(R"("cluster_status":128)") != std::string::npos);
  assert(backend.last->kind == InteractionKind::ReadAttributes);
}

void EventIdentityAndMinimumNumber() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  Open(protocol);

  const ConcretePath event_path = Path(2, 0x0039, 3);
  backend.response.ok = true;
  backend.response.results = {
      {event_path, std::nullopt,
       EventData{event_path, Reachable(false), 0xFFFFFFFFFFFFFFFFULL, 2,
                 EventData::TimestampKind::Epoch, 17},
       std::nullopt}};

  auto events = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"read_events","parameters":{"paths":[{"fabric_id":1,"node_id":3,"endpoint":2,"cluster":57,"member":3}],"min_event_number":0},"timeout_ms":1000})");
  assert(events.keep_running);
  assert(events.frame->find(R"("event_number":18446744073709551615)") != std::string::npos);
  assert(events.frame->find(R"("kind":"epoch")") != std::string::npos);
  assert(events.frame->find(R"("priority":2)") != std::string::npos);
  assert(backend.last->minimum_event_number == 0);
}

void MutationTimeoutCompletesOnce() {
  MutationCompletion completion;
  assert(completion.Submit());
  assert(!completion.Submit());
  assert(completion.submitted());
  assert(completion.Timeout());
  assert(completion.completed());
  assert(!completion.Complete());
  assert(!completion.Timeout());
  assert(remaining_timeout_ms(1000, 999) == 1);
  assert(remaining_timeout_ms(1000, 1000) == 0);
  assert(remaining_timeout_ms(1000, 2000) == 0);
}

} // namespace

int main() {
  TimedWriteAndLocalRejection();
  AttributeStatusAndDataVersion();
  EventIdentityAndMinimumNumber();
  MutationTimeoutCompletesOnce();
  return 0;
}
