#include "wotex_matter/protocol.hpp"

#include <cassert>
#include <string>

namespace {

class CommissioningBackend final : public wotex::matter::ControllerBackend {
 public:
  wotex::matter::BackendResult Open(
      const wotex::matter::NativeOpenOptions &options) override {
    fabric_id = options.fabric_id;
    open = true;
    return {true, {}};
  }

  wotex::matter::InteractionResponse Interact(
      const wotex::matter::InteractionRequest &) override {
    return {false, wotex::matter::InteractionError{
                       "interaction_status", 126U, std::nullopt,
                       wotex::matter::InteractionEffect::None}};
  }

  wotex::matter::CommissioningResponse Commission(
      const wotex::matter::CommissioningRequest &request) override {
    commissioning = request;
    if (malformed_result) {
      return {true, std::nullopt, request.node_id + 1, fabric_id, true};
    }
    if (commissioning_failure) {
      return {false,
              wotex::matter::CommissioningError{
                  "commissioning_failed", 0xF1230001U,
                  wotex::matter::InteractionEffect::Unknown},
              0, 0, false};
    }
    return {true, std::nullopt, request.node_id, fabric_id, true};
  }

  wotex::matter::CommissioningWindowResponse OpenWindow(
      const wotex::matter::CommissioningWindowRequest &request) override {
    window = request;
    if (malformed_result) {
      return {true, std::nullopt, request.node_id + 1, 20202021U,
              request.discriminator, request.timeout_s, "34970112332",
              "MT:Y.K9042C00KA0648G00"};
    }
    if (window_failure) {
      return {false,
              wotex::matter::CommissioningError{
                  "window_failed", 0xF1230002U,
                  wotex::matter::InteractionEffect::Unknown},
              0, 0, 0, 0, {}, {}};
    }
    return {true,
            std::nullopt,
            request.node_id,
            20202021U,
            request.discriminator,
            request.timeout_s,
            "34970112332",
            "MT:Y.K9042C00KA0648G00"};
  }

  void Close() override { open = false; }
  bool IsOpen() const override { return open; }

  std::uint64_t fabric_id{0};
  wotex::matter::CommissioningRequest commissioning;
  wotex::matter::CommissioningWindowRequest window;
  bool commissioning_failure{false};
  bool window_failure{false};
  bool malformed_result{false};
  bool open{false};
};

std::string OpenFrame() {
  return
      "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
      "\"lifecycle\":\"persistent\",\"storage_path\":\"/tmp/store\","
      "\"storage_mode\":\"create_new\",\"authority\":\"generate_root\","
      "\"vendor_id\":65521,\"fabric_id\":1,\"controller_node_id\":2,"
      "\"paa_trust_store\":\"/tmp/paa\"},\"timeout_ms\":1000}";
}

void Open(wotex::matter::HostProtocol &protocol) {
  auto flow = protocol.ProcessLine(
      "{\"version\":1,\"event\":\"flow_open\","
      "\"session_generation\":\"0123456789abcdef0123456789abcdef\"}");
  assert(flow.keep_running && !flow.frame.has_value());
  auto opened = protocol.ProcessLine(OpenFrame());
  assert(opened.keep_running &&
         opened.frame->find("\"ok\":true") != std::string::npos);
}

void TestPinAndRequestBounds() {
  assert(wotex::matter::valid_setup_pin(20202021U));
  for (std::uint32_t pin : {0U, 99999999U, 11111111U, 12345678U,
                            87654321U}) {
    assert(!wotex::matter::valid_setup_pin(pin));
  }

  wotex::matter::CommissioningRequest request{9U, 20202021U, 4095U, 60000U};
  assert(wotex::matter::valid_commissioning_request(request));
  request.discriminator = 4096U;
  assert(!wotex::matter::valid_commissioning_request(request));

  wotex::matter::CommissioningWindowRequest window{
      9U, 180U, 1000U, 0U, 1U};
  assert(wotex::matter::valid_commissioning_window_request(window));
  window.timeout_s = 179U;
  assert(!wotex::matter::valid_commissioning_window_request(window));
}

void TestFinalCommissionAndWindowResults() {
  CommissioningBackend backend;
  wotex::matter::HostProtocol protocol(backend);
  Open(protocol);

  auto commissioned = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"2\",\"operation\":\"commission_on_network\","
      "\"parameters\":{\"node_id\":9,\"setup_pin\":20202021,"
      "\"discriminator\":4095},\"timeout_ms\":60000}");
  assert(commissioned.keep_running);
  assert(commissioned.frame->find("\"case\":\"established\"") !=
         std::string::npos);
  assert(backend.commissioning.node_id == 9U &&
         backend.commissioning.discriminator == 4095U &&
         backend.commissioning.timeout_ms == 60000U);

  auto window = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"3\",\"operation\":\"open_window\","
      "\"parameters\":{\"node_id\":9,\"timeout_s\":300,"
      "\"iteration_count\":1000,\"discriminator\":1234},"
      "\"timeout_ms\":5000}");
  assert(window.keep_running);
  assert(window.frame->find("\"setup_pin\":20202021") != std::string::npos);
  assert(window.frame->find("MT:Y.K9042C00KA0648G00") != std::string::npos);
  assert(backend.window.timeout_s == 300U &&
         backend.window.iteration_count == 1000U);
}

void TestInvalidInputsAndSdkFailures() {
  CommissioningBackend backend;
  wotex::matter::HostProtocol protocol(backend);
  Open(protocol);

  for (const std::string parameters : {
           "{\"node_id\":9,\"setup_pin\":11111111,\"discriminator\":1}",
           "{\"node_id\":9,\"setup_pin\":20202021,\"discriminator\":4096}",
           "{\"node_id\":9,\"setup_pin\":20202021,\"discriminator\":1,\"unfiltered\":true}"}) {
    auto rejected = protocol.ProcessLine(
        "{\"version\":1,\"id\":\"" +
        std::to_string(2U + backend.commissioning.node_id++) +
        "\",\"operation\":\"commission_on_network\",\"parameters\":" +
        parameters + ",\"timeout_ms\":1000}");
    assert(rejected.frame->find("invalid_request") != std::string::npos);
  }

  backend.commissioning_failure = true;
  auto failed = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"5\",\"operation\":\"commission_on_network\","
      "\"parameters\":{\"node_id\":9,\"setup_pin\":20202021,"
      "\"discriminator\":1},\"timeout_ms\":1000}");
  assert(failed.frame->find("\"sdk_status\":4045602817") !=
         std::string::npos);
  assert(failed.frame->find("\"effect\":\"unknown\"") !=
         std::string::npos);
}

void TestExpiredWindowAndOperationalAclDenial() {
  CommissioningBackend backend;
  backend.window_failure = true;
  wotex::matter::HostProtocol protocol(backend);
  Open(protocol);

  auto expired = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"2\",\"operation\":\"open_window\","
      "\"parameters\":{\"node_id\":9,\"timeout_s\":180,"
      "\"iteration_count\":100000,\"discriminator\":0},"
      "\"timeout_ms\":5000}");
  assert(expired.frame->find("window_failed") != std::string::npos);
  assert(expired.frame->find("\"sdk_status\":4045602818") !=
         std::string::npos);
  assert(expired.frame->find("\"effect\":\"unknown\"") !=
         std::string::npos);

  auto denied = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"3\",\"operation\":\"read\","
      "\"parameters\":{\"fabric_id\":1,\"node_id\":9,\"endpoint\":0,"
      "\"cluster\":31,\"member\":0},\"timeout_ms\":1000}");
  assert(denied.frame->find("interaction_status") != std::string::npos);
  assert(denied.frame->find("\"status\":126") != std::string::npos);
}

void TestMalformedAcknowledgementEffect() {
  CommissioningBackend backend;
  backend.malformed_result = true;
  wotex::matter::HostProtocol protocol(backend);
  Open(protocol);

  const auto commission = protocol.ProcessLine(
      R"({"version":1,"id":"2","operation":"commission_on_network","parameters":{"node_id":9,"setup_pin":20202021,"discriminator":1},"timeout_ms":5000})");
  const auto window = protocol.ProcessLine(
      R"({"version":1,"id":"3","operation":"open_window","parameters":{"node_id":9,"timeout_s":180,"iteration_count":1000,"discriminator":1},"timeout_ms":5000})");
  for (const auto &result : {commission, window}) {
    assert(result.keep_running);
    assert(result.frame->find("invalid_backend_result") != std::string::npos);
    assert(result.frame->find(R"("effect":"unknown")") != std::string::npos);
  }
}

} // namespace

int main() {
  TestPinAndRequestBounds();
  TestFinalCommissionAndWindowResults();
  TestInvalidInputsAndSdkFailures();
  TestExpiredWindowAndOperationalAclDenial();
  TestMalformedAcknowledgementEffect();
  return 0;
}
