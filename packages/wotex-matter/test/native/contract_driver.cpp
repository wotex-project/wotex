#include "wotex_matter/protocol.hpp"

#include <charconv>
#include <fstream>
#include <iostream>
#include <string>

// Inputs select shared production validators; expectations stay in ExUnit.
int main(int argc, char **argv) {
  if (argc != 3) {
    return 2;
  }
  const std::string operation(argv[1]);
  if (operation != "parse_request" && operation != "result_budget") {
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
  if (operation == "parse_request") {
    const bool accepted = complete &&
        wotex::matter::HostProtocol::ParseRequestAccepted(line);
    std::cout << (accepted ? "{\"accepted\":true}\n" : "{\"accepted\":false}\n");
  } else {
    std::size_t bytes = 0;
    const auto parsed = std::from_chars(line.data(), line.data() + line.size(), bytes);
    if (!complete || parsed.ec != std::errc{} || parsed.ptr != line.data() + line.size()) {
      return 2;
    }
    const bool accepted = wotex::matter::valid_encoded_result_size(bytes);
    std::cout << (accepted ? "{\"accepted\":true}\n"
                          : "{\"accepted\":false,\"code\":\"response_limit\"}\n");
  }
  return 0;
}
