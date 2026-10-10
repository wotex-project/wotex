#include "wotex_matter/bridge_commissioning_input.hpp"

#include <cassert>
#include <iostream>
#include <string>

int main() {
  using Material = wotex::matter::BridgeCommissioningInput;
  using R = Material::Result;
  std::string bytes("WMCSET1\0", 8);
  const auto append = [&](std::uint32_t value, unsigned count) {
    while (count != 0) bytes += static_cast<char>(value >> (--count * 8));
  };
  append(20202021, 4);
  append(3840, 2);
  append(1000, 4);
  append(16, 1);
  for (unsigned i = 0; i < 16; ++i) bytes += static_cast<char>(i);
  Material owner;
  assert(owner.Decode(bytes) == R::Decoded && owner.passcode() == 20202021 &&
         owner.discriminator() == 3840 && owner.iterations() == 1000 && owner.salt_size() == 16 &&
         owner.salt()[15] == 15);
  for (std::size_t count = 0; count < bytes.size(); ++count) {
    assert(owner.Decode(std::string_view(bytes).substr(0, count)) == R::Malformed);
    assert(owner.passcode() == 20202021 && owner.salt()[15] == 15);
  }
  const auto refuse = [&](const std::string &malformed) {
    assert(owner.Decode(malformed) == R::Malformed && owner.passcode() == 20202021 &&
           owner.salt_size() == 16);
  };
  refuse(bytes + '\0');
  auto changed = bytes;
  changed[0] = 'X';
  refuse(changed);
  changed = bytes;
  changed[18] = 15;
  refuse(changed);
  changed = bytes;
  changed[12] = 16;
  refuse(changed);
  changed = bytes;
  changed[14] = 0;
  changed[15] = 1;
  changed[16] = static_cast<char>(0x86);
  changed[17] = static_cast<char>(0xA1);
  refuse(changed);
  changed = bytes;
  changed[16] = 3;
  changed[17] = static_cast<char>(0xE7);
  refuse(changed);
  changed = bytes;
  changed[7] = '1';
  refuse(changed);
  changed = bytes;
  changed[18] = 33;
  changed += std::string(17, 'x');
  refuse(changed);
  changed = bytes;
  changed[18] = 32;
  changed += std::string(16, static_cast<char>(255));
  assert(owner.Decode(changed) == R::Decoded && owner.salt_size() == 32 && owner.salt()[31] == 255);
  std::fill(changed.begin(), changed.end(), '\0');
  assert(owner.passcode() == 20202021 && owner.salt()[31] == 255);
  changed = bytes;
  changed[12] = 15;
  changed[13] = static_cast<char>(255);
  changed[14] = 0;
  changed[15] = 1;
  changed[16] = static_cast<char>(0x86);
  changed[17] = static_cast<char>(0xA0);
  assert(owner.Decode(changed) == R::Decoded && owner.discriminator() == 4095 &&
         owner.iterations() == 100000);
  changed[12] = changed[13] = 0;
  // This codec validates byte layout and bounds; SDK PIN validity is a
  // separate credential-owner obligation, never inferred from decoding.
  changed[8] = changed[9] = changed[10] = changed[11] = static_cast<char>(255);
  assert(owner.Decode(changed) == R::Decoded && owner.discriminator() == 0 &&
         owner.passcode() == 0xFFFFFFFFu);
  owner.Clear();
  owner.Clear();
  assert(owner.passcode() == 0 && owner.discriminator() == 0 && owner.iterations() == 0 &&
         owner.salt_size() == 0);
  for (std::size_t i = 0; i < 32; ++i) assert(owner.salt()[i] == 0);
  std::cout << "owned commissioning binary passed\n";
}
