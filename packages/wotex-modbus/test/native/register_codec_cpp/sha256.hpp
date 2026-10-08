// SPDX-License-Identifier: Apache-2.0
// First-party SHA-256 for configuration identity, per FIPS 180-4 (August 2015).
// https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf, sections 4-6.
#ifndef WMB_REFERENCE_SHA256_HPP
#define WMB_REFERENCE_SHA256_HPP

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace wmb_reference {
inline uint32_t rotate(uint32_t word, unsigned bits) {
  return (word >> bits) | (word << (32U - bits));
}

inline std::string sha256(const std::string &input) {
  constexpr std::array<uint32_t, 64> constants = {
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
      0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
      0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
      0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
      0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
      0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
      0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
      0xc67178f2};
  std::array<uint32_t, 8> hash = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  std::vector<uint8_t> bytes(input.begin(), input.end());
  const uint64_t bits = static_cast<uint64_t>(bytes.size()) * 8;
  bytes.push_back(0x80);
  while (bytes.size() % 64 != 56) bytes.push_back(0);
  for (int shift = 56; shift >= 0; shift -= 8) bytes.push_back(static_cast<uint8_t>(bits >> shift));
  for (size_t offset = 0; offset < bytes.size(); offset += 64) {
    std::array<uint32_t, 64> schedule{};
    for (size_t i = 0; i < 16; ++i) {
      for (size_t j = 0; j < 4; ++j) schedule[i] = (schedule[i] << 8) | bytes[offset + i * 4 + j];
    }
    for (size_t i = 16; i < 64; ++i) {
      const uint32_t x = schedule[i - 15], y = schedule[i - 2];
      const uint32_t small0 = rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3);
      const uint32_t small1 = rotate(y, 17) ^ rotate(y, 19) ^ (y >> 10);
      schedule[i] = schedule[i - 16] + small0 + schedule[i - 7] + small1;
    }
    auto work = hash;
    for (size_t i = 0; i < 64; ++i) {
      const uint32_t big1 = rotate(work[4], 6) ^ rotate(work[4], 11) ^ rotate(work[4], 25);
      const uint32_t choose = (work[4] & work[5]) ^ (~work[4] & work[6]);
      const uint32_t first = work[7] + big1 + choose + constants[i] + schedule[i];
      const uint32_t big0 = rotate(work[0], 2) ^ rotate(work[0], 13) ^ rotate(work[0], 22);
      const uint32_t majority = (work[0] & work[1]) ^ (work[0] & work[2]) ^ (work[1] & work[2]);
      work = {first + big0 + majority, work[0], work[1], work[2],
              work[3] + first,         work[4], work[5], work[6]};
    }
    for (size_t i = 0; i < hash.size(); ++i) hash[i] += work[i];
  }
  constexpr char hex[] = "0123456789abcdef";
  std::string digest;
  for (uint32_t word : hash) {
    for (int shift = 28; shift >= 0; shift -= 4) digest.push_back(hex[(word >> shift) & 15]);
  }
  return digest;
}
} // namespace wmb_reference
#endif
