#include "wotex_matter/controller.hpp"
#include "wotex_matter/protocol.hpp"

#include <csignal>
#include <iostream>

int main() {
  std::signal(SIGPIPE, SIG_IGN);
  wotex::matter::SdkControllerBackend controller;
  return wotex::matter::RunHost(controller, std::cin, std::cout);
}
