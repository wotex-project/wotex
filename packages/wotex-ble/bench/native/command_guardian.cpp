// SPDX-License-Identifier: Apache-2.0
// The build and fixture command guardian of the BLE package
// (priv/bluez/native/build_command.c) with the native build's limits: 600 s,
// 16 MiB of output and a 5,000 ms cleanup allowance. A command runs in its
// own process group with /dev/null as stdin while the owner holds the
// liveness pipe open: /usr/bin/true, whose exit ends the command, and
// /bin/cat of a 1 MiB file in the scratch directory, whose output the
// guardian forwards through its bounded queue. The driver forks and runs the
// guardian's main (renamed at compile time) in the child, so the guardian's
// own exec is not measured; the command's is.
#include <array>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" {
int wbl_command_main(int argc, char **argv);
}

namespace {

constexpr std::size_t file_bytes = 1048576;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "command_guardian: " << what << " failed (errno " << errno << ")\n";
  std::exit(1);
}

void close_on_exec(int descriptor) {
  check(::fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0, "close-on-exec");
}

// Runs one command through the guardian and returns the bytes it forwarded.
class Command {
  std::vector<std::string> words_;

 public:
  Command(const std::string &scratch, std::vector<std::string> command)
      : words_{"command", "600000", "16777216", "5000", scratch} {
    words_.insert(words_.end(), command.begin(), command.end());
  }

  std::size_t run() {
    std::array<int, 2> liveness{-1, -1}, output{-1, -1};
    check(::pipe(liveness.data()) == 0 && ::pipe(output.data()) == 0, "owner pipes");
    for (const int descriptor : {liveness[0], liveness[1], output[0], output[1]})
      close_on_exec(descriptor);
    std::vector<char *> argv;
    argv.reserve(words_.size() + 1);
    for (std::string &word : words_) argv.push_back(word.data());
    argv.push_back(nullptr);
    const pid_t pid = ::fork();
    check(pid >= 0, "fork");
    if (pid == 0) {
      if (::dup2(liveness[0], STDIN_FILENO) < 0 || ::dup2(output[1], STDOUT_FILENO) < 0)
        ::_exit(120);
      for (const int descriptor : {liveness[0], liveness[1], output[0], output[1]})
        ::close(descriptor);
      ::_exit(wbl_command_main(static_cast<int>(argv.size() - 1), argv.data()));
    }
    ::close(liveness[0]);
    ::close(output[1]);
    std::array<char, 65536> buffer{};
    std::size_t forwarded = 0;
    for (;;) {
      const ssize_t count = ::read(output[0], buffer.data(), buffer.size());
      if (count < 0 && errno == EINTR) continue;
      check(count >= 0, "owner read");
      if (count == 0) break;
      forwarded += static_cast<std::size_t>(count);
    }
    int status = 0;
    pid_t reaped = -1;
    do reaped = ::waitpid(pid, &status, 0);
    while (reaped < 0 && errno == EINTR);
    ::close(liveness[1]);
    ::close(output[0]);
    check(reaped == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0, "command status");
    return forwarded;
  }
};

} // namespace

int main() {
  const char *scratch = std::getenv("WOTEX_BLE_BENCH_SCRATCH");
  check(scratch != nullptr && scratch[0] == '/', "WOTEX_BLE_BENCH_SCRATCH");
  check(std::signal(SIGPIPE, SIG_IGN) != SIG_ERR, "ignore SIGPIPE");
  for (const char *executable : {"/bin/cat", "/usr/bin/true"})
    check(::access(executable, X_OK) == 0, "command executable");

  const std::string file = std::string(scratch) + "/output.bin";
  {
    const int descriptor = ::open(file.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    check(descriptor >= 0, "create output file");
    std::string bytes(file_bytes, '\0');
    for (std::size_t index = 0; index < bytes.size(); ++index)
      bytes[index] = static_cast<char>(index % 251);
    check(::write(descriptor, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()),
          "write output file");
    check(::close(descriptor) == 0, "close output file");
  }
  Command exiting(scratch, {"/usr/bin/true"});
  Command forwarding(scratch, {"/bin/cat", file});
  check(exiting.run() == 0 && forwarding.run() == file_bytes, "forwarded bytes");

  ankerl::nanobench::Bench bench;
  bench.title("command guardian")
      .unit("command")
      .warmup(3)
      .epochs(21)
      .minEpochIterations(10)
      .minEpochTime(std::chrono::milliseconds(1));
  bench.run("run /usr/bin/true", [&] { check(exiting.run() == 0, "no output"); });

  bench.title("command guardian output").unit("byte").batch(file_bytes);
  bench.run("forward 1 MiB from /bin/cat",
            [&] { check(forwarding.run() == file_bytes, "forwarded bytes"); });
  return 0;
}
