// SPDX-License-Identifier: Apache-2.0
#include "driver.hpp"
#include <csignal>

using namespace wotex::ble::corebluetooth;
int main(int argc, char **) {
  if (argc != 1) return 64;
  std::signal(SIGPIPE, SIG_IGN);
  SteadyClock clock;
  return run_host(clock, [](SDKClock &clock, SDKSink &sink) {
    return std::make_unique<SDKDriver>(clock, sink);
  });
}
