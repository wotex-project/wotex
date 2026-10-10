#include "wotex_matter/bridge_private_file.hpp"

#include <array>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <new>
#include <sys/stat.h>
#include <unistd.h>

namespace wotex::matter {
namespace {
class Descriptor final {
 public:
  explicit Descriptor(int value) : value_(value) {}
  ~Descriptor() {
    if (value_ >= 0) close(value_);
  }
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  int get() const { return value_; }
  void Reset(int value) {
    if (value_ >= 0) close(value_);
    value_ = value;
  }
 private:
  int value_;
};

void Wipe(std::uint8_t *bytes, std::size_t size) noexcept {
  volatile std::uint8_t *owned = bytes;
  while (size != 0) {
    *owned++ = 0;
    --size;
  }
}

bool Same(const struct stat &left, const struct stat &right) {
#if defined(__APPLE__)
  const bool times = left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec &&
      left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec &&
      left.st_ctimespec.tv_sec == right.st_ctimespec.tv_sec &&
      left.st_ctimespec.tv_nsec == right.st_ctimespec.tv_nsec;
#else
  const bool times = left.st_mtim.tv_sec == right.st_mtim.tv_sec &&
      left.st_mtim.tv_nsec == right.st_mtim.tv_nsec &&
      left.st_ctim.tv_sec == right.st_ctim.tv_sec && left.st_ctim.tv_nsec == right.st_ctim.tv_nsec;
#endif
  return times && left.st_dev == right.st_dev && left.st_ino == right.st_ino &&
      left.st_size == right.st_size && left.st_uid == right.st_uid &&
      left.st_mode == right.st_mode && left.st_nlink == right.st_nlink;
}
} // namespace

BridgePrivateFile::Result BridgePrivateFile::Load(
    std::string_view path, std::size_t maximum,
    std::unique_ptr<BridgePrivateFile> &result) noexcept {
  using R = Result;
  if (maximum == 0 || maximum > kMaximumBytes || path.empty() || path.size() > 4096 ||
      path.front() != '/' || path.back() == '/' ||
      path.find_first_of(std::string_view("\0\n\r", 3)) != std::string_view::npos)
    return R::InvalidPath;
  try {
    // Walk each component through directory descriptors; no parent or leaf
    // symlink can redirect this load. Directory writability is not immutability.
    Descriptor directory(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    if (directory.get() < 0) return R::File;
    std::size_t begin = 1;
    Descriptor file(-1);
    std::array<char, 4097> component;
    while (begin < path.size()) {
      const auto end = path.find('/', begin);
      const std::string_view segment(path.data() + begin,
                                     end == path.npos ? path.size() - begin : end - begin);
      if (segment.empty() || segment == "." || segment == "..") return R::InvalidPath;
      // The whole path is bounded above. Use fixed scratch storage rather than
      // a string allocation with a separate length-exception boundary.
      std::memcpy(component.data(), segment.data(), segment.size());
      component[segment.size()] = '\0';
      if (end == path.npos) {
        // NONBLOCK prevents an untrusted FIFO/device open from waiting before
        // fstat can refuse its type. Regular-file reads remain ordinary reads.
        file.Reset(openat(directory.get(), component.data(),
                          O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
        break;
      }
      directory.Reset(openat(directory.get(), component.data(),
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
      if (directory.get() < 0) return R::File;
      begin = end + 1;
    }
    struct stat before{};
    if (file.get() < 0 || fstat(file.get(), &before) != 0 || !S_ISREG(before.st_mode) ||
        before.st_uid != geteuid() || before.st_nlink != 1 ||
        ((before.st_mode & 07777) != 0600 && (before.st_mode & 07777) != 0400))
      return R::File;
    if (before.st_size <= 0 || static_cast<std::uint64_t>(before.st_size) > maximum) return R::Size;
    std::unique_ptr<BridgePrivateFile> owned(new BridgePrivateFile);
    owned->size_ = static_cast<std::size_t>(before.st_size);
    owned->bytes_.reset(new std::uint8_t[owned->size_]{});
    std::size_t offset = 0;
    while (offset < owned->size_) {
      const auto count = read(file.get(), owned->bytes_.get() + offset, owned->size_ - offset);
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) return R::Changed;
      offset += static_cast<std::size_t>(count);
    }
    std::uint8_t extra = 0;
    ssize_t count;
    do {
      count = read(file.get(), &extra, 1);
    } while (count < 0 && errno == EINTR);
    Wipe(&extra, sizeof(extra));
    struct stat after{};
    if (count != 0 || fstat(file.get(), &after) != 0 || !Same(before, after)) return R::Changed;
    result = std::move(owned);
    return R::Loaded;
  } catch (const std::bad_alloc &) {
    return R::NoMemory;
  }
}

BridgePrivateFile::~BridgePrivateFile() { Clear(); }
void BridgePrivateFile::Clear() noexcept {
  if (bytes_) Wipe(bytes_.get(), size_);
  bytes_.reset();
  size_ = 0;
}
} // namespace wotex::matter
