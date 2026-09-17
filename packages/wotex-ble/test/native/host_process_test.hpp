// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "discovery_test.hpp"
#include <array>
#include <csignal>
#include <sys/wait.h>

namespace host_process_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) { if (!value) throw std::runtime_error("native host process assertion at line " + std::to_string(line)); }
#define PROCESS_CHECK(value) ::host_process_test::verify((value), __LINE__)
class Process {
  pid_t pid_ = -1;
  int input_ = -1, output_ = -1;
  Lines lines_;
public:
  std::vector<Json> frames;
  std::optional<int> status;
  explicit Process(const std::string &executable) {
    std::array<int, 2> input{-1, -1}, output{-1, -1};
    PROCESS_CHECK(::pipe(input.data()) == 0 && ::pipe(output.data()) == 0);
    pid_ = ::fork(); PROCESS_CHECK(pid_ >= 0);
    if (!pid_) {
      if (::dup2(input[0], STDIN_FILENO) < 0 || ::dup2(output[1], STDOUT_FILENO) < 0) _exit(126);
      for (int descriptor : {input[0], input[1], output[0], output[1]}) ::close(descriptor);
      ::execl(executable.c_str(), executable.c_str(), static_cast<char *>(nullptr)); _exit(126);
    }
    ::close(input[0]); ::close(output[1]); input_ = input[1]; output_ = output[0];
    for (int descriptor : {input_, output_}) {
      PROCESS_CHECK(::fcntl(descriptor, F_SETFL, ::fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0);
      PROCESS_CHECK(::fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0);
    }
  }
  ~Process() {
    if (input_ >= 0) ::close(input_);
    if (output_ >= 0) ::close(output_);
    if (pid_ <= 0) return;
    // This unreaped direct child is the SDK fixture and never forks. Runtime
    // process-group custody is independently tested through custody_check.c.
    ::kill(pid_, SIGTERM);
    const auto deadline = Clock::now() + std::chrono::milliseconds(750);
    int status = 0;
    while (Clock::now() < deadline) {
      if (::waitpid(pid_, &status, WNOHANG) == pid_) { pid_ = -1; return; }
      ::poll(nullptr, 0, 1);
    }
    ::kill(pid_, SIGKILL); while (::waitpid(pid_, &status, 0) < 0 && errno == EINTR) {}
  }
  void send(const Json &frame) {
    const auto bytes = EncodedFrame::from(frame).bytes();
    PROCESS_CHECK(input_ >= 0 && ::write(input_, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
  }
  void eof() { PROCESS_CHECK(input_ >= 0); ::close(input_); input_ = -1; }
  const Json *response(const std::string &id) const {
    for (const auto &frame : frames) if (frame.contains("id") && frame.at("id") == id && frame.contains("ok")) return &frame;
    return nullptr;
  }
  void request(const std::string &id, const std::string &operation, const Json &parameters = Json::object(), unsigned timeout = 2000) {
    send({{"version", 1}, {"id", id}, {"operation", operation}, {"parameters", parameters}, {"timeout_ms", timeout}});
  }
  void poll() {
    std::array<char, 8192> bytes{};
    for (unsigned count = 0; count < 16 && output_ >= 0; ++count) {
      const auto size = ::read(output_, bytes.data(), bytes.size());
      if (size < 0) { PROCESS_CHECK(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR); break; }
      if (!size) { lines_.eof(); ::close(output_); output_ = -1; break; }
      lines_.feed(std::string_view(bytes.data(), static_cast<std::size_t>(size)), [&](std::string_view line) { frames.push_back(parse_line(line)); });
    }
    if (pid_ > 0) {
      int value = 0; const auto result = ::waitpid(pid_, &value, WNOHANG);
      PROCESS_CHECK(result >= 0 || errno == EINTR);
      if (result == pid_) { PROCESS_CHECK(WIFEXITED(value)); status = WEXITSTATUS(value); pid_ = -1; }
    }
  }
};
inline void until(discovery_test::Peer &peer, Process &process, const std::function<bool()> &done) {
  const auto deadline = Clock::now() + std::chrono::seconds(3);
  while (!done() && Clock::now() < deadline) { peer.poll(); process.poll(); ::poll(nullptr, 0, 1); }
  PROCESS_CHECK(done());
}
inline Json parameters(const std::string &address) {
  return {{"peer", {{"adapter", "/org/bluez/hci0"}, {"address", "AA:BB:CC:DD:EE:FF"}, {"address_type", "random"}}},
    {"connection", "borrowed"}, {"bus_address", address}};
}
inline Json projection(const Json &input, const std::string &address, const std::string &executable) {
  PROCESS_CHECK(fields(input, {"session_generation", "parameters", "mode"}) && input.at("session_generation").is_string() &&
    (input.at("mode") == "normal" || input.at("mode") == "open_eof" || input.at("mode") == "duplicate_flow"));
  discovery_test::Peer peer(address); Process process(executable);
  until(peer, process, [&] { return !process.frames.empty(); });
  const auto ready = process.frames.front();
  const Json flow{{"version", 1}, {"event", "flow_open"}, {"session_generation", input.at("session_generation")}};
  process.send(flow); Json result{{"ready", ready}};
  if (input.at("mode") == "duplicate_flow") process.send(flow);
  else {
    auto options = input.at("parameters"); PROCESS_CHECK(options.at("bus_address") == "$PRIVATE_BUS"); options["bus_address"] = address;
    std::string sender;
    if (input.at("mode") == "open_eof") peer.on_query = [&](DBusMessage *request) { sender = dbus_message_get_sender(request); };
    process.request("open", "open", options, 60000);
    if (input.at("mode") == "open_eof") {
      until(peer, process, [&] { return !sender.empty(); }); process.eof();
    } else {
      until(peer, process, [&] { return process.response("open"); }); PROCESS_CHECK(process.response("open")->at("ok") == true);
      sender = process.response("open")->at("result").at("sender").get<std::string>();
      process.request("1", "discover"); until(peer, process, [&] { return process.response("1"); });
      result["discovery"] = process.response("1")->at("result"); process.request("close", "close");
    }
    until(peer, process, [&] { return process.status.has_value(); });
    result["owned_sender_released"] = !dbus_bus_name_has_owner(peer.connection(), sender.c_str(), nullptr);
    result["unrelated_sender_retained"] = bool(dbus_bus_name_has_owner(peer.connection(), peer.sender().c_str(), nullptr));
  }
  until(peer, process, [&] { return process.status.has_value(); });
  result["status"] = *process.status; result["disconnect_calls"] = peer.methods.size(); result["snapshot_calls"] = peer.calls;
  return result;
}
inline void invariants(const std::string &address, const std::string &executable) {
  discovery_test::Peer peer(address);
  {
    Process process(executable); until(peer, process, [&] { return !process.frames.empty(); });
    PROCESS_CHECK(process.frames[0] == Json({{"version", 1}, {"event", "ready"}, {"backend", "bluez-native"},
      {"revision", "2123ab772fbe97d1369fc9e179ea87c3469cf98f"}}));
    process.send({{"version", 1}, {"event", "flow_open"}, {"session_generation", std::string(32, 'a')}});
    process.request("open", "open", parameters(address)); until(peer, process, [&] { return process.response("open"); });
    PROCESS_CHECK(process.response("open")->at("ok") == true);
    const auto sender = process.response("open")->at("result").at("sender").get<std::string>();
    process.request("1", "discover"); until(peer, process, [&] { return process.response("1"); });
    PROCESS_CHECK(process.response("1")->at("ok") == true && process.response("1")->at("result").at("characteristics").size() == 1);
    process.request("close", "close"); until(peer, process, [&] { return process.status.has_value(); });
    PROCESS_CHECK(process.status == 0 && process.response("close") && process.response("close")->at("ok") == true && peer.methods.empty());
    PROCESS_CHECK(!dbus_bus_name_has_owner(peer.connection(), sender.c_str(), nullptr));
    PROCESS_CHECK(dbus_bus_name_has_owner(peer.connection(), peer.sender().c_str(), nullptr));
  }
  {
    Process process(executable); until(peer, process, [&] { return !process.frames.empty(); });
    process.send({{"version", 1}, {"event", "flow_open"}, {"session_generation", std::string(32, 'b')}});
    std::string opening_sender;
    peer.on_query = [&](DBusMessage *request) { opening_sender = dbus_message_get_sender(request); };
    const auto calls = peer.calls;
    process.request("open", "open", parameters(address), 60000); until(peer, process, [&] { return peer.calls > calls; });
    const auto started = Clock::now(); process.eof(); until(peer, process, [&] { return process.status.has_value(); });
    PROCESS_CHECK(process.status == 1 && Clock::now() - started < std::chrono::milliseconds(750) && peer.methods.empty());
    PROCESS_CHECK(!opening_sender.empty() && !dbus_bus_name_has_owner(peer.connection(), opening_sender.c_str(), nullptr));
    peer.on_query = {};
  }
  {
    Process process(executable); until(peer, process, [&] { return !process.frames.empty(); });
    process.send({{"version", 1}, {"event", "flow_open"}, {"session_generation", std::string(32, 'c')}});
    process.send({{"version", 1}, {"event", "flow_open"}, {"session_generation", std::string(32, 'c')}});
    until(peer, process, [&] { return process.status.has_value(); }); PROCESS_CHECK(process.status == 1);
  }
  {
    // Input loss after an admitted close cannot relabel that close as a cleanup failure.
    Process process(executable); until(peer, process, [&] { return !process.frames.empty(); });
    process.send({{"version", 1}, {"event", "flow_open"}, {"session_generation", std::string(32, 'd')}});
    process.request("close", "close"); process.eof();
    until(peer, process, [&] { return process.status.has_value(); });
    PROCESS_CHECK(process.status == 0 && process.response("close") && process.response("close")->at("ok") == true);
    PROCESS_CHECK(process.response("close")->at("result").is_null());
  }
}
} // namespace host_process_test
