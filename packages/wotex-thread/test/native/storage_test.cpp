#include "storage.hpp"
#include <sys/wait.h>
#include <signal.h>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

using namespace wotex::thread;
namespace fs = std::filesystem;
static void check(bool value) { if (!value) std::abort(); }
static void rejects(const std::string &path, bool create) {
  try { Storage store(path, create); std::abort(); }
  catch (const StorageError &error) { check(std::string(error.what()) == "storage_unavailable"); }
}
static std::size_t descriptors() {
#ifdef __linux__
  const fs::path path("/proc/self/fd");
#else
  const fs::path path("/dev/fd");
#endif
  std::size_t count = 0;
  for (const auto &entry : fs::directory_iterator(path)) { (void)entry; ++count; }
  return count;
}
int main() {
  char name[] = "/tmp/wth-store-XXXXXX";
  char *created = ::mkdtemp(name);
  check(created != nullptr);
  const fs::path root(created);
  const std::string store = (root / "store").string();
  rejects("relative", false); rejects("/", false); rejects(std::string("/bad\0path", 9), false);
  rejects(std::string(4097, '/'), false); rejects(store, false);
  {
    Storage owned(store, true);
    check(owned.directory() >= 0);
    rejects(store, true); rejects(store, false);
    const pid_t child = ::fork();
    check(child >= 0);
    if (child == 0) {
      try { Storage competing(store, false); ::_exit(1); }
      catch (const StorageError &) { ::_exit(0); }
    }
    int status = 0;
    check(::waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    FileDescriptor data(::openat(owned.directory(), "settings", O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600));
    check(data.get() >= 0 && ::write(data.get(), "durable", 7) == 7);
    check(::fsync(data.get()) == 0 && ::fsync(owned.directory()) == 0);
    Storage moved(std::move(owned));
    // NOLINTNEXTLINE(bugprone-use-after-move): asserts the moved-from state
    check(moved.directory() >= 0 && owned.directory() == -1);
  }
  {
    Storage reopened(store, false);
    FileDescriptor data(::openat(reopened.directory(), "settings", O_RDONLY | O_CLOEXEC));
    char bytes[7] {};
    check(data.get() >= 0 && ::read(data.get(), bytes, sizeof bytes) == 7);
    check(std::string(bytes, sizeof bytes) == "durable");
  }
  // WTH-S03/WTH-V04: process death releases the OS lock without deleting durable settings.
  int channel[2]; check(::pipe(channel) == 0);
  const pid_t owner = ::fork(); check(owner >= 0);
  if (owner == 0) {
    (void)::close(channel[0]);
    Storage owned(store, false);
    check(::write(channel[1], "r", 1) == 1);
    for (;;) ::pause();
  }
  (void)::close(channel[1]); char ready = 0;
  check(::read(channel[0], &ready, 1) == 1 && ready == 'r');
  (void)::close(channel[0]);
  rejects(store, false);
  check(::kill(owner, SIGKILL) == 0); int status = 0;
  check(::waitpid(owner, &status, 0) == owner && WIFSIGNALED(status));
  { Storage reopened(store, false); check(reopened.directory() >= 0); }
  const auto before = descriptors();
  for (std::size_t i = 0; i < 1000; ++i) {
    Storage reopened(store, false); rejects(store, false);
  }
  check(descriptors() == before);
  check(::chmod(store.c_str(), 0755) == 0); rejects(store, false);
  check(::chmod(store.c_str(), 0700) == 0);
  const std::string link = (root / "link").string();
  check(::symlink(store.c_str(), link.c_str()) == 0); rejects(link, false);
  const std::string lock = (fs::path(store) / ".wotex-lock").string();
  check(::chmod(lock.c_str(), 0644) == 0); rejects(store, false);
  check(::chmod(lock.c_str(), 0600) == 0);
  const std::string alias = (root / "lock-alias").string();
  check(::link(lock.c_str(), alias.c_str()) == 0); rejects(store, false);
  check(::unlink(alias.c_str()) == 0);
  check(::unlink(lock.c_str()) == 0);
  check(::symlink((fs::path(store) / "settings").c_str(), lock.c_str()) == 0);
  rejects(store, false);
  fs::remove_all(root);
  std::cout << "WTH-S03 WTH-V04 exclusive storage, descriptor cleanup and durable reopen checks passed\n";
}
