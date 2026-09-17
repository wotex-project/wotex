#include "output.hpp"
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <cstdlib>
#include <string>

using namespace wotex::thread;

namespace {
void check(bool value) {
  if (!value) std::abort();
}

std::string drain(int descriptor) {
  std::string bytes;
  char buffer[65536];
  ssize_t count = 0;
  while ((count = ::read(descriptor, buffer, sizeof buffer)) > 0) bytes.append(buffer, static_cast<std::size_t>(count));
  return bytes;
}
}  // namespace

int main() {
  (void)::signal(SIGPIPE, SIG_IGN);
  {
    // WTH-B02: each lane has its own frame count, frame size and aggregate budget.
    Output output;
    check(!output.push(Lane::reply, "") && !output.push(Lane::control, "two\nlines"));
    check(output.push(Lane::control, std::string(4095, 'c')) && !output.push(Lane::control, std::string(4096, 'c')));
    for (int index = 1; index < 256; ++index) check(output.push(Lane::control, "c"));
    check(!output.push(Lane::control, "c") && output.usage(Lane::control).frames == 256);
    check(output.usage(Lane::control).bytes == 4096 + 255 * 2);
    // Exhausted control capacity cannot consume or be consumed by replies or reports.
    for (int index = 0; index < 64; ++index) check(output.push(Lane::reply, std::string(131071, 'r')));
    check(!output.push(Lane::reply, "r") && output.usage(Lane::reply).bytes == 8388608);
    for (int index = 0; index < 8; ++index) check(output.push(Lane::report, std::string(131071, 'p')));
    check(!output.push(Lane::report, "p") && output.usage(Lane::report).bytes == 1048576);
    check(!output.push(Lane::reply, std::string(131072, 'r')));
  }
  {
    Output output;
    for (int index = 0; index < 64; ++index) check(output.push(Lane::report, "p"));
    check(!output.push(Lane::report, "p") && output.maximum(Lane::report).frames == 64);
  }
  {
    // WTH-B02: partial writes keep order and reservations until each final byte is written.
    int pipe_descriptors[2];
    check(::pipe(pipe_descriptors) == 0);
    check(::fcntl(pipe_descriptors[1], F_SETFL, O_NONBLOCK) == 0 && ::fcntl(pipe_descriptors[0], F_SETFL, O_NONBLOCK) == 0);
    Output output;
    std::string expected;
    for (int index = 0; index < 64; ++index) {
      const std::string reply(131071, static_cast<char>('a' + index % 26));
      check(output.push(Lane::reply, reply));
      expected += reply + "\n";
      check(output.push(Lane::control, "control-" + std::to_string(index)));
      expected += "control-" + std::to_string(index) + "\n";
    }
    std::string observed;
    Output::Flush result = Output::Flush::pending;
    bool saw_pending = false;
    while ((result = output.flush(pipe_descriptors[1])) == Output::Flush::pending) {
      saw_pending = true;
      check(output.usage(Lane::reply).frames > 0 || output.usage(Lane::control).frames > 0);
      observed += drain(pipe_descriptors[0]);
    }
    observed += drain(pipe_descriptors[0]);
    check(result == Output::Flush::idle && saw_pending && output.empty() && observed == expected);
    check(output.usage(Lane::reply).frames == 0 && output.usage(Lane::control).bytes == 0);
    check(output.maximum(Lane::reply).frames == 64);
    check(output.push(Lane::reply, "after") && ::close(pipe_descriptors[0]) == 0);
    // A closed reader is a channel failure, not a pending write.
    check(output.flush(pipe_descriptors[1]) == Output::Flush::failed);
    check(::close(pipe_descriptors[1]) == 0);
  }
  return 0;
}
