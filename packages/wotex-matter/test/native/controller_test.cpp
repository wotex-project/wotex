#include "wotex_matter/protocol.hpp"
#include "wotex_matter/input_lifetime.hpp"

#include <cassert>
#include <csignal>
#include <sstream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>

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

void TestRequestCounterAndReservedClose() {
  const auto request = [](const std::string &id,
                          const std::string &operation = "health",
                          const std::string &parameters = "{}") {
    return std::string(R"({"version":1,"id":")") + id +
        R"(","operation":")" + operation + R"(","parameters":)" +
        parameters + R"(,"timeout_ms":1000})";
  };
  const std::string maximum = "18446744073709551615";
  assert(wotex::matter::HostProtocol::ParseRequestAccepted(request(maximum)));
  assert(wotex::matter::HostProtocol::ParseRequestAccepted(request("close", "close")));
  for (const auto &invalid : {"0", "01", "+1", "-1", "18446744073709551616"}) {
    assert(!wotex::matter::HostProtocol::ParseRequestAccepted(request(invalid)));
  }
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(request("close")));
  assert(!wotex::matter::HostProtocol::ParseRequestAccepted(
      request("close", "close", R"({"extra":true})")));

  for (const auto &next : {"2", "1", "01", "18446744073709551616", "close"}) {
    RecordingBackend backend;
    wotex::matter::HostProtocol protocol(backend);
    assert(protocol.ProcessLine(
        R"({"version":1,"event":"flow_open","session_generation":"0123456789abcdef0123456789abcdef"})").keep_running);
    assert(protocol.ProcessLine(OpenFrame()).keep_running);
    assert(protocol.ProcessLine(request(maximum)).keep_running);
    const bool closing = std::string(next) == "close";
    const auto result = protocol.ProcessLine(request(next, closing ? "close" : "health"));
    assert(!result.keep_running && backend.closes == 1 && !backend.open);
    assert(result.frame.has_value() == closing);
    if (closing) {
      assert(result.frame->find(R"("id":"close")") != std::string::npos);
      assert(result.frame->find(R"("result":null)") != std::string::npos);
    }
  }
}

void TestInputLifetime() {
  int input[2];
  assert(pipe(input) == 0);
  const auto normal_start = std::chrono::steady_clock::now();
  {
    wotex::matter::InputLifetime lifetime(input[0]);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  assert(std::chrono::steady_clock::now() - normal_start <
         std::chrono::seconds(1));

  int ready[2];
  assert(pipe(ready) == 0);
  const pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    close(input[1]);
    close(ready[0]);
    wotex::matter::InputLifetime lifetime(input[0]);
    const char byte = 'r';
    assert(write(ready[1], &byte, 1) == 1);
    close(ready[1]);
    std::this_thread::sleep_for(std::chrono::seconds(5));
    std::_Exit(42);
  }

  close(input[0]);
  close(ready[1]);
  char byte = 0;
  assert(read(ready[0], &byte, 1) == 1 && byte == 'r');
  close(ready[0]);
  const auto started = std::chrono::steady_clock::now();
  close(input[1]);
  int status = 0;
  bool reaped = false;
  while (std::chrono::steady_clock::now() - started < std::chrono::seconds(1)) {
    const pid_t result = waitpid(child, &status, WNOHANG);
    if (result == child) {
      reaped = true;
      break;
    }
    assert(result == 0 || (result == -1 && errno == EINTR));
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  if (!reaped) {
    kill(child, SIGKILL);
    waitpid(child, &status, 0);
  }
  assert(reaped && WIFEXITED(status) && WEXITSTATUS(status) == EXIT_FAILURE);
}

} // namespace

int main() {
  TestParser();
  TestFrameDepthBoundary();
  TestLifecycleAndFabricAdmission();
  TestStartupFailureAndEofCleanup();
  TestRequestCounterAndReservedClose();
  TestInputLifetime();
  return 0;
}
