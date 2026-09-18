// SPDX-License-Identifier: Apache-2.0
// The settings storage of the Thread host (priv/openthread/storage.hpp):
// opening an existing owner-only directory and taking its exclusive lock,
// refusing a second owner while the lock is held, and creating a new
// directory with its lock. WOTEX_THREAD_BENCH_STORAGE names an absolute
// directory path that does not exist yet. Each operation is one open.
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

#include <nanobench.h>

#include "storage.hpp"

namespace {

using namespace wotex::thread;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "settings_storage: " << what << " failed\n";
  std::exit(1);
}

bool refused(const std::string &path) {
  try {
    const Storage competing(path, false);
  } catch (const StorageError &) {
    return true;
  }
  return false;
}

// Removes a storage directory created by the benchmark and its lock file.
void remove(const std::string &path) {
  check(::unlink((path + "/.wotex-lock").c_str()) == 0, "unlink lock");
  check(::rmdir(path.c_str()) == 0, "remove directory");
}

} // namespace

int main() {
  const char *root = std::getenv("WOTEX_THREAD_BENCH_STORAGE");
  check(root != nullptr && root[0] == '/', "WOTEX_THREAD_BENCH_STORAGE");
  const std::string existing = std::string(root) + "/settings";
  const std::string created = std::string(root) + "/created";
  check(::mkdir(root, 0700) == 0, "create the storage root");
  { const Storage first(existing, true); }

  ankerl::nanobench::Bench bench;
  bench.title("settings storage")
      .unit("open")
      .batch(1)
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));

  bench.run("open existing directory, take the lock, release", [&] {
    const Storage storage(existing, false);
    check(storage.directory() >= 0, "open");
  });
  {
    const Storage owner(existing, false);
    bench.run("open refused while another owner holds the lock",
              [&] { check(refused(existing), "refusal"); });
  }
  bench.run("create directory, take the lock, release, remove", [&] {
    {
      const Storage storage(created, true);
      check(storage.directory() >= 0, "create");
    }
    remove(created);
  });

  remove(existing);
  check(::rmdir(root) == 0, "remove the storage root");
  return 0;
}
