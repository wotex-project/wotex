#include "wotex_matter/bridge_private_file.hpp"

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <new>
#include <sys/stat.h>
#include <unistd.h>

namespace {
long remaining = -1;
void *watch = nullptr;
std::size_t watched_bytes = 0;
bool cleared = false;
void Freed(void *value) {
  if (value == watch) {
    const auto *bytes = static_cast<const unsigned char *>(value);
    cleared = true;
    for (std::size_t i = 0; i < watched_bytes; ++i) cleared = cleared && bytes[i] == 0;
    watch = nullptr;
  }
  std::free(value);
}
}
void *operator new(std::size_t size) {
  if (remaining == 0) throw std::bad_alloc();
  if (remaining > 0) --remaining;
  if (auto *memory = std::malloc(size == 0 ? 1 : size)) return memory;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *value) noexcept { Freed(value); }
void operator delete[](void *value) noexcept { Freed(value); }
void operator delete(void *value, std::size_t) noexcept { Freed(value); }
void operator delete[](void *value, std::size_t) noexcept { Freed(value); }

int main() {
  using File = wotex::matter::BridgePrivateFile;
  using R = File::Result;
  char temporary[] = "/private/tmp/wotex-matter-private-config-XXXXXX";
#if !defined(__APPLE__)
  std::strcpy(temporary, "/tmp/wotex-matter-private-config-XXXXXX");
#endif
  const char *created = mkdtemp(temporary);
  assert(created);
  const auto directory = std::filesystem::canonical(created).string();
  const auto path = directory + "/private.bin";
  const unsigned char contents[] = {0, 1, 2, 3, 255, 0, 128, 65};
  const int descriptor = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  assert(descriptor >= 0);
  assert(write(descriptor, contents, sizeof(contents)) == sizeof(contents));
  assert(close(descriptor) == 0);
  std::unique_ptr<File> owner;
  assert(File::Load(path, sizeof(contents), owner) == R::Loaded);
  assert(owner && owner->size() == sizeof(contents));
  assert(std::memcmp(owner->data(), contents, sizeof(contents)) == 0);
  const auto *initial = owner.get();
  if (geteuid() == 0) {
    assert(chown(path.c_str(), 1, 0) == 0);
    assert(File::Load(path, 8, owner) == R::File && owner.get() == initial);
    assert(chown(path.c_str(), 0, 0) == 0);
  }
  for (const auto &invalid :
       {std::string(""), std::string("relative"), path + "/", directory + "//private.bin",
        directory + "/./private.bin", directory + "/../private.bin", path + '\0', path + '\n',
        path + '\r', "/" + std::string(4096, 'x')}) {
    assert(File::Load(invalid, 8, owner) == R::InvalidPath);
    assert(owner.get() == initial);
  }
  assert(File::Load(path, 0, owner) == R::InvalidPath);
  assert(File::Load(path, File::kMaximumBytes + 1, owner) == R::InvalidPath);
  assert(File::Load(path, 7, owner) == R::Size);
  for (const mode_t mode : {0644, 0640, 0660, 0700, 04600}) {
    assert(chmod(path.c_str(), mode) == 0);
    assert(File::Load(path, 8, owner) == R::File);
    assert(owner.get() == initial);
  }
  assert(chmod(path.c_str(), 0400) == 0);
  std::unique_ptr<File> read_only;
  assert(File::Load(path, 8, read_only) == R::Loaded);
  assert(std::memcmp(read_only->data(), contents, 8) == 0);
  assert(chmod(path.c_str(), 0600) == 0);
  const auto leaf_link = directory + "/linked.bin";
  assert(symlink(path.c_str(), leaf_link.c_str()) == 0);
  assert(File::Load(leaf_link, 8, owner) == R::File);
  const auto parent_link = directory + "/linked-parent";
  assert(symlink(directory.c_str(), parent_link.c_str()) == 0);
  assert(File::Load(parent_link + "/private.bin", 8, owner) == R::File);
  const auto alias = directory + "/hard-link";
  assert(link(path.c_str(), alias.c_str()) == 0);
  assert(File::Load(path, 8, owner) == R::File);
  assert(unlink(alias.c_str()) == 0);
  const auto fifo = directory + "/fifo";
  assert(mkfifo(fifo.c_str(), 0600) == 0);
  assert(File::Load(fifo, 8, owner) == R::File);
  assert(File::Load(directory, 8, owner) == R::File);
  const auto empty_path = directory + "/empty";
  const int empty = open(empty_path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
  assert(empty >= 0 && close(empty) == 0);
  assert(File::Load(empty_path, 8, owner) == R::Size);
  assert(owner.get() == initial);
  const auto large_path = directory + "/large";
  const int large = open(large_path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
  assert(large >= 0 && ftruncate(large, File::kMaximumBytes + 1) == 0);
  assert(File::Load(large_path, File::kMaximumBytes, owner) == R::Size);
  assert(owner.get() == initial);
  assert(ftruncate(large, File::kMaximumBytes) == 0 && close(large) == 0);
  std::unique_ptr<File> maximum;
  assert(File::Load(large_path, File::kMaximumBytes, maximum) == R::Loaded);
  assert(maximum->size() == File::kMaximumBytes);
  std::size_t refused = 0;
  bool reached = false;
  for (long point = 0; point < 16; ++point) {
    remaining = point;
    const auto result = File::Load(path, 8, owner);
    remaining = -1;
    if (result == R::Loaded) {
      reached = true;
      break;
    }
    assert(result == R::NoMemory && owner.get() == initial);
    ++refused;
  }
  assert(reached && refused > 0);
  watch = const_cast<std::uint8_t *>(owner->data());
  watched_bytes = owner->size();
  owner->Clear();
  assert(cleared && owner->size() == 0 && owner->data() == nullptr);
  owner->Clear();
  std::filesystem::remove_all(directory);
  std::cout << "private bootstrap file boundary passed\n";
}
