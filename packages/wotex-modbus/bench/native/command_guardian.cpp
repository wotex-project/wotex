// SPDX-License-Identifier: Apache-2.0
// The command guardian of the software lane (test/interop/native/command.c),
// linked with its main() renamed to wmb_command_main. Argument validation runs
// in this process; the other cases run the guardian in a child with an owner
// liveness pipe on stdin and its bounded output on stdout, supervising this
// executable again as the command, which writes a given number of bytes or
// waits for a signal. A baseline spawns that command without the guardian.
// Each case asserts the exit status and the exact number of bytes relayed.
#include <cerrno>
#include <chrono>
#include <climits>
#include <csignal>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" int wmb_command_main(int argc, char **argv);

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "command_guardian: " << what << " failed\n";
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

// The command: writes `text` bytes to stdout, or waits for a signal.
int command(const char *mode, const char *text) {
  if (std::strcmp(mode, "--wait") == 0) {
    for (;;) pause();
  }
  char *end = nullptr;
  const unsigned long long total = std::strtoull(text, &end, 10);
  if (std::strcmp(mode, "--emit") != 0 || end == text || *end != '\0') return 2;
  std::vector<char> block(4096, 'x');
  for (unsigned long long left = total; left > 0;) {
    const std::size_t size = left < block.size() ? static_cast<std::size_t>(left) : block.size();
    if (!write_all(STDOUT_FILENO, block.data(), size)) return 3;
    left -= size;
  }
  return 0;
}

class Arguments {
 public:
  explicit Arguments(std::vector<std::string> values) : values_(std::move(values)) {
    pointers_.reserve(values_.size() + 1);
    for (std::string &value : values_) pointers_.push_back(value.data());
    pointers_.push_back(nullptr);
  }
  int argc() const { return static_cast<int>(values_.size()); }
  char **argv() { return pointers_.data(); }

 private:
  std::vector<std::string> values_;
  std::vector<char *> pointers_;
};

struct Run {
  pid_t pid = -1;
  int owner = -1;
  int output = -1;
};

void owned_pipe(int descriptors[2]) {
  check(pipe(descriptors) == 0 && fcntl(descriptors[0], F_SETFD, FD_CLOEXEC) == 0 &&
            fcntl(descriptors[1], F_SETFD, FD_CLOEXEC) == 0,
        "pipe");
}

// Starts the guardian in a child: stdin is the owner's liveness pipe, stdout
// the guardian's relayed output.
Run start(Arguments &arguments) {
  int owner[2];
  int output[2];
  owned_pipe(owner);
  owned_pipe(output);
  Run run;
  run.pid = fork();
  check(run.pid >= 0, "fork");
  if (run.pid == 0) {
    if (dup2(owner[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0) _exit(126);
    for (const int descriptor : {owner[0], owner[1], output[0], output[1]}) close(descriptor);
    _exit(wmb_command_main(arguments.argc(), arguments.argv()));
  }
  close(owner[0]);
  close(output[1]);
  run.owner = owner[1];
  run.output = output[0];
  return run;
}

// Starts the command itself, without the guardian, as the baseline.
Run spawn_direct(Arguments &arguments) {
  int output[2];
  owned_pipe(output);
  Run run;
  run.pid = fork();
  check(run.pid >= 0, "fork");
  if (run.pid == 0) {
    if (dup2(output[1], STDOUT_FILENO) < 0) _exit(126);
    execv(arguments.argv()[0], arguments.argv());
    _exit(126);
  }
  close(output[1]);
  run.output = output[0];
  return run;
}

// Reads the child's output to its end, then reaps it; returns the byte count.
std::size_t drain(Run &run, int expected_status, std::vector<char> &buffer) {
  std::size_t total = 0;
  for (;;) {
    const ssize_t count = read(run.output, buffer.data(), buffer.size());
    if (count < 0 && errno == EINTR) continue;
    check(count >= 0, "output read");
    if (count == 0) break;
    total += static_cast<std::size_t>(count);
  }
  if (run.owner >= 0) close(run.owner);
  close(run.output);
  int status = 0;
  check(waitpid(run.pid, &status, 0) == run.pid && WIFEXITED(status) &&
            WEXITSTATUS(status) == expected_status,
        "exit status");
  run = Run{};
  return total;
}

struct Case {
  const char *name;
  std::string timeout, limit, mode, count;
  int status;
  std::size_t relayed;
};

} // namespace

int main(int argc, char **argv) {
  if (argc == 3) return command(argv[1], argv[2]);
  check(argc == 1, "no arguments");
  char self[PATH_MAX];
  check(realpath(argv[0], self) != nullptr, "realpath of the executable");
  const char *scratch = std::getenv("WMB_BENCH_SCRATCH");
  check(scratch != nullptr, "WMB_BENCH_SCRATCH");
  check(std::signal(SIGPIPE, SIG_IGN) != SIG_ERR, "ignore SIGPIPE");

  ankerl::nanobench::Bench bench;
  bench.title("command guardian").warmup(3).minEpochTime(std::chrono::milliseconds(50));

  // Each vector fails the guardian's argument or bounds check (status 126)
  // before it installs a handler, opens a pipe or forks.
  const std::string guardian = "command";
  std::vector<Arguments> invalid;
  invalid.reserve(8);
  invalid.emplace_back(std::vector<std::string>{guardian, "1000", "65536", "400", "/"});
  invalid.emplace_back(std::vector<std::string>{guardian, "0", "65536", "400", "/", self});
  invalid.emplace_back(std::vector<std::string>{guardian, "600001", "65536", "400", "/", self});
  invalid.emplace_back(std::vector<std::string>{guardian, "1000", "16777217", "400", "/", self});
  invalid.emplace_back(std::vector<std::string>{guardian, "1000", "65536", "5001", "/", self});
  invalid.emplace_back(std::vector<std::string>{guardian, "1e3", "65536", "400", "/", self});
  invalid.emplace_back(std::vector<std::string>{guardian, "1000", "65536", "400", "tmp", self});
  invalid.emplace_back(std::vector<std::string>{guardian, "1000", "65536", "400", "/", "probe"});
  bench.unit("vector").batch(invalid.size()).run("reject 8 invalid argument vectors", [&] {
    for (Arguments &arguments : invalid)
      check(wmb_command_main(arguments.argc(), arguments.argv()) == 126, "rejection");
  });

  std::vector<char> buffer(65536);
  const std::vector<Case> cases = {
      {"run a command that exits at once", "5000", "65536", "--emit", "0", 0, 0},
      {"relay 64 KiB of output", "5000", "16777216", "--emit", "65536", 0, 65536},
      {"relay 1 MiB of output", "5000", "16777216", "--emit", "1048576", 0, 1048576},
      {"stop 1 MiB of output at a 64 KiB bound", "5000", "65536", "--emit", "1048576", 125, 65536},
      {"stop a waiting command at a 20 ms deadline", "20", "65536", "--wait", "0", 124, 0},
  };
  // The guardian polls every 10 ms, so longer epochs average its quantization.
  bench.batch(1).unit("command").minEpochTime(std::chrono::milliseconds(250));
  Arguments direct({self, "--emit", "0"});
  bench.run("baseline: the same command without the guardian", [&] {
    Run run = spawn_direct(direct);
    check(drain(run, 0, buffer) == 0, "direct command");
  });
  for (const Case &entry : cases) {
    Arguments arguments(
        {guardian, entry.timeout, entry.limit, "400", "/", self, entry.mode, entry.count});
    bench.run(entry.name, [&] {
      Run run = start(arguments);
      check(drain(run, entry.status, buffer) == entry.relayed, entry.name);
    });
  }

  // The fixture lock: acquire, report readiness, release on the owner's `R`.
  char resolved[PATH_MAX];
  check(realpath(scratch, resolved) != nullptr, "realpath WMB_BENCH_SCRATCH");
  const std::string path = std::string(resolved) + "/fixture.lock";
  Arguments lock({guardian, "--lock", path});
  bench.run("acquire and release the fixture lock", [&] {
    static const char ready[] = "wotex_fixture_lock\n";
    static const char released[] = "wotex_fixture_unlocked\n";
    Run run = start(lock);
    char text[sizeof(released)] = {};
    std::size_t used = 0;
    while (used < sizeof(ready) - 1) {
      const ssize_t count = read(run.output, text + used, sizeof(ready) - 1 - used);
      check(count > 0, "lock readiness");
      used += static_cast<std::size_t>(count);
    }
    check(std::memcmp(text, ready, used) == 0, "lock readiness");
    check(write_all(run.owner, "R", 1), "lock release request");
    check(drain(run, 0, buffer) == sizeof(released) - 1, "lock release");
  });
  (void)unlink(path.c_str());
  return 0;
}
