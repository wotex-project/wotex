// SPDX-License-Identifier: Apache-2.0
// Request round trips through a complete session of the Matter controller host
// (native/src/protocol.cpp and include/wotex_matter/input.hpp). RunHost reads
// LF-terminated frames from its input pipe through BoundedInput, dispatches
// each through HostProtocol and hands every reply to the bounded output writer
// thread, which writes it to the output pipe. A second thread plays the BEAM
// Port as Wotex.Matter.Native.Connection drives it: it reads the ready frame,
// sends flow_open and open, then sends one request at a time and reads its
// reply before the next, and finally closes. The scripted backend
// (scripted_backend.hpp) answers the interactions. Each operation is one
// request round trip; the session set-up (two pipes, two threads, ready, open
// and close) is amortised over the session's requests.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <streambuf>
#include <string>
#include <thread>

#include <csignal>
#include <unistd.h>

#include <nanobench.h>

#include "scripted_backend.hpp"
#include "wotex_matter/protocol.hpp"

namespace {

using namespace wotex::matter;
using namespace wotex::matter::bench;

constexpr std::size_t kRequests = 256;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "host_session: " << what << " failed\n";
  std::exit(1);
}

bool write_all(int descriptor, const std::string &bytes) {
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const ssize_t written = write(descriptor, bytes.data() + offset, bytes.size() - offset);
    if (written <= 0) return false;
    offset += static_cast<std::size_t>(written);
  }
  return true;
}

// The host's stdout: each flushed frame is written to the output pipe.
class PipeSink final : public std::streambuf {
 public:
  explicit PipeSink(int descriptor) : descriptor_(descriptor) {}

 protected:
  int_type overflow(int_type byte) override {
    if (traits_type::eq_int_type(byte, traits_type::eof())) return traits_type::not_eof(byte);
    pending_.push_back(traits_type::to_char_type(byte));
    return byte;
  }

  std::streamsize xsputn(const char *bytes, std::streamsize count) override {
    pending_.append(bytes, static_cast<std::size_t>(count));
    return count;
  }

  int sync() override {
    const bool written = write_all(descriptor_, pending_);
    pending_.clear();
    return written ? 0 : -1;
  }

 private:
  int descriptor_;
  std::string pending_;
};

// Reads LF-terminated frames from the host's output pipe.
class FrameReader {
 public:
  explicit FrameReader(int descriptor) : descriptor_(descriptor) {}

  bool next(std::string &frame) {
    for (;;) {
      const std::size_t end = buffer_.find('\n', offset_);
      if (end != std::string::npos) {
        frame.assign(buffer_, offset_, end - offset_);
        offset_ = end + 1;
        return true;
      }
      buffer_.erase(0, offset_);
      offset_ = 0;
      char chunk[4096];
      const ssize_t count = read(descriptor_, chunk, sizeof chunk);
      if (count <= 0) return false;
      buffer_.append(chunk, static_cast<std::size_t>(count));
    }
  }

 private:
  int descriptor_;
  std::string buffer_;
  std::size_t offset_{0};
};

bool ok(const std::string &frame) { return frame.find(R"("ok":true)") != std::string::npos; }

// The Port side of one session; returns the number of successful replies.
std::size_t drive(int input, int output, const RequestLine &request, std::size_t count) {
  FrameReader reader(output);
  std::string frame;
  std::size_t answered = 0;
  if (!reader.next(frame) || frame.find(R"("event":"ready")") == std::string::npos) return 0;
  if (!write_all(input, flow_open_line() + "\n" + open_line() + "\n") || !reader.next(frame) ||
      !ok(frame))
    return 0;
  for (std::size_t index = 0; index < count; ++index) {
    if (!write_all(input, request.with_id(index + 2) + "\n") || !reader.next(frame))
      return answered;
    if (ok(frame)) ++answered;
  }
  const std::string close_frame =
      R"({"version":1,"id":"close","operation":"close","parameters":{},"timeout_ms":30000})"
      "\n";
  if (write_all(input, close_frame) && reader.next(frame) && ok(frame)) ++answered;
  return answered;
}

// Runs one session of `count` requests and checks that every request and the
// close were answered successfully and `interactions` reached the backend.
void run_session(const RequestLine &request, std::size_t count, std::size_t interactions) {
  int input[2];
  int output[2];
  check(pipe(input) == 0 && pipe(output) == 0, "pipe");
  std::size_t answered = 0;
  std::thread port([&] {
    answered = drive(input[1], output[0], request, count);
    close(input[1]);
  });

  ScriptedBackend backend;
  PipeSink sink(output[1]);
  std::ostream stdout_stream(&sink);
  std::istringstream unused;
  const int status = RunHost(backend, unused, stdout_stream, {}, input[0]);
  close(output[1]);
  port.join();
  close(input[0]);
  close(output[0]);
  check(status == 0, "session status");
  check(answered == count + 1, "replies");
  check(backend.interactions == interactions, "interactions");
}

} // namespace

int main() {
  // A host that stops reading early must fail its check, not end the process.
  check(std::signal(SIGPIPE, SIG_IGN) != SIG_ERR, "SIGPIPE");

  const RequestLine health = request_line("health", "");
  const RequestLine on_off = request_line("read", path_members(1, 0x0006, 0x0000));
  const RequestLine setpoint = request_line(
      "write",
      path_members(1, 0x0201, 0x0012) +
          R"(,"value":{"tag":"anonymous","type":"i16","value":2150})");

  ankerl::nanobench::Bench bench;
  bench.title("host session")
      .unit("request")
      .batch(kRequests)
      .warmup(3)
      .minEpochTime(std::chrono::milliseconds(50));

  bench.run("256 health round trips", [&] { run_session(health, kRequests, 0); });
  bench.run("256 OnOff read round trips", [&] { run_session(on_off, kRequests, kRequests); });
  bench.run("256 setpoint write round trips", [&] { run_session(setpoint, kRequests, kRequests); });
  return 0;
}
