#ifndef WOTEX_MATTER_BRIDGE_COMMISSIONING_INPUT_HPP
#define WOTEX_MATTER_BRIDGE_COMMISSIONING_INPUT_HPP

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string_view>

namespace wotex::matter {
// Explicit binary commissioning layout: WMCSET1 followed by NUL, big-endian
// PIN(u32), discriminator(u16), iterations(u32), salt length(u8), salt(16..32).
// SDK PIN validity and PASE derivation remain credential-owner obligations.
class BridgeCommissioningInput final {
 public:
  ~BridgeCommissioningInput() { Clear(); }
  BridgeCommissioningInput() = default;
  BridgeCommissioningInput(const BridgeCommissioningInput &) = delete;
  BridgeCommissioningInput &operator=(const BridgeCommissioningInput &) = delete;
  enum class Result { Decoded, Malformed };
  Result Decode(std::string_view bytes) noexcept {
    constexpr char magic[] = "WMCSET1";
    if (bytes.size() < 35 || bytes.size() > 51 || std::memcmp(bytes.data(), magic, 8) != 0)
      return Result::Malformed;
    const auto number = [&](std::size_t offset, std::size_t length) {
      std::uint32_t result = 0;
      for (std::size_t i = offset; i < offset + length; ++i)
        result = (result << 8) | static_cast<unsigned char>(bytes[i]);
      return result;
    };
    const auto count = number(18, 1);
    const auto iterations = number(14, 4), discriminator = number(12, 2);
    if (count < 16 || count > 32 || bytes.size() != 19 + count || discriminator > 4095 ||
        iterations < 1000 || iterations > 100000)
      return Result::Malformed;
    // All validation precedes replacement of the current owned scalar/salt.
    Clear();
    passcode_ = number(8, 4);
    discriminator_ = static_cast<std::uint16_t>(discriminator);
    iterations_ = iterations;
    salt_size_ = count;
    std::memcpy(salt_.data(), bytes.data() + 19, count);
    return Result::Decoded;
  }
  std::uint32_t passcode() const noexcept { return passcode_; }
  std::uint16_t discriminator() const noexcept { return discriminator_; }
  std::uint32_t iterations() const noexcept { return iterations_; }
  const std::uint8_t *salt() const noexcept { return salt_.data(); }
  std::size_t salt_size() const noexcept { return salt_size_; }
  void Clear() noexcept {
    // Volatile stores clear this owner's complete scalar/salt allocation.
    Wipe(reinterpret_cast<std::uint8_t *>(&passcode_), sizeof(passcode_));
    Wipe(salt_.data(), salt_.size());
    discriminator_ = 0;
    iterations_ = 0;
    salt_size_ = 0;
  }
 private:
  static void Wipe(std::uint8_t *value, std::size_t size) noexcept {
    volatile std::uint8_t *output = value;
    while (size != 0) {
      *output++ = 0;
      --size;
    }
  }
  std::uint32_t passcode_{0};
  std::uint16_t discriminator_{0};
  std::uint32_t iterations_{0};
  std::array<std::uint8_t, 32> salt_{};
  std::size_t salt_size_{0};
};
} // namespace wotex::matter
#endif
