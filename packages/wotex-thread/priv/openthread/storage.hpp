#ifndef WOTEX_THREAD_STORAGE_HPP
#define WOTEX_THREAD_STORAGE_HPP

#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdexcept>
#include <string>
#include <utility>

namespace wotex::thread {
class StorageError final : public std::runtime_error {
 public:
  StorageError() : std::runtime_error("storage_unavailable") {}
};

class FileDescriptor final {
 public:
  explicit FileDescriptor(int value = -1) : value_(value) {}
  ~FileDescriptor() { if (value_ >= 0) (void)::close(value_); }
  FileDescriptor(const FileDescriptor &) = delete;
  FileDescriptor &operator=(const FileDescriptor &) = delete;
  FileDescriptor(FileDescriptor &&other) noexcept : value_(std::exchange(other.value_, -1)) {}
  FileDescriptor &operator=(FileDescriptor &&other) noexcept {
    if (this != &other) {
      if (value_ >= 0) (void)::close(value_);
      value_ = std::exchange(other.value_, -1);
    }
    return *this;
  }
  int get() const { return value_; }
 private:
  int value_;
};

class Storage final {
 public:
  Storage(const std::string &path, bool create_new) {
    if (path.size() < 2 || path.size() > 4096 || path.front() != '/' ||
        path.find('\0') != std::string::npos) throw StorageError();
    if (create_new && ::mkdir(path.c_str(), 0700) != 0) throw StorageError();
    FileDescriptor directory(::open(path.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat info {};
    if (directory.get() < 0 || ::fstat(directory.get(), &info) != 0 ||
        !S_ISDIR(info.st_mode) || (info.st_mode & 0777) != 0700 || info.st_uid != ::geteuid()) {
      throw StorageError();
    }
    FileDescriptor lock(::openat(directory.get(), ".wotex-lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600));
    if (lock.get() < 0 || ::fstat(lock.get(), &info) != 0 || !S_ISREG(info.st_mode) ||
        (info.st_mode & 0777) != 0600 || info.st_uid != ::geteuid() || info.st_nlink != 1 ||
        ::flock(lock.get(), LOCK_EX | LOCK_NB) != 0) throw StorageError();
    directory_ = std::move(directory);
    lock_ = std::move(lock);
  }
  Storage(const Storage &) = delete;
  Storage &operator=(const Storage &) = delete;
  Storage(Storage &&) noexcept = default;
  Storage &operator=(Storage &&) noexcept = default;
  int directory() const { return directory_.get(); }
 private:
  FileDescriptor directory_;
  FileDescriptor lock_;
};
}  // namespace wotex::thread
#endif
