// SPDX-License-Identifier: Apache-2.0
// Process custody of the native OSCORE helper (native/oscore/custody.c): the
// guardian that owns the worker's process group and relays its two byte
// streams through bounded queues. The guardian runs in a child of this driver
// with the arguments main.c gives it; the worker is this executable again in
// its echo mode, which returns every byte and exits after a `close` line.
// Measured: a whole lifecycle (guardian and worker start, one 256-byte line,
// close, worker exit, guardian reap) and line round trips through a running
// guardian (owner, guardian, worker and back).
#include <cerrno>
#include <chrono>
#include <climits>
#include <csignal>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" int wco_custody_main(int argc, char **argv);

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "oscore_custody: " << what << " failed\n";
  std::exit(1);
}

bool write_all(int descriptor, const char *bytes, std::size_t length) {
  while (length > 0) {
    const ssize_t written = write(descriptor, bytes, length);
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) return false;
    bytes += written;
    length -= static_cast<std::size_t>(written);
  }
  return true;
}

// Reads exactly `length` bytes; false on end of stream or error.
bool read_exact(int descriptor, char *bytes, std::size_t length) {
  while (length > 0) {
    const ssize_t count = read(descriptor, bytes, length);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    bytes += count;
    length -= static_cast<std::size_t>(count);
  }
  return true;
}

// The worker: echoes stdin to stdout and exits 0 once a whole `close` line or
// end of input has been echoed.
int echo_worker() {
  static const char close_line[] = "close\n";
  std::vector<char> buffer(65536);
  std::size_t matched = 0;
  bool line_start = true;
  for (;;) {
    const ssize_t count = read(STDIN_FILENO, buffer.data(), buffer.size());
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return count == 0 ? 0 : 3;
    if (!write_all(STDOUT_FILENO, buffer.data(), static_cast<std::size_t>(count))) return 3;
    for (ssize_t index = 0; index < count; ++index) {
      const char byte = buffer[static_cast<std::size_t>(index)];
      if ((line_start || matched > 0) && byte == close_line[matched]) {
        if (++matched == sizeof(close_line) - 1) return 0;
      } else {
        matched = 0;
      }
      line_start = byte == '\n';
    }
  }
}

void owned_pipe(int descriptors[2]) {
  check(pipe(descriptors) == 0 && fcntl(descriptors[0], F_SETFD, FD_CLOEXEC) == 0 &&
            fcntl(descriptors[1], F_SETFD, FD_CLOEXEC) == 0,
        "pipe");
}

struct Child {
  pid_t pid = -1;
  int input = -1;
  int output = -1;
};

// Starts custody as main.c does: 500 ms cleanup, 256 KiB queues, `/` as the
// worker's directory and this executable as the worker.
Child start(const std::string &self) {
  int input[2];
  int output[2];
  owned_pipe(input);
  owned_pipe(output);
  Child guardian;
  guardian.pid = fork();
  check(guardian.pid >= 0, "fork");
  if (guardian.pid == 0) {
    if (dup2(input[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0) _exit(126);
    std::vector<std::string> arguments = {self, "500", "262144",       "262144",
                                          "/",  self,  "--echo-worker"};
    std::vector<char *> argv;
    argv.reserve(arguments.size() + 1);
    for (std::string &argument : arguments) argv.push_back(argument.data());
    argv.push_back(nullptr);
    _exit(wco_custody_main(static_cast<int>(arguments.size()), argv.data()));
  }
  close(input[0]);
  close(output[1]);
  guardian.input = input[1];
  guardian.output = output[0];
  return guardian;
}

// Starts the worker itself, without custody, as the baseline.
Child spawn_direct(const std::string &self) {
  int input[2];
  int output[2];
  owned_pipe(input);
  owned_pipe(output);
  Child worker;
  worker.pid = fork();
  check(worker.pid >= 0, "fork");
  if (worker.pid == 0) {
    if (dup2(input[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0) _exit(126);
    std::string path = self;
    std::string mode = "--echo-worker";
    char *argv[] = {path.data(), mode.data(), nullptr};
    execv(path.c_str(), argv);
    _exit(126);
  }
  close(input[0]);
  close(output[1]);
  worker.input = input[1];
  worker.output = output[0];
  return worker;
}

void round_trip(const Child &child, const std::string &line, std::vector<char> &echo) {
  check(write_all(child.input, line.data(), line.size()), "line write");
  check(read_exact(child.output, echo.data(), line.size()), "line echo");
}

// Sends `close`, reads to the end of the output and reaps the process.
void finish(Child &child) {
  static const std::string close_line = "close\n";
  std::vector<char> echo(close_line.size());
  round_trip(child, close_line, echo);
  char extra = 0;
  check(read(child.output, &extra, 1) == 0, "end of output");
  int status = 0;
  check(
      waitpid(child.pid, &status, 0) == child.pid && WIFEXITED(status) && WEXITSTATUS(status) == 0,
      "exit status 0");
  close(child.input);
  close(child.output);
  child = Child{};
}

std::string line(std::size_t size) {
  std::string text(size - 1, 'a');
  text += '\n';
  return text;
}

} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::strcmp(argv[1], "--echo-worker") == 0) return echo_worker();
  check(argc == 1, "no arguments");
  char self[PATH_MAX];
  check(realpath(argv[0], self) != nullptr, "realpath of the executable");
  check(std::signal(SIGPIPE, SIG_IGN) != SIG_ERR, "ignore SIGPIPE");

  ankerl::nanobench::Bench bench;
  bench.title("custody").warmup(3);

  const std::string first = line(256);
  std::vector<char> echo(32768);
  // Longer epochs for a whole process lifecycle.
  bench.unit("worker").minEpochTime(std::chrono::milliseconds(250));
  bench.run("start, echo one line, close and reap", [&] {
    Child guardian = start(self);
    round_trip(guardian, first, echo);
    check(std::memcmp(echo.data(), first.data(), first.size()) == 0, "echo contents");
    finish(guardian);
  });

  bench.run("baseline: the same worker without custody", [&] {
    Child worker = spawn_direct(self);
    round_trip(worker, first, echo);
    finish(worker);
  });

  bench.minEpochTime(std::chrono::milliseconds(50));
  Child guardian = start(self);
  for (const std::size_t size : {256U, 4096U, 32768U}) {
    const std::string text = line(size);
    round_trip(guardian, text, echo);
    check(std::memcmp(echo.data(), text.data(), text.size()) == 0, "echo contents");
    const std::string name = "round trip of a " +
        (size < 1024 ? std::to_string(size) + " B" : std::to_string(size / 1024) + " KiB") +
        " line";
    bench.unit("line").run(name, [&] { round_trip(guardian, text, echo); });
  }
  finish(guardian);
  return 0;
}
