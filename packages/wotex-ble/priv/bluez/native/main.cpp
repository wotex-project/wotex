// SPDX-License-Identifier: Apache-2.0
// Direct SDK executable: no argv configuration, stdout diagnostics or runtime
// interpreter. The separate custody executable owns forced teardown and reaping.
#include "host.hpp"
#include <array>
#include <csignal>
#include <sys/random.h>

namespace {
volatile std::sig_atomic_t stopping = 0;
void stop_signal(int) { stopping = 1; }
std::string random_token() {
  std::array<unsigned char, 16> bytes{};
#ifdef __linux__
  const auto size = ::getrandom(bytes.data(), bytes.size(), GRND_NONBLOCK);
  if (size != static_cast<ssize_t>(bytes.size())) throw std::runtime_error("resource_limit");
#else
  if (::getentropy(bytes.data(), bytes.size()) != 0) throw std::runtime_error("resource_limit");
#endif
  std::string result; result.reserve(32);
  constexpr char alphabet[] = "0123456789abcdef";
  for (const auto byte : bytes) { result += alphabet[byte >> 4]; result += alphabet[byte & 15]; }
  return result;
}
bool nonblocking(int descriptor) {
  const int flags = ::fcntl(descriptor, F_GETFL);
  return flags >= 0 && ::fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0;
}
}
int main(int argc, char **) {
  if (argc != 1 || !nonblocking(STDIN_FILENO) || !nonblocking(STDOUT_FILENO)) return 2;
  std::signal(SIGPIPE, SIG_IGN); std::signal(SIGTERM, stop_signal); std::signal(SIGINT, stop_signal);
  using namespace wotex::ble;
  try {
    NativeHost host(random_token); Lines lines; bool input = true, failed = false;
    auto stop_by = Clock::time_point::max();
    const auto stop = [&] {
      if (stop_by == Clock::time_point::max()) stop_by = Clock::now() + std::chrono::milliseconds(500);
      input = false; host.stop();
    };
    while (Clock::now() < stop_by) {
      try {
        if (stopping) stop();
        host.flush(STDOUT_FILENO);
        if (host.finished() && !host.output_frames()) return failed ? 1 : host.status();
        std::vector<pollfd> descriptors{{STDIN_FILENO, static_cast<short>(input ? POLLIN : 0), 0},
          {STDOUT_FILENO, static_cast<short>(host.output_frames() ? POLLOUT : 0), 0}};
        host.poll(descriptors, 5);
        stop_by = std::min(stop_by, host.close_deadline());
        if (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) { failed = true; stop(); }
        if (input && descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
          std::array<char, 8192> bytes{};
          for (unsigned attempt = 0; attempt < 8; ++attempt) {
            const auto count = ::read(STDIN_FILENO, bytes.data(), bytes.size());
            if (count < 0) {
              if (errno == EAGAIN || errno == EWOULDBLOCK) break;
              if (errno == EINTR) continue;
              failed = true; stop(); break;
            }
            if (!count) { lines.eof(); stop(); break; }
            lines.feed(std::string_view(bytes.data(), static_cast<std::size_t>(count)), [&](std::string_view line) { host.receive(parse_line(line)); });
          }
        }
      } catch (...) { failed = true; stop(); }
    }
    return 1;
  } catch (...) { return 1; }
}
