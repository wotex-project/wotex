#include "bridge_host_test.hpp"

#include <nlohmann/json.hpp>
#include <array>
#include <cassert>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <poll.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>
#include <utility>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Executable probes must remain separate from the production process.
#endif

namespace wotex::matter::testing {
namespace {
using Json = nlohmann::json;
using Time = std::chrono::steady_clock;
const std::string generation = "01000000000000000000000000000000";
const std::string failure = "bridge process failed\n";
std::string Control(std::string_view role) {
  return "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"" + std::string(role) +
      "\",\"generation\":\"" + generation + "\"}\n";
}
void Configure(const std::string &root, std::string_view key, const Json &value) {
  const auto path = root + "/configuration";
  Json configuration;
  std::ifstream(path) >> configuration;
  configuration[key] = value;
  std::ofstream output(path, std::ios::trunc);
  output << configuration.dump();
  assert(output.good());
}
class Child final {
 public:
  Child(const char *executable, const std::vector<std::string> &arguments,
        bool diagnostics = true) {
    int input[2], output[2], errors[2];
    assert(pipe(input) == 0 && pipe(output) == 0 && pipe(errors) == 0);
    if (!diagnostics) close(errors[0]);
    std::vector<char *> argv{const_cast<char *>(executable)};
    for (const auto &argument : arguments) argv.push_back(const_cast<char *>(argument.c_str()));
    argv.push_back(nullptr);
    pid_ = fork();
    assert(pid_ >= 0);
    if (pid_ == 0) {
      // The executable must install its own dispositions after exec.
      assert(signal(SIGPIPE, SIG_DFL) != SIG_ERR && signal(SIGTERM, SIG_DFL) != SIG_ERR &&
             signal(SIGINT, SIG_DFL) != SIG_ERR);
      assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
      assert(dup2(output[1], STDOUT_FILENO) == STDOUT_FILENO);
      assert(dup2(errors[1], STDERR_FILENO) == STDERR_FILENO);
      // A second probe must not retain a first probe's process pipes.
      for (int descriptor = 3; descriptor < 1024; ++descriptor) close(descriptor);
      execv(executable, argv.data());
      _exit(127);
    }
    close(input[0]);
    close(output[1]);
    close(errors[1]);
    input_ = input[1];
    output_ = output[0];
    errors_ = diagnostics ? errors[0] : -1;
  }
  ~Child() {
    if (pid_ > 0) {
      kill(pid_, SIGKILL);
      waitpid(pid_, nullptr, 0);
    }
    EndInput();
    EndOutput();
    if (errors_ >= 0) close(errors_);
  }
  void Send(std::string_view frame) {
    assert(write(input_, frame.data(), frame.size()) == static_cast<ssize_t>(frame.size()));
  }
  void EndInput() {
    if (input_ >= 0) close(input_);
    input_ = -1;
  }
  void EndOutput() {
    if (output_ >= 0) close(output_);
    output_ = -1;
  }
  void Signal(int signal) { assert(kill(pid_, signal) == 0); }
  void AwaitSignals() {
    const auto deadline = Time::now() + std::chrono::seconds(3);
    while (Time::now() < deadline) {
      std::ifstream state("/proc/" + std::to_string(pid_) + "/status");
      std::string line;
      unsigned long long caught = 0, ignored = 0;
      while (std::getline(state, line)) {
        if (line.substr(0, 7) == "SigCgt:") caught = std::stoull(line.substr(7), nullptr, 16);
        if (line.substr(0, 7) == "SigIgn:") ignored = std::stoull(line.substr(7), nullptr, 16);
      }
      if ((caught & (1ULL << (SIGTERM - 1))) && (caught & (1ULL << (SIGINT - 1))) &&
          (ignored & (1ULL << (SIGPIPE - 1))))
        return;
      poll(nullptr, 0, 1);
    }
    assert(false && "production signal setup did not become ready");
  }
  std::string Line() {
    const auto deadline = Time::now() + std::chrono::seconds(6);
    while (Time::now() < deadline) {
      const auto end = output_bytes_.find('\n');
      if (end != std::string::npos) {
        const auto line = output_bytes_.substr(0, end + 1);
        output_bytes_.erase(0, end + 1);
        return line;
      }
      if (output_ < 0) return std::exchange(output_bytes_, {});
      Pump();
    }
    assert(false && "production output exceeded its original test deadline");
    return {};
  }
  void Ready() {
    Send(Control("open"));
    const auto ready = Json::parse(Line());
    assert(ready ==
           Json({{"v", 1},
                 {"backend", "matter-bridge"},
                 {"type", "ready"},
                 {"generation", generation},
                 {"sdk_revision", "250a9e6c50ee2068107f3c4808b680f5f2925415"},
                 {"model_sha256",
                  "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671"}}));
  }
  void Observe(unsigned id, std::string_view thing = "0001", unsigned endpoint = 3,
               Json on_off = true, Json temperature = nullptr, bool applied = true) {
    Send(Json({{"v", 1},
               {"backend", "matter-bridge"},
               {"type", "observation"},
               {"generation", generation},
               {"id", std::to_string(id)},
               {"thing", thing},
               {"endpoint", endpoint},
               {"reachable", true},
               {"on_off", on_off},
               {"temperature", temperature}})
             .dump() +
         "\n");
    assert(Json::parse(Line()) ==
           Json({{"v", 1},
                 {"backend", "matter-bridge"},
                 {"type", "observation-receipt"},
                 {"generation", generation},
                 {"id", std::to_string(id)},
                 {"outcome", applied ? "applied" : "refused"}}));
  }
  void Closed() {
    Send(Control("close"));
    assert(Line() == Control("closed"));
    Finish(0);
  }
  void Finish(int expected, std::string_view diagnostic = {}) {
    const auto deadline = Time::now() + std::chrono::seconds(7);
    int status = 0;
    bool exited = false;
    while (Time::now() < deadline) {
      Pump();
      if (!exited) {
        const auto result = waitpid(pid_, &status, WNOHANG);
        assert(result >= 0 || errno == EINTR);
        exited = result == pid_;
        if (exited) pid_ = -1;
      }
      if (exited && output_ < 0 && errors_ < 0) break;
    }
    assert(exited && output_ < 0 && errors_ < 0 && WIFEXITED(status));
    if (WEXITSTATUS(status) != expected || error_bytes_ != diagnostic || !output_bytes_.empty())
      std::cerr << "host probe actual exit " << WEXITSTATUS(status) << ", expected " << expected
                << ", stderr " << error_bytes_ << ", stdout " << output_bytes_ << '\n';
    assert(WEXITSTATUS(status) == expected && error_bytes_ == diagnostic && output_bytes_.empty());
    EndInput();
  }

 private:
  void Pump() {
    std::array<pollfd, 2> descriptors{{{output_, POLLIN, 0}, {errors_, POLLIN, 0}}};
    const int ready = poll(descriptors.data(), descriptors.size(), 10);
    assert(ready >= 0 || errno == EINTR);
    for (unsigned i = 0; i < descriptors.size(); ++i) {
      if (!(descriptors[i].revents & (POLLIN | POLLHUP))) continue;
      auto &descriptor = i == 0 ? output_ : errors_;
      auto &bytes = i == 0 ? output_bytes_ : error_bytes_;
      char buffer[4096];
      const auto count = read(descriptor, buffer, sizeof(buffer));
      assert(count >= 0 || errno == EINTR);
      if (count == 0) {
        close(descriptor);
        descriptor = -1;
      } else if (count > 0) {
        bytes.append(buffer, static_cast<std::size_t>(count));
        assert(bytes.size() <= 16384);
      }
    }
  }
  pid_t pid_{-1};
  int input_{-1}, output_{-1}, errors_{-1};
  std::string output_bytes_, error_bytes_;
};
} // namespace

int RunBridgeHostProbe(const std::string &root, std::string_view mode, const char *executable) {
  assert(executable && executable[0] == '/');
  assert(signal(SIGPIPE, SIG_IGN) != SIG_ERR);
  const auto path = root + "/configuration";
  const std::vector<std::string> arguments{"--configuration", path};
  if (mode == "invocation") {
    for (const auto &invalid :
         std::vector<std::vector<std::string>>{{},
                                               {"--help"},
                                               {path},
                                               {"--configuration"},
                                               {"--config", path},
                                               {"--configuration", ""},
                                               {"--configuration", "relative-private-canary"},
                                               {"--configuration", "/private\ncanary"},
                                               {"--configuration", "/private\rcanary"},
                                               {"--configuration", "/" + std::string(4096, 'x')},
                                               {"--configuration", path, "private-extra-canary"}}) {
      Child child(executable, invalid);
      child.Finish(64, "invalid bridge invocation\n");
    }
    // Even argument refusal must survive a lost diagnostic pipe.
    Child lost_diagnostics(executable, {}, false);
    lost_diagnostics.Finish(64);
    // The exact bound is admitted as an argument; EOF still prevents SDK work.
    Child maximum(executable, {"--configuration", "/" + std::string(4095, 'x')});
    maximum.EndInput();
    maximum.Finish(65, failure);
    assert(!std::filesystem::exists(root + "/store"));
  } else if (mode == "missing-open" || mode == "bad-open" || mode == "partial-open" ||
             mode == "oversize-open" || mode == "pre-ready" || mode == "startup-timeout" ||
             mode == "term-before-open" || mode == "interrupt-before-open") {
    Child child(executable, {"--configuration", root + "/absent-private-canary"});
    const auto started = Time::now();
    int expected = 65;
    if (mode == "missing-open") child.EndInput();
    else if (mode == "partial-open") {
      child.Send("{\"v\":1");
      child.EndInput();
    } else if (mode == "bad-open") child.Send("{}\n");
    else if (mode == "oversize-open") child.Send(std::string(513, 'x'));
    else if (mode == "pre-ready") child.Send(Control("open") + Control("close"));
    else if (mode == "startup-timeout") expected = 69;
    else {
      child.AwaitSignals();
      child.Signal(mode == "term-before-open" ? SIGTERM : SIGINT);
      expected = 75;
    }
    child.Finish(expected, failure);
    if (mode == "startup-timeout") assert(Time::now() - started >= std::chrono::milliseconds(4900));
    assert(!std::filesystem::exists(root + "/store"));
  } else {
    if (mode == "missing-config") assert(unlink(path.c_str()) == 0);
    if (mode == "missing-dac") assert(unlink((root + "/dac").c_str()) == 0);
    if (mode == "permissions") assert(chmod(path.c_str(), 0644) == 0);
    if (mode == "symlink") {
      assert(rename(path.c_str(), (root + "/private-canary").c_str()) == 0);
      assert(symlink((root + "/private-canary").c_str(), path.c_str()) == 0);
    }
    if (mode == "interface") Configure(root, "interface", "absent-wm");
    Child child(executable, arguments);
    if (mode == "missing-config" || mode == "missing-dac" || mode == "permissions" ||
        mode == "symlink" || mode == "interface") {
      child.Send(Control("open"));
      child.Finish(69, failure);
    } else {
      child.Ready();
      if (mode == "normal" || mode == "reopen" || mode == "store-exists" ||
          mode == "store-locked") {
        child.Send(
            "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-probe\",\"generation\":\"" +
            generation + "\",\"id\":\"1\"}\n");
        const auto sample = Json::parse(child.Line());
        assert(sample.size() == 6 && sample["v"] == 1 && sample["backend"] == "matter-bridge" &&
               sample["type"] == "clock-sample" && sample["generation"] == generation &&
               sample["id"] == "1" && sample["native_ms"].is_string());
        child.Observe(1);
        child.Observe(2, "0002", 4, nullptr, -1000);
        child.Observe(3, "0001", 3, nullptr);
        child.Observe(4, "ffff", 3, true, nullptr, false);
        child.Observe(5, "0001", 4, true, nullptr, false);
        child.Observe(6, "0002", 4, nullptr, 4001, false);
        for (unsigned i = 7; i <= 70; ++i) child.Observe(i);
        if (mode == "store-locked") {
          Configure(root, "store_mode", "reopen");
          Child locked(executable, arguments);
          locked.Send(Control("open"));
          locked.Finish(69, failure);
        }
        child.Closed();
        if (mode != "normal") {
          if (mode != "store-exists") Configure(root, "store_mode", "reopen");
          Child reopened(executable, arguments);
          if (mode == "store-exists") {
            reopened.Send(Control("open"));
            reopened.Finish(69, failure);
          } else {
            reopened.Ready();
            reopened.Observe(1);
            reopened.Observe(2, "0002", 4, nullptr, 4000);
            reopened.Closed();
          }
        }
      } else if (mode == "term" || mode == "interrupt") {
        child.Signal(mode == "term" ? SIGTERM : SIGINT);
        child.Finish(75, failure);
      } else if (mode == "output-lost") {
        child.EndOutput();
        child.Finish(74, failure);
      } else {
        if (mode == "input-eof") child.EndInput();
        else if (mode == "partial-input") {
          child.Send("{\"v\":1");
          child.EndInput();
        } else if (mode == "malformed") child.Send("private-input-canary\n");
        else if (mode == "generation") {
          auto close = Control("close");
          close.replace(close.find(generation), generation.size(), std::string(32, 'f'));
          child.Send(close);
        } else if (mode == "replay") {
          child.Observe(1);
          child.Send(Json({{"v", 1},
                           {"backend", "matter-bridge"},
                           {"type", "clock-probe"},
                           {"generation", generation},
                           {"id", "1"}})
                         .dump() +
                     "\n");
          assert(Json::parse(child.Line())["type"] == "clock-sample");
          child.Send(Json({{"v", 1},
                           {"backend", "matter-bridge"},
                           {"type", "clock-probe"},
                           {"generation", generation},
                           {"id", "1"}})
                         .dump() +
                     "\n");
        } else assert(false && "unknown executable probe");
        child.Finish(65, failure);
      }
    }
  }
  std::filesystem::remove_all(root);
  std::cout << "production bridge executable and pipes passed\n";
  return 0;
}
} // namespace wotex::matter::testing
