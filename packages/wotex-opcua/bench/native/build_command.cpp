// SPDX-License-Identifier: Apache-2.0
// The build command guardian of the OPC UA native build
// (priv/native/build_command.c), through which Wotex.OPCUA.Native.Command runs
// every recipe step. The benchmark compiles it with its main renamed and runs it
// in a forked child whose standard input is an owner-liveness pipe and whose
// standard output is a pipe the driver reads, as the Mix owner runs the
// executable, so the guardian's own exec is not measured. The guarded command
// is this driver re-executed in a child mode. A row spawns the command,
// collects its output until EOF and checks both exit statuses and the byte
// count; the direct rows spawn the same command without the guardian.
#include <algorithm>
#include <chrono>
#include <cerrno>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <nanobench.h>

// priv/native/build_command.c, compiled with -Dmain=wotex_opcua_build_command_main.
extern "C" int wotex_opcua_build_command_main(int argc, char **argv);

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "build_command: " << what << " failed\n";
  std::exit(1);
}

void write_all(int descriptor, const char *bytes, std::size_t size) {
  while (size > 0) {
    const ssize_t count = write(descriptor, bytes, size);
    if (count < 0 && errno == EINTR) continue;
    check(count > 0, "write");
    bytes += count;
    size -= static_cast<std::size_t>(count);
  }
}

// Child mode: writes `bytes` bytes to standard output and exits.
int emit(const char *text) {
  char *end = nullptr;
  const unsigned long long total = std::strtoull(text, &end, 10);
  if (!end || *end) return 2;
  std::vector<char> chunk(65536, 'x');
  for (unsigned long long sent = 0; sent < total;) {
    const std::size_t size = static_cast<std::size_t>(
        std::min<unsigned long long>(chunk.size(), total - sent));
    write_all(STDOUT_FILENO, chunk.data(), size);
    sent += size;
  }
  return 0;
}

// Reads `descriptor` until EOF and returns the byte count.
std::size_t collect(int descriptor) {
  static char buffer[65536];
  std::size_t total = 0;
  for (;;) {
    const ssize_t count = read(descriptor, buffer, sizeof(buffer));
    if (count < 0 && errno == EINTR) continue;
    check(count >= 0, "read");
    if (count == 0) return total;
    total += static_cast<std::size_t>(count);
  }
}

int reap(pid_t child) {
  int status = 0;
  while (waitpid(child, &status, 0) < 0) check(errno == EINTR, "waitpid");
  check(WIFEXITED(status), "normal exit");
  return WEXITSTATUS(status);
}

std::vector<char *> argv_of(std::vector<std::string> &arguments) {
  std::vector<char *> argv;
  argv.reserve(arguments.size() + 1);
  for (std::string &argument : arguments) argv.push_back(argument.data());
  argv.push_back(nullptr);
  return argv;
}

// Runs `arguments` (an absolute executable and its arguments) with /dev/null
// input and combined output, directly or through the guardian.
void command(std::vector<std::string> arguments, bool guarded, std::size_t expected) {
  int owner[2];
  int output[2];
  check(pipe(owner) == 0 && pipe(output) == 0, "pipe");
  if (guarded) {
    arguments.insert(arguments.begin(), {"build-command", "60000", "16777216", "1000", "/"});
  }
  std::vector<char *> argv = argv_of(arguments);
  const pid_t child = fork();
  check(child >= 0, "fork");
  if (child == 0) {
    const int input = guarded ? owner[0] : open("/dev/null", O_RDONLY);
    if (input < 0 || dup2(input, STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0 ||
        (!guarded && dup2(output[1], STDERR_FILENO) < 0))
      _exit(126);
    for (const int descriptor : {owner[0], owner[1], output[0], output[1]}) close(descriptor);
    if (guarded)
      _exit(wotex_opcua_build_command_main(static_cast<int>(argv.size() - 1), argv.data()));
    execv(argv[0], argv.data());
    _exit(126);
  }
  close(owner[0]);
  close(output[1]);
  check(collect(output[0]) == expected, "output bytes");
  close(output[0]);
  check(reap(child) == 0, "exit status");
  close(owner[1]);
}

} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::strcmp(argv[1], "--exit") == 0) return 0;
  if (argc == 3 && std::strcmp(argv[1], "--emit") == 0) return emit(argv[2]);
  check(argc == 1, "arguments");

  char self[PATH_MAX];
  check(realpath(argv[0], self) != nullptr && self[0] == '/', "absolute driver path");
  signal(SIGPIPE, SIG_IGN);

  ankerl::nanobench::Bench commands;
  // The guardian waits in polls of up to 10 ms, so the time of a single
  // command varies; each epoch averages at least 30 commands.
  commands.title("command").unit("command").warmup(3).epochs(10).minEpochIterations(30);
  commands.run("command that exits, without the guardian",
               [&] { command({self, "--exit"}, false, 0); });
  commands.run("command that exits, guarded", [&] { command({self, "--exit"}, true, 0); });
  commands.run("command writing 1 MiB, without the guardian",
               [&] { command({self, "--emit", "1048576"}, false, 1048576); });
  commands.run("command writing 1 MiB, guarded",
               [&] { command({self, "--emit", "1048576"}, true, 1048576); });
  return 0;
}
