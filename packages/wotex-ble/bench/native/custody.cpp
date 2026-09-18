// SPDX-License-Identifier: Apache-2.0
// The runtime guardian of the BLE native host (priv/bluez/native/custody.c,
// runtime-guardian.md) with the BLE profile's limits: CLEANUP_MS 500, 131,072
// input and 65,536 output bytes. The relay rows send a 256-byte line and a
// 64 KiB burst from the owner through the guardian to an echoing SDK child
// (/bin/cat) and read them back. The session rows start a guardian and end
// it: the SDK exits (/usr/bin/true) and is reaped, or the owner closes its
// input and the guardian tears the SDK (/bin/cat) down. The driver forks and
// runs the guardian's main (renamed at compile time) in the child, so the
// guardian's own exec is not measured; the SDK's is. The guardian's working
// directory is the benchmark's scratch directory.
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
#include <poll.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" {
int wbl_custody_main(int argc, char **argv);
}

namespace {

constexpr int owner_loss = 127;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "custody: " << what << " failed (errno " << errno << ")\n";
  std::exit(1);
}

void flags(int descriptor, int descriptor_flags, int status_flags) {
  check(::fcntl(descriptor, F_SETFD, descriptor_flags) == 0, "descriptor flags");
  const int current = ::fcntl(descriptor, F_GETFL);
  check(current >= 0 && ::fcntl(descriptor, F_SETFL, current | status_flags) == 0, "status flags");
}

// A guardian process: `input` writes its stdin, `output` reads its stdout.
struct Guardian {
  pid_t pid = -1;
  int input = -1;
  int output = -1;
};

class Launcher {
  std::vector<std::string> words_;

 public:
  Launcher(const std::string &scratch, const char *sdk)
      : words_{"custody", "500", "131072", "65536", scratch, sdk} {}

  Guardian start() {
    std::array<int, 2> in{-1, -1}, out{-1, -1};
    check(::pipe(in.data()) == 0 && ::pipe(out.data()) == 0, "owner pipes");
    for (const int descriptor : {in[0], in[1], out[0], out[1]}) flags(descriptor, FD_CLOEXEC, 0);
    std::vector<char *> argv;
    argv.reserve(words_.size() + 1);
    for (std::string &word : words_) argv.push_back(word.data());
    argv.push_back(nullptr);
    const pid_t pid = ::fork();
    check(pid >= 0, "fork");
    if (pid == 0) {
      if (::dup2(in[0], STDIN_FILENO) < 0 || ::dup2(out[1], STDOUT_FILENO) < 0) ::_exit(120);
      for (const int descriptor : {in[0], in[1], out[0], out[1]}) ::close(descriptor);
      ::_exit(wbl_custody_main(static_cast<int>(argv.size() - 1), argv.data()));
    }
    ::close(in[0]);
    ::close(out[1]);
    flags(in[1], FD_CLOEXEC, O_NONBLOCK);
    flags(out[0], FD_CLOEXEC, O_NONBLOCK);
    return {pid, in[1], out[0]};
  }
};

int finish(Guardian &guardian) {
  if (guardian.input >= 0) ::close(guardian.input);
  int status = 0;
  pid_t reaped = -1;
  do reaped = ::waitpid(guardian.pid, &status, 0);
  while (reaped < 0 && errno == EINTR);
  check(reaped == guardian.pid && WIFEXITED(status), "guardian exit");
  ::close(guardian.output);
  guardian = {};
  return WEXITSTATUS(status);
}

// Writes `frame` to the guardian and reads its echo back, both nonblocking.
void round_trip(const Guardian &guardian, const std::string &frame, std::string &echo) {
  std::size_t sent = 0, received = 0;
  while (received < frame.size()) {
    std::array<pollfd, 2> ready{
        {{sent < frame.size() ? guardian.input : -1, POLLOUT, 0}, {guardian.output, POLLIN, 0}}};
    check(::poll(ready.data(), ready.size(), 5000) > 0, "relay progress");
    if (ready[0].revents & POLLOUT) {
      const ssize_t count = ::write(guardian.input, frame.data() + sent, frame.size() - sent);
      check(count > 0 || errno == EAGAIN || errno == EINTR, "owner write");
      if (count > 0) sent += static_cast<std::size_t>(count);
    }
    if (ready[1].revents & (POLLIN | POLLHUP | POLLERR)) {
      const ssize_t count = ::read(guardian.output, echo.data() + received, echo.size() - received);
      check(count > 0 || (count < 0 && (errno == EAGAIN || errno == EINTR)), "owner read");
      if (count > 0) received += static_cast<std::size_t>(count);
    }
  }
  check(echo == frame, "echo");
}

std::string line(std::size_t size) {
  std::string frame(size, '\0');
  for (std::size_t index = 0; index + 1 < size; ++index)
    frame[index] = static_cast<char>('a' + index % 26);
  frame.back() = '\n';
  return frame;
}

} // namespace

int main() {
  const char *scratch = std::getenv("WOTEX_BLE_BENCH_SCRATCH");
  check(scratch != nullptr && scratch[0] == '/', "WOTEX_BLE_BENCH_SCRATCH");
  check(std::signal(SIGPIPE, SIG_IGN) != SIG_ERR, "ignore SIGPIPE");
  for (const char *sdk : {"/bin/cat", "/usr/bin/true"})
    check(::access(sdk, X_OK) == 0, "SDK stand-in executable");
  Launcher echo(scratch, "/bin/cat");
  Launcher exiting(scratch, "/usr/bin/true");

  ankerl::nanobench::Bench bench;
  bench.title("custody relay")
      .unit("round trip")
      .warmup(50)
      .minEpochTime(std::chrono::milliseconds(50));
  Guardian relay = echo.start();
  const std::string small = line(256);
  std::string small_echo(small.size(), '\0');
  round_trip(relay, small, small_echo);
  bench.run("256 B line through the guardian and /bin/cat",
            [&] { round_trip(relay, small, small_echo); });

  const std::string burst = line(65536);
  std::string burst_echo(burst.size(), '\0');
  round_trip(relay, burst, burst_echo);
  bench.title("custody relay throughput").unit("byte").batch(burst.size());
  bench.run("64 KiB burst through the guardian and /bin/cat",
            [&] { round_trip(relay, burst, burst_echo); });
  check(finish(relay) == owner_loss, "owner-loss status");

  bench.title("custody sessions")
      .unit("session")
      .batch(1)
      .warmup(3)
      .epochs(21)
      .minEpochIterations(10)
      .minEpochTime(std::chrono::milliseconds(1));
  bench.run("start, SDK exit and reap (/usr/bin/true)", [&] {
    Guardian guardian = exiting.start();
    std::array<char, 16> bytes{};
    ssize_t count = -1;
    do {
      pollfd ready{guardian.output, POLLIN, 0};
      check(::poll(&ready, 1, 5000) > 0, "stdout end");
      count = ::read(guardian.output, bytes.data(), bytes.size());
    } while (count < 0 && (errno == EAGAIN || errno == EINTR));
    check(count == 0, "no SDK output");
    check(finish(guardian) == 0, "SDK status");
  });
  bench.run("start, owner EOF and teardown (/bin/cat)", [&] {
    Guardian guardian = echo.start();
    check(finish(guardian) == owner_loss, "owner-loss status");
  });
  return 0;
}
