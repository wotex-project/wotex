#include "wotex_matter/protocol.hpp"
#include "wotex_matter/input_lifetime.hpp"
#include "wotex_matter/input.hpp"

#include <atomic>
#include <cassert>
#include <csignal>
#include <fcntl.h>
#include <iostream>
#include <streambuf>
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
    assert(!interacting);
    ++closes;
    open = false;
  }

  bool IsOpen() const override { return open; }

  wotex::matter::InteractionResponse Interact(
      const wotex::matter::InteractionRequest &) override {
    assert(!interacting);
    ++interactions;
    if (wait_for_control) {
      interacting = true;
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
      while (std::chrono::steady_clock::now() < deadline) {
        if (pump && !pump()) {
          interrupted = true;
          break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      }
      interacting = false;
    }
    return {false, wotex::matter::InteractionError{"not_supported"}};
  }

  void SetControlPump(std::function<bool()> value) override { pump = std::move(value); }
  std::function<bool()> pump;
  bool wait_for_control{false};
  bool interacting{false};
  bool interrupted{false};

  wotex::matter::BackendResult open_result{true, {}};
  wotex::matter::NativeOpenOptions identity;
  int interactions{0};
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


std::string PendingCommands() {
  return R"({"version":1,"event":"flow_open","session_generation":"0123456789abcdef0123456789abcdef"})" "\n" +
      OpenFrame() + "\n" +
      R"({"version":1,"id":"2","operation":"read","parameters":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":6,"member":0},"timeout_ms":1000})" "\n";
}

void TestControlsDuringPendingInteraction() {
  const std::string health = R"({"version":1,"id":"3","operation":"health","parameters":{},"timeout_ms":1000})" "\n";
  const std::string close_frame = R"({"version":1,"id":"4","operation":"close","parameters":{},"timeout_ms":1000})" "\n";
  for (const std::string &ending : {
           health + close_frame,
           health,
           health.substr(0, health.size() - 1),
           std::string(R"({"version":1,"id":"2","operation":"health","parameters":{},"timeout_ms":1000})") + "\n",
           std::string(R"({"version":1,"id":"3","operation":"invoke","parameters":{},"timeout_ms":1000})") + "\n" + close_frame}) {
    const std::string commands = PendingCommands() + ending;
    int input[2];
    assert(pipe(input) == 0);
    assert(write(input[1], commands.data(), commands.size()) == static_cast<ssize_t>(commands.size()));
    close(input[1]);
    RecordingBackend backend;
    backend.wait_for_control = true;
    std::istringstream stream(commands);
    std::ostringstream output;
    const int result = wotex::matter::RunHost(backend, stream, output, {}, input[0]);
    close(input[0]);
    assert(result == (ending.back() == '\n' ? 0 : 1));
    assert(backend.interrupted && backend.closes == 1 && !backend.pump);
    assert(backend.interactions == 1);
    const auto frames = output.str();
    assert(frames.find("\"id\":\"2\"") == std::string::npos);
    if (ending == health + close_frame) {
      const auto ready = frames.find("\"id\":\"3\"");
      const auto closed = frames.find("\"id\":\"4\"");
      assert(ready != std::string::npos && closed != std::string::npos && ready < closed);
    }
    if (ending.find("invoke") != std::string::npos) {
      assert(frames.find("interaction_busy") != std::string::npos);
    }
  }

  // A health request neither aborts nor restarts an otherwise pending wait.
  int input[2];
  assert(pipe(input) == 0);
  const std::string commands = PendingCommands() + health;
  assert(write(input[1], commands.data(), commands.size()) == static_cast<ssize_t>(commands.size()));
  std::thread owner([&] {
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    close(input[1]);
  });
  RecordingBackend backend;
  backend.wait_for_control = true;
  std::istringstream stream(commands);
  std::ostringstream output;
  const int result = wotex::matter::RunHost(backend, stream, output, {}, input[0]);
  owner.join();
  close(input[0]);
  assert(result == 0 && !backend.interrupted && backend.closes == 1 && !backend.pump);
  assert(output.str().find("\"id\":\"3\"") < output.str().find("\"id\":\"2\""));
}

void TestBoundedDescriptorInput() {
  using Input = wotex::matter::BoundedInput;
  for (bool oversized : {false, true}) {
    int descriptors[2];
    assert(pipe(descriptors) == 0);
    const int flags = fcntl(descriptors[0], F_GETFL);
    {
      Input input(descriptors[0]);
      assert(fcntl(descriptors[0], F_GETFL) & O_NONBLOCK);
      std::string line;
      assert(input.Next(line, 0) == Input::Result::Waiting);
      const std::string chunk(1024, 'x');
      for (unsigned part = 0; part < 127; ++part) {
        assert(write(descriptors[1], chunk.data(), chunk.size()) == 1024);
        assert(input.Next(line, 0) == Input::Result::Waiting);
      }
      const std::string last(oversized ? 1024 : 1023, 'x');
      assert(write(descriptors[1], last.data(), last.size()) == static_cast<ssize_t>(last.size()));
      assert(input.Next(line, 0) == (oversized ? Input::Result::Invalid : Input::Result::Waiting));
      if (!oversized) {
        assert(write(descriptors[1], "\nnext\n", 6) == 6);
        assert(input.Next(line, 0) == Input::Result::Line);
        assert(line.size() == wotex::matter::kMaximumFrameBytes - 1);
        assert(input.Next(line, 0) == Input::Result::Line && line == "next");
        close(descriptors[1]);
        assert(input.Next(line, 0) == Input::Result::End);
      } else {
        close(descriptors[1]);
      }
    }
    assert(fcntl(descriptors[0], F_GETFL) == flags);
    close(descriptors[0]);
  }
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

class DelayedEof final : public std::streambuf {
 protected:
  int_type underflow() override {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    return traits_type::eof();
  }
};

void TestFailedOutputCleanup() {
  for (const bool exceptions : {false, true}) {
    // Give the writer time to fail before RunHost reaches Stop. Exception-
    // enabled streams must also join their writer and signal failure once.
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
      RecordingBackend backend;
      DelayedEof buffer;
      std::istream input(&buffer);
      std::ostringstream output;
      if (exceptions) {
        output.exceptions(std::ios_base::badbit | std::ios_base::failbit);
      }
      try {
        output.setstate(std::ios_base::badbit);
      } catch (const std::ios_base::failure &) {
      }
      std::atomic<unsigned> failures{0};
      const int result = wotex::matter::RunHost(
          backend, input, output, [&failures] { ++failures; });
      assert(result == EXIT_FAILURE && failures == 1);
      std::_Exit(result);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == EXIT_FAILURE);
  }
}

std::int64_t AssertReapedFailure(pid_t child) {
  const auto started = std::chrono::steady_clock::now();
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
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - started).count();
}

void TestExplicitChannelFailure() {
  int input[2];
  assert(pipe(input) == 0);
  const pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    wotex::matter::InputLifetime lifetime(input[0]);
    // Keep both input ends open: only explicit failure can start termination.
    // Repeated failure must not extend the first grace.
    for (unsigned attempt = 0; attempt < 50; ++attempt) {
      lifetime.Fail();
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    std::_Exit(42);
  }
  AssertReapedFailure(child);
  close(input[0]);
  close(input[1]);
}

void TestSdkFailedOutput(const char *executable) {
  int input[2];
  assert(pipe(input) == 0);
  const pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    const int full = open("/dev/full", O_WRONLY);
    assert(full >= 0 && dup2(input[0], STDIN_FILENO) == STDIN_FILENO &&
           dup2(full, STDOUT_FILENO) == STDOUT_FILENO);
    close(full);
    close(input[0]);
    close(input[1]);
    execl(executable, executable, static_cast<char *>(nullptr));
    std::_Exit(42);
  }
  // The SDK host cannot consume another command or observe stdin EOF. Its
  // ready-frame write fails, and the host must still release within one second.
  close(input[0]);
  const auto elapsed = AssertReapedFailure(child);
  close(input[1]);
  std::cout << "{\"status\":\"passed\",\"cleanup_ms\":" << elapsed
            << ",\"owned_processes_after_grace\":0}\n";
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

int main(int argc, char **argv) {
  if (argc == 2) {
    TestSdkFailedOutput(argv[1]);
    return 0;
  }
  assert(argc == 1);
  TestBoundedDescriptorInput();
  TestControlsDuringPendingInteraction();
  TestParser();
  TestFrameDepthBoundary();
  TestLifecycleAndFabricAdmission();
  TestStartupFailureAndEofCleanup();
  TestRequestCounterAndReservedClose();
  TestInputLifetime();
  TestFailedOutputCleanup();
  TestExplicitChannelFailure();
  return 0;
}
