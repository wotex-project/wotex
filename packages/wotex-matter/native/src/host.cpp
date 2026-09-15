#include "wotex_matter/controller.hpp"
#include "wotex_matter/input_lifetime.hpp"
#include "wotex_matter/protocol.hpp"

#include <csignal>
#include <iostream>
#include <unistd.h>

int main() {
  std::signal(SIGPIPE, SIG_IGN);
  wotex::matter::InputLifetime lifetime(STDIN_FILENO);
  wotex::matter::SdkControllerBackend controller;
  return wotex::matter::RunHost(controller, std::cin, std::cout,
                                [&lifetime] { lifetime.Fail(); }, STDIN_FILENO);
}
