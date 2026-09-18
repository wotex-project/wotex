// SPDX-License-Identifier: Apache-2.0
// The output lanes of the Thread host (priv/openthread/output.hpp): admission
// of frames into the reply, control and report reservations, and admission
// followed by a flush through write(2) to a non-blocking /dev/null, for
// 212-byte frames up to each lane's frame limit and 128 KiB report frames up
// to the report lane's byte budget. Each operation is one frame.
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <string>
#include <fcntl.h>
#include <unistd.h>

#include <nanobench.h>

#include "output.hpp"

namespace {

using namespace wotex::thread;

constexpr std::size_t kFrameBytes = 212;

const LaneLimit &limit(Lane lane) { return kLaneLimits[static_cast<std::size_t>(lane)]; }

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "output_lanes: " << what << " failed\n";
  std::exit(1);
}

// A frame without its newline that occupies `bytes` of a reservation.
std::string frame(std::size_t bytes) {
  std::string text = "{\"value\":\"";
  text.append(bytes - text.size() - 3, 'x');
  text.append("\"}");
  return text;
}

void admit(Output &output, Lane lane, const std::string &bytes, std::size_t count) {
  for (std::size_t index = 0; index < count; ++index) check(output.push(lane, bytes), "admission");
}

void flush(Output &output, int sink) {
  check(output.flush(sink) == Output::Flush::idle, "flush");
  check(output.empty(), "drain");
  for (const Lane lane : {Lane::reply, Lane::control, Lane::report})
    check(output.usage(lane).frames == 0 && output.usage(lane).bytes == 0, "release");
}

} // namespace

int main() {
  static_assert(kLaneLimits[0].frames == 64 && kLaneLimits[1].frames == 256 &&
                    kLaneLimits[2].frames == 64 && kLaneLimits[2].frame_bytes == 131072 &&
                    kLaneLimits[2].bytes == 1048576,
                "the native_bench description of output_lanes names these limits");
  const int sink = open("/dev/null", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
  check(sink >= 0, "open /dev/null");

  const std::string small = frame(kFrameBytes);
  const std::size_t reports = limit(Lane::report).frames;
  const std::size_t controls = limit(Lane::control).frames;
  const std::size_t replies = limit(Lane::reply).frames;
  // The report lane's byte budget in frames of the largest admitted size.
  const std::string large = frame(limit(Lane::report).frame_bytes);
  const std::size_t large_count = limit(Lane::report).bytes / limit(Lane::report).frame_bytes;

  ankerl::nanobench::Bench bench;
  bench.title("output lanes").unit("frame").warmup(100).minEpochTime(std::chrono::milliseconds(20));

  bench.batch(reports).run("admit 64 x 212 B report", [&] {
    Output output;
    admit(output, Lane::report, small, reports);
    check(output.usage(Lane::report).frames == reports, "report usage");
  });
  bench.batch(reports).run("admit and flush 64 x 212 B report", [&] {
    Output output;
    admit(output, Lane::report, small, reports);
    flush(output, sink);
  });
  bench.batch(controls).run("admit and flush 256 x 212 B control", [&] {
    Output output;
    admit(output, Lane::control, small, controls);
    flush(output, sink);
  });
  bench.batch(replies * 3)
      .run("admit and flush 192 x 212 B, reply, control and report interleaved", [&] {
    Output output;
    for (std::size_t index = 0; index < replies; ++index) {
      check(output.push(Lane::reply, small), "reply admission");
      check(output.push(Lane::control, small), "control admission");
      check(output.push(Lane::report, small), "report admission");
    }
    flush(output, sink);
  });
  bench.batch(large_count).run("admit and flush 8 x 128 KiB report", [&] {
    Output output;
    admit(output, Lane::report, large, large_count);
    check(!output.push(Lane::report, small), "report byte budget");
    flush(output, sink);
  });

  close(sink);
  return 0;
}
