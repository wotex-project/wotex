#ifndef WOTEX_MATTER_BRIDGE_PRIVATE_FILE_HPP
#define WOTEX_MATTER_BRIDGE_PRIVATE_FILE_HPP

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>

namespace wotex::matter {

// Native bootstrap snapshot only. Caller owns source-file custody and any
// later copies. No lookup, example material or reread occurs after loading.
class BridgePrivateFile final {
 public:
  static constexpr std::size_t kMaximumBytes = 65'536;
  enum class Result { Loaded, InvalidPath, File, Size, Changed, NoMemory };
  static Result Load(std::string_view path, std::size_t maximum,
                     std::unique_ptr<BridgePrivateFile> &result) noexcept;
  ~BridgePrivateFile();
  BridgePrivateFile(const BridgePrivateFile &) = delete;
  BridgePrivateFile &operator=(const BridgePrivateFile &) = delete;
  const std::uint8_t *data() const noexcept { return bytes_.get(); }
  std::size_t size() const noexcept { return size_; }
  void Clear() noexcept;

 private:
  BridgePrivateFile() = default;
  std::unique_ptr<std::uint8_t[]> bytes_;
  std::size_t size_{0};
};

} // namespace wotex::matter
#endif
