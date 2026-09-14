#include "wotex_matter/protocol.hpp"

#include <cassert>
#include <sstream>
#include <string>

namespace {

class RecordingBackend final : public wotex::matter::ControllerBackend {
 public:
  wotex::matter::BackendResult Open(
      const wotex::matter::NativeOpenOptions &options) override {
    ++opens;
    identity = options;
    open = open_result.ok;
    return open_result;
  }

  void Close() override {
    ++closes;
    open = false;
  }

  bool IsOpen() const override { return open; }

  wotex::matter::InteractionResponse Interact(
      const wotex::matter::InteractionRequest &) override {
    return {false, wotex::matter::InteractionError{"not_supported"}};
  }

  wotex::matter::BackendResult open_result{true, {}};
  wotex::matter::NativeOpenOptions identity;
  int opens{0};
  int closes{0};
  bool open{false};
};

std::string OpenFrame(const std::string &id = "1") {
  return "{\"version\":1,\"id\":\"" + id +
      "\",\"operation\":\"open\",\"parameters\":{"
      "\"lifecycle\":\"persistent\",\"storage_path\":\"/tmp/store\","
      "\"storage_mode\":\"create_new\",\"authority\":\"generate_root\","
      "\"vendor_id\":65521,\"fabric_id\":1,\"controller_node_id\":2,"
      "\"paa_trust_store\":\"/tmp/paa\"},\"timeout_ms\":1000}";
}

void TestParser() {
  assert(wotex::matter::HostProtocol::ParseRequestAccepted(
      "{\"version\":1,\"id\":\"1\",\"operation\":\"health\","
      "\"parameters\":{},\"timeout_ms\":1000}"));
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(
      "{\"version\":1,\"id\":\"1\",\"id\":\"2\","
      "\"operation\":\"health\",\"parameters\":{},\"timeout_ms\":1000}"));
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(
      "{\"version\":1,\"id\":\"1\",\"operation\":\"health\","
      "\"parameters\":{},\"timeout_ms\":0}"));
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(
      "{\"version\":1,\"id\":\"1\",\"operation\":\"health\","
      "\"parameters\":{},\"timeout_ms\":1000,\"extra\":true}"));
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(
      "{\"version\":1,\"id\":\"1\",\"operation\":\"health\","
      "\"parameters\":[],\"timeout_ms\":1000}"));
}

void TestFrameDepthBoundary() {
  const auto nested_request = [](unsigned arrays) {
    return std::string(R"({"version":1,"id":"1","operation":"health","parameters":{"nested":)") +
        std::string(arrays, '[') + "0" + std::string(arrays, ']') +
        R"(},"timeout_ms":1000})";
  };
  // Root and parameters account for two collection levels.
  assert(wotex::matter::HostProtocol::ParseRequestAccepted(nested_request(22)));
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(nested_request(23)));
}

void TestLifecycleAndFabricAdmission() {
  RecordingBackend backend;
  wotex::matter::HostProtocol protocol(backend);
  auto flow = protocol.ProcessLine(
      "{\"version\":1,\"event\":\"flow_open\","
      "\"session_generation\":\"0123456789abcdef0123456789abcdef\"}");
  assert(flow.keep_running && !flow.frame.has_value());

  auto opened = protocol.ProcessLine(OpenFrame());
  assert(opened.keep_running && opened.frame->find("\"ok\":true") != std::string::npos);
  assert(backend.opens == 1 && backend.identity.fabric_id == 1);

  auto wrong_fabric = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"2\",\"operation\":\"read\","
      "\"parameters\":{\"fabric_id\":2},\"timeout_ms\":1000}");
  assert(wrong_fabric.keep_running);
  assert(wrong_fabric.frame->find("fabric_mismatch") != std::string::npos);

  auto health = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"3\",\"operation\":\"health\","
      "\"parameters\":{},\"timeout_ms\":1000}");
  assert(health.frame->find("\"status\":\"ready\"") != std::string::npos);

  auto closed = protocol.ProcessLine(
      "{\"version\":1,\"id\":\"4\",\"operation\":\"close\","
      "\"parameters\":{},\"timeout_ms\":1000}");
  assert(!closed.keep_running && backend.closes == 1 && !backend.open);
}

void TestStartupFailureAndEofCleanup() {
  RecordingBackend failed_backend;
  failed_backend.open_result = {false, "authority_invalid"};
  wotex::matter::HostProtocol failed(failed_backend);
  assert(failed.ProcessLine(
      "{\"version\":1,\"event\":\"flow_open\","
      "\"session_generation\":\"0123456789abcdef0123456789abcdef\"}").keep_running);
  auto result = failed.ProcessLine(OpenFrame());
  assert(!result.keep_running);
  assert(result.frame->find("authority_invalid") != std::string::npos);

  RecordingBackend eof_backend;
  std::istringstream input(
      "{\"version\":1,\"event\":\"flow_open\","
      "\"session_generation\":\"0123456789abcdef0123456789abcdef\"}\n" +
      OpenFrame() + "\n");
  std::ostringstream output;
  assert(wotex::matter::RunHost(eof_backend, input, output) == 0);
  assert(eof_backend.opens == 1 && eof_backend.closes == 1 && !eof_backend.open);
  assert(output.str().find("\"event\":\"ready\"") != std::string::npos);
}

} // namespace

int main() {
  TestParser();
  TestFrameDepthBoundary();
  TestLifecycleAndFabricAdmission();
  TestStartupFailureAndEofCleanup();
  return 0;
}
