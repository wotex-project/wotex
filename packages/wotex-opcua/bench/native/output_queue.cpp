// SPDX-License-Identifier: Apache-2.0
// The bounded output queue of the OPC UA host (priv/native/output.c): admission
// of normal envelopes into the queue, and admission followed by a credited
// flush through write(2) to /dev/null. Each operation is one envelope.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <fcntl.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" {
#include "output.h"
}

namespace {

// One LF-terminated normal envelope of `size` bytes.
std::string envelope(std::size_t size) {
  std::string frame = R"({"type":"value","data":")";
  frame.append(size - frame.size() - 3, 'a');
  frame.append("\"}\n");
  return frame;
}

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "output_queue: " << what << " failed\n";
  std::exit(1);
}

// Admits `count` envelopes into an empty queue, then frees them unwritten.
void admit(WopOutput *output, const std::string &frame, std::size_t count) {
  wop_output_init(output);
  for (std::size_t i = 0; i < count; ++i)
    check(wop_output_normal(output, frame.data(), frame.size()) == WOP_OUTPUT_OK, "admission");
  wop_output_clear(output);
}

// Grants credit for `count` envelopes, admits them and flushes the queue.
void admit_and_flush(WopOutput *output, const std::string &frame, std::size_t count, int sink) {
  const WopIpcCredit credit = {1, 1, count, WOP_CREDIT_BYTES};
  wop_output_init(output);
  check(wop_output_credit(output, &credit) == WOP_OUTPUT_OK, "credit");
  for (std::size_t i = 0; i < count; ++i)
    check(wop_output_normal(output, frame.data(), frame.size()) == WOP_OUTPUT_OK, "admission");
  check(wop_output_flush(output, sink) == WOP_OUTPUT_OK, "flush");
  check(wop_output_drained(output), "drain");
  wop_output_clear(output);
}

} // namespace

int main() {
  const int sink = open("/dev/null", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
  check(sink >= 0, "open /dev/null");
  auto output = std::make_unique<WopOutput>();

  ankerl::nanobench::Bench bench;
  bench.title("output queue")
      .unit("envelope")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  for (const std::size_t size : {256U, 4096U}) {
    const std::string frame = envelope(size);
    const std::string bytes = std::to_string(size) + " B";

    bench.batch(WOP_OUTPUT_FRAMES).run("admit 64 x " + bytes, [&] {
      admit(output.get(), frame, WOP_OUTPUT_FRAMES);
    });
    bench.batch(WOP_CREDIT_MESSAGES).run("admit and flush 16 x " + bytes, [&] {
      admit_and_flush(output.get(), frame, WOP_CREDIT_MESSAGES, sink);
    });
  }

  close(sink);
  return 0;
}
