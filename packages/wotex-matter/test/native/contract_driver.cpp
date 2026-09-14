#include "wotex_matter/protocol.hpp"

#include <fstream>
#include <iostream>
#include <string>

// This fixture calls the same pure validator used by the production host.
int main(int argc, char **argv) {
  if (argc != 3 || std::string(argv[1]) != "parse_request") {
    return 2;
  }
  std::ifstream input(argv[2], std::ios::binary);
  if (!input) {
    return 2;
  }
  std::string line;
  char byte = 0;
  bool complete = false;
  while (input.get(byte)) {
    if (line.size() + 1 > wotex::matter::kMaximumFrameBytes) {
      break;
    }
    if (byte == '\n') {
      complete = input.peek() == std::char_traits<char>::eof();
      break;
    }
    line.push_back(byte);
  }
  const bool accepted = complete &&
      wotex::matter::HostProtocol::ParseRequestAccepted(line);
  std::cout << (accepted ? "{\"accepted\":true}\n" : "{\"accepted\":false}\n");
  return 0;
}
