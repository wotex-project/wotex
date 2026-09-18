// SPDX-License-Identifier: Apache-2.0
// The runtime custody guardian of the OPC UA host (priv/native/custody.c),
// which relays opaque bytes between the BEAM host and the SDK executable. The
// benchmark compiles it with its main renamed and runs it in a forked child
// whose standard input and output are pipes owned by the driver, as the BEAM
// Port runs the executable, with the OPC UA profile's limits (500 ms cleanup,
// 131072-byte input and 65536-byte output queues), so the guardian's own exec
// is not measured. The child it guards is this driver re-executed as a line
// echo, the stand-in for the SDK host. The rows without custody talk to the
// same echo process over plain pipes as the baseline.
#include <chrono>
#include <cerrno>
#include <climits>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <nanobench.h>

// priv/native/custody.c, compiled with -Dmain=wotex_opcua_custody_main.
extern "C" int wotex_opcua_custody_main(int argc, char **argv);

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "custody: " << what << " failed\n";
  std::exit(1);
}

bool write_all(int descriptor, const char *bytes, std::size_t size) {
  while (size > 0) {
    const ssize_t count = write(descriptor, bytes, size);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    bytes += count;
    size -= static_cast<std::size_t>(count);
  }
  return true;
}

// Child mode: echoes each LF-terminated line until the line `quit`.
int echo() {
  static char buffer[1 << 17];
  std::size_t used = 0;
  for (;;) {
    const ssize_t count = read(STDIN_FILENO, buffer + used, sizeof(buffer) - used);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return count == 0 ? 3 : 4;
    used += static_cast<std::size_t>(count);
    std::size_t start = 0;
    for (std::size_t i = 0; i < used; ++i) {
      if (buffer[i] != '\n') continue;
      if (i - start == 4 && std::memcmp(buffer + start, "quit", 4) == 0) return 0;
      if (!write_all(STDOUT_FILENO, buffer + start, i + 1 - start)) return 5;
      start = i + 1;
    }
    std::memmove(buffer, buffer + start, used - start);
    used -= start;
    if (used == sizeof(buffer)) return 6;
  }
}

// One echo process, directly or under custody, with the driver's pipe ends.
class Session {
 public:
  Session(const char *self, bool guarded) {
    int input[2];
    int output[2];
    check(pipe(input) == 0 && pipe(output) == 0, "pipe");
    std::vector<std::string> arguments = {self, "--echo"};
    if (guarded) arguments.insert(arguments.begin(), {"custody", "500", "131072", "65536", "/"});
    std::vector<char *> argv;
    argv.reserve(arguments.size() + 1);
    for (std::string &argument : arguments) argv.push_back(argument.data());
    argv.push_back(nullptr);
    child_ = fork();
    check(child_ >= 0, "fork");
    if (child_ == 0) {
      if (dup2(input[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0) _exit(126);
      for (const int descriptor : {input[0], input[1], output[0], output[1]}) close(descriptor);
      if (guarded) _exit(wotex_opcua_custody_main(static_cast<int>(argv.size() - 1), argv.data()));
      execv(argv[0], argv.data());
      _exit(126);
    }
    close(input[0]);
    close(output[1]);
    to_child_ = input[1];
    from_child_ = output[0];
  }
  ~Session() {
    if (to_child_ >= 0) close(to_child_);
    if (from_child_ >= 0) close(from_child_);
    if (child_ > 0) (void)waitpid(child_, nullptr, 0);
  }
  Session(const Session &) = delete;
  Session &operator=(const Session &) = delete;
  Session(Session &&) = delete;
  Session &operator=(Session &&) = delete;

  // Sends `line` and reads the same bytes back.
  void round_trip(const std::string &line) {
    check(write_all(to_child_, line.data(), line.size()), "line write");
    for (std::size_t used = 0; used < line.size();) {
      const ssize_t count = read(from_child_, reply_.data() + used, line.size() - used);
      if (count < 0 && errno == EINTR) continue;
      check(count > 0, "echo read");
      used += static_cast<std::size_t>(count);
    }
    check(std::memcmp(reply_.data(), line.data(), line.size()) == 0, "echoed bytes");
  }

  // Ends the echo with `quit`, reads to EOF and checks a clean exit.
  void finish() {
    check(write_all(to_child_, "quit\n", 5), "quit write");
    char byte = 0;
    ssize_t count = 0;
    do count = read(from_child_, &byte, 1);
    while (count < 0 && errno == EINTR);
    check(count == 0, "EOF after quit");
    int status = 0;
    while (waitpid(child_, &status, 0) < 0) check(errno == EINTR, "waitpid");
    child_ = -1;
    check(WIFEXITED(status) && WEXITSTATUS(status) == 0, "clean exit");
  }

 private:
  pid_t child_ = -1;
  int to_child_ = -1;
  int from_child_ = -1;
  std::vector<char> reply_ = std::vector<char>(1 << 17);
};

std::string line_of(std::size_t size) { return std::string(size - 1, 'v') + "\n"; }

} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::strcmp(argv[1], "--echo") == 0) return echo();
  check(argc == 1, "arguments");

  char self[PATH_MAX];
  check(realpath(argv[0], self) != nullptr && self[0] == '/', "absolute driver path");
  signal(SIGPIPE, SIG_IGN);
  const std::string small = line_of(256);
  const std::string large = line_of(16384);

  ankerl::nanobench::Bench trips;
  trips.title("relay").unit("round trip").warmup(100).minEpochTime(std::chrono::milliseconds(30));
  for (const std::string *line : {&small, &large}) {
    const std::string size = line == &small ? "256 B" : "16 KiB";
    for (const bool guarded : {false, true}) {
      auto session = std::make_unique<Session>(self, guarded);
      trips.run(size + (guarded ? " line through custody" : " line, without custody"),
                [&] { session->round_trip(*line); });
      session->finish();
    }
  }

  ankerl::nanobench::Bench sessions;
  sessions.title("lifecycle").unit("session").warmup(3).epochs(10).minEpochIterations(30);
  for (const bool guarded : {false, true}) {
    sessions.run(std::string("start, one 256 B round trip and clean exit") +
                     (guarded ? ", through custody" : ", without custody"),
                 [&] {
      Session session(self, guarded);
      session.round_trip(small);
      session.finish();
    });
  }
  return 0;
}
