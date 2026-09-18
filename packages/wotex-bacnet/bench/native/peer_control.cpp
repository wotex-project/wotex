// SPDX-License-Identifier: Apache-2.0
// The control-command parser of the BACnet C-stack software peer
// (test/interop/cstack/control.c), the only part of the peer that compiles
// without the pinned BACnet stack: peer_parse on the datagrams the software
// runner sends to the peer's control port (`stats`, `fault` and `quit` with a
// nonce), accepted and rejected. The unit is one command.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <nanobench.h>

extern "C" {
#include "peer.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "peer_control: " << what << " failed\n";
  std::exit(1);
}

// Parses one control datagram and checks the outcome.
peer_command parse(const char *datagram, bool accepted) {
  peer_command command = {};
  check(peer_parse(datagram, std::strlen(datagram), &command) == accepted, datagram);
  return command;
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.title("control commands")
      .unit("command")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));
  bench.run("peer_parse, stats with the largest nonce", [&] {
    const peer_command command = parse("stats 4294967295\n", true);
    check(command.kind == PEER_STATS && command.nonce == UINT32_MAX, "stats command");
  });
  bench.run("peer_parse, fault cancel_request 255", [&] {
    const peer_command command = parse("fault cancel_request 255 4294967295\n", true);
    check(command.kind == PEER_FAULT && command.fault == PEER_FAULT_CANCEL_REQUEST &&
              command.count == 255,
          "fault command");
  });
  bench.run("peer_parse, fault count out of range",
            [&] { parse("fault register_ack 256 4294967295\n", false); });
  bench.run("peer_parse, quit",
            [&] { check(parse("quit 7\n", true).kind == PEER_QUIT, "quit command"); });
  return 0;
}
