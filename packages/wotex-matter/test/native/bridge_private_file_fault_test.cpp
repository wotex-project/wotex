#include "wotex_matter/bridge_private_file.hpp"
#include <cassert>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <new>
#include <sys/stat.h>
#include <unistd.h>

extern "C" ssize_t __real_read(int, void *, std::size_t);
extern "C" int __real_fstat(int, struct stat *);
namespace {
enum class Fault {
  None,
  Short,
  Interrupted,
  ReadError,
  EarlyEof,
  Extend,
  Truncate,
  Rewrite,
  Mode,
  StatError
};
Fault fault = Fault::None;
bool armed = false;
unsigned reads = 0, stats = 0;
int writer = -1;
void *watched = nullptr;
std::size_t watched_size = 0;
bool wiped = false;
void Free(void *value) {
  if (value && value == watched) {
    wiped = true;
    for (std::size_t i = 0; i < watched_size; ++i)
      wiped = wiped && static_cast<const unsigned char *>(value)[i] == 0;
    watched = nullptr;
  }
  std::free(value);
}
}
void *operator new(std::size_t size) {
  if (auto *value = std::malloc(size ? size : 1)) return value;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *value) noexcept { Free(value); }
void operator delete[](void *value) noexcept { Free(value); }
void operator delete(void *value, std::size_t) noexcept { Free(value); }
void operator delete[](void *value, std::size_t) noexcept { Free(value); }

extern "C" int __wrap_fstat(int descriptor, struct stat *result) {
  if (armed && ++stats == 2 && fault == Fault::StatError) {
    errno = EIO;
    return -1;
  }
  return __real_fstat(descriptor, result);
}
extern "C" ssize_t __wrap_read(int descriptor, void *bytes, std::size_t size) {
  if (!armed) return __real_read(descriptor, bytes, size);
  ++reads;
  if (reads == 1) {
    watched = bytes;
    watched_size = 8;
    wiped = false;
  }
  if (fault == Fault::Interrupted && reads == 1) {
    errno = EINTR;
    return -1;
  }
  if (fault == Fault::ReadError && reads == 2) {
    errno = EIO;
    return -1;
  }
  if (fault == Fault::EarlyEof && reads == 2) return 0;
  const auto count = __real_read(descriptor, bytes, size > 4 ? 4 : size);
  if (reads == 1 && count > 0) {
    if (fault == Fault::Extend) {
      constexpr unsigned char extra = 0xA5;
      assert(pwrite(writer, &extra, 1, 8) == 1);
    } else if (fault == Fault::Truncate) {
      assert(ftruncate(writer, 4) == 0);
    } else if (fault == Fault::Rewrite) {
      constexpr unsigned char changed[] = {9, 9, 9, 9};
      assert(pwrite(writer, changed, sizeof(changed), 4) == sizeof(changed));
      struct stat state{};
      assert(__real_fstat(writer, &state) == 0);
      const struct timespec times[] = {state.st_atim,
                                       {state.st_mtim.tv_sec + 1, state.st_mtim.tv_nsec}};
      assert(futimens(writer, times) == 0);
    } else if (fault == Fault::Mode) {
      assert(fchmod(writer, 0644) == 0);
    }
  }
  return count;
}
int main() {
  using File = wotex::matter::BridgePrivateFile;
  using R = File::Result;
  char temporary[] = "/tmp/wotex-matter-private-mutation-XXXXXX";
  assert(mkdtemp(temporary));
  const auto root = std::filesystem::canonical(temporary).string();
  const auto path = root + "/input";
  writer = open(path.c_str(), O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  assert(writer >= 0);
  constexpr unsigned char input[] = {1, 2, 3, 4, 5, 6, 7, 8};
  const auto restore = [&] {
    assert(ftruncate(writer, 8) == 0 && fchmod(writer, 0600) == 0);
    assert(pwrite(writer, input, sizeof(input), 0) == sizeof(input));
  };
  restore();
  std::unique_ptr<File> owner;
  assert(File::Load(path, 8, owner) == R::Loaded);
  for (auto selected : {Fault::ReadError, Fault::EarlyEof, Fault::Extend, Fault::Truncate,
                        Fault::Rewrite, Fault::Mode, Fault::StatError}) {
    restore();
    const auto *previous = owner.get();
    reads = stats = 0;
    fault = selected;
    armed = true;
    const auto result = File::Load(path, 8, owner);
    armed = false;
    assert(result == R::Changed && owner.get() == previous && wiped && watched == nullptr);
    assert(std::memcmp(owner->data(), input, sizeof(input)) == 0);
  }
  for (auto selected : {Fault::Short, Fault::Interrupted}) {
    restore();
    reads = stats = 0;
    fault = selected;
    armed = true;
    const auto result = File::Load(path, 8, owner);
    armed = false;
    assert(result == R::Loaded && std::memcmp(owner->data(), input, sizeof(input)) == 0);
    owner->Clear();
    assert(wiped && watched == nullptr);
  }
  assert(close(writer) == 0);
  std::filesystem::remove_all(root);
  std::cout << "private file mutation, read fault and retirement passed\n";
}
