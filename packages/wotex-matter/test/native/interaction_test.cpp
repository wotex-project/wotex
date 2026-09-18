#include "wotex_matter/interaction.hpp"
#include "wotex_matter/protocol.hpp"

#include <cassert>
#include <optional>
#include <string>

namespace {

// Whether processing a line produced a frame that contains `text`.
bool FrameHas(const wotex::matter::ProcessResult &result, const std::string &text) {
  return result.frame.has_value() && result.frame->find(text) != std::string::npos;
}

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

// The request the backend last received; the test fails when there is none.
const InteractionRequest &Last(const RecordingBackend &backend) {
  assert(backend.last.has_value());
  return *backend.last;
}

std::string OpenFrame() {
  return R"({"version":1,"id":"1","operation":"open","parameters":{"lifecycle":"persistent","storage_path":"/tmp/store","storage_mode":"create_new","authority":"generate_root","vendor_id":65521,"fabric_id":1,"controller_node_id":2,"paa_trust_store":"/tmp/paa"},"timeout_ms":1000})";
}

void Open(HostProtocol &protocol) {
  assert(protocol.ProcessLine(
      R"({"version":1,"event":"flow_open","session_generation":"0123456789abcdef0123456789abcdef"})")
             .keep_running);
  const auto opened = protocol.ProcessLine(OpenFrame());
  assert(opened.keep_running && FrameHas(opened, R"("ok":true)"));
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
  assert(written.keep_running && FrameHas(written, R"("status":0)"));
  assert(backend.interactions == 1 && Last(backend).kind == InteractionKind::Write);
  assert(Last(backend).expected_data_version == 0xFFFFFFFFU);
  assert(Last(backend).timed_request_timeout_ms == 60000U);
  assert(Last(backend).timeout_ms == 60000U);

  auto onoff = protocol.ProcessLine(
      R"({"version":1,"id":"3","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":6,"member":0,"value":{"tag":"anonymous","type":"boolean","value":true}},"timeout_ms":1000})");
  assert(FrameHas(onoff, "invalid_request"));
  assert(backend.interactions == 1);

  auto expired = protocol.ProcessLine(
      R"({"version":1,"id":"4","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":18,"value":{"tag":"anonymous","type":"i16","value":2000},"timed_request_timeout_ms":1001},"timeout_ms":1000})");
  assert(FrameHas(expired, "invalid_request"));
  assert(backend.interactions == 1);

  auto tagged = protocol.ProcessLine(
      R"({"version":1,"id":"5","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":18,"value":{"tag":["context",0],"type":"i16","value":2000}},"timeout_ms":1000})");
  assert(FrameHas(tagged, "invalid_request"));
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
  assert(FrameHas(read, R"("data_version":0)"));
  assert(FrameHas(read, R"("status":126)"));
  assert(FrameHas(read, R"("cluster_status":128)"));
  assert(Last(backend).kind == InteractionKind::ReadAttributes);
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
  assert(FrameHas(events, R"("event_number":18446744073709551615)"));
  assert(FrameHas(events, R"("kind":"epoch")"));
  assert(FrameHas(events, R"("priority":2)"));
  assert(Last(backend).minimum_event_number == 0);
  backend.response.results.clear();
  auto empty = protocol.ProcessLine(
      R"({"version":1,"id":"3","operation":"read_events","parameters":{"paths":[{"fabric_id":1,"node_id":3,"endpoint":2,"cluster":57,"member":3}],"min_event_number":9},"timeout_ms":1000})");
  assert(empty.keep_running);
  assert(FrameHas(empty, R"("result":[])"));
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

void AccessControlWriteCrossesProtocolBoundary() {
  RecordingBackend backend;
  HostProtocol protocol(backend);
  Open(protocol);

  backend.response.ok = true;
  backend.response.response_path = Path(0, 0x001F, 0);
  auto written = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":0,"cluster":31,"member":0,"value":{"tag":"anonymous","type":"array","value":[{"tag":"anonymous","type":"structure","value":[{"tag":["context",1],"type":"u8","value":5},{"tag":["context",2],"type":"u8","value":2},{"tag":["context",3],"type":"array","value":[{"tag":"anonymous","type":"u64","value":999999}]},{"tag":["context",4],"type":"null","value":null}]}]}},"timeout_ms":60000})");

  assert(written.keep_running);
  assert(FrameHas(written, R"("status":0)"));
  assert(backend.interactions == 1);
  const InteractionRequest &request = Last(backend);
  assert(request.kind == InteractionKind::Write);
  assert(request.value.has_value() && request.value->type == ElementType::Array);
  assert(request.value->children.size() == 1U);
}

void MutationResponseIdentity() {
  for (const bool invoke : {false, true}) {
    for (unsigned field = 0; field < (invoke ? 4U : 5U); ++field) {
      RecordingBackend backend;
      HostProtocol protocol(backend);
      Open(protocol);
      ConcretePath path = invoke ? Path(1, 6, 1) : Path(1, 0x0201, 0x12);
      if (field == 0) { path.fabric_id = 2; }
      if (field == 1) { path.node_id = 4; }
      if (field == 2) { path.endpoint = 2; }
      if (field == 3) { path.cluster = 8; }
      if (field == 4) { path.member = 0x11; }
      backend.response.ok = true;
      backend.response.response_path = path;
      if (invoke) {
        Element value;
        value.type = ElementType::Structure;
        backend.response.response_value = value;
      }
      const std::string frame = invoke
          ? R"({"version":1,"id":"2","operation":"invoke","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":6,"member":1,"value":{"tag":"anonymous","type":"structure","value":[]}},"timeout_ms":1000})"
          : R"({"version":1,"id":"2","operation":"write","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":18,"value":{"tag":"anonymous","type":"i16","value":2000}},"timeout_ms":1000})";
      const auto result = protocol.ProcessLine(frame);
      assert(backend.interactions == 1U);
      assert(result.keep_running);
      assert(FrameHas(result, "invalid_backend_result"));
      assert(FrameHas(result, R"("effect":"unknown")"));
    }
  }

  for (unsigned mode = 0; mode < 6U; ++mode) {
    RecordingBackend backend;
    HostProtocol protocol(backend);
    Open(protocol);
    backend.response.ok = true;
    backend.response.response_path = Path(1, 6, 2);
    Element value;
    value.type = ElementType::Structure;
    backend.response.response_value = value;
    if (mode == 0) { backend.response.response_path.reset(); }
    if (mode == 1) { backend.response.response_value.reset(); }
    if (mode == 2) { backend.response.response_value = I16(0); }
    if (mode == 3) {
      backend.response.response_path = Path(1, 6, 0xFFFFU);
    }
    if (mode == 5) {
      backend.response.response_path.reset();
      backend.response.response_value.reset();
    }
    const auto result = protocol.ProcessLine(
        R"({"version":1,"id":"2","operation":"invoke","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":6,"member":1,"value":{"tag":"anonymous","type":"structure","value":[]}},"timeout_ms":1000})");
    assert(result.keep_running && backend.interactions == 1U);
    if (mode >= 4) {
      assert(FrameHas(result, R"("ok":true)"));
    } else {
      assert(FrameHas(result, "invalid_backend_result"));
      assert(FrameHas(result, R"("effect":"unknown")"));
    }
  }
}

} // namespace

int main() {
  for (const std::uint32_t cluster : {0U, 0x7FFFU, 0x0001FC00U, 0x0001FFFEU,
                                      0xFFF1FC05U, 0xFFF4FFFEU}) {
    InteractionRequest request;
    request.kind = InteractionKind::ReadAttributes;
    request.fabric_id = 1;
    request.node_id = 3;
    request.timeout_ms = 1000;
    request.paths = {{1, 3, 1, cluster, 0}};
    assert(valid_interaction_request(request));

    RecordingBackend backend;
    backend.response.ok = false;
    backend.response.error = InteractionError{"unsupported_schema"};
    HostProtocol protocol(backend);
    Open(protocol);
    const auto response = protocol.ProcessLine(
        std::string(R"({"version":1,"id":"2","operation":"read_paths","parameters":{"paths":[{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":)") +
        std::to_string(cluster) + R"(,"member":0}]},"timeout_ms":1000})");
    assert(response.keep_running);
    assert(backend.interactions == 1);
    assert(Last(backend).paths[0].cluster == cluster);
  }
  for (const std::uint32_t cluster : {0x8000U, 0xFC00U, 0xFFFFU, 0x10000U,
                                      0x1FBFFU, 0x1FFFFU, 0xFFF50000U,
                                      0xFFF5FC00U, 0xFFFFFFFFU}) {
    InteractionRequest request;
    request.kind = InteractionKind::ReadAttributes;
    request.fabric_id = 1;
    request.node_id = 3;
    request.timeout_ms = 1000;
    request.paths = {{1, 3, 1, cluster, 0}};
    assert(!valid_interaction_request(request));
    RecordingBackend backend;
    HostProtocol protocol(backend);
    Open(protocol);
    const auto response = protocol.ProcessLine(
        std::string(R"({"version":1,"id":"2","operation":"read_paths","parameters":{"paths":[{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":)") +
        std::to_string(cluster) + R"(,"member":0}]},"timeout_ms":1000})");
    assert(response.keep_running);
    assert(FrameHas(response, "invalid_request"));
    assert(backend.interactions == 0);
  }
  TimedWriteAndLocalRejection();
  AttributeStatusAndDataVersion();
  EventIdentityAndMinimumNumber();
  MutationTimeoutCompletesOnce();
  AccessControlWriteCrossesProtocolBoundary();
  MutationResponseIdentity();
  return 0;
}
