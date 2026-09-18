// SPDX-License-Identifier: Apache-2.0
// The durable OSCORE context store of the native helper: deriving the storage
// identity of a security context (native/oscore/identity.c, HKDF-SHA-256 through
// OpenSSL), consuming it in a new private store directory, and reserving a
// sequence boundary, which rewrites the registry atomically with two fsync(2)
// calls (store.c). The store directories live below WCO_BENCH_SCRATCH, which
// must be on a local filesystem.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <utility>
#include <climits>
#include <sys/stat.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" {
#include "identity.h"
#include "store.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "oscore_store: " << what << " failed\n";
  std::exit(1);
}

// A private directory as the store requires it: owned, mode 0700, no symlink.
std::string private_directory(const std::string &path) {
  check(mkdir(path.c_str(), 0700) == 0 && chmod(path.c_str(), 0700) == 0, path.c_str());
  return path;
}

void remove_store(const std::string &path) {
  for (const char *name : {"/context.lock", "/contexts.v1"}) (void)unlink((path + name).c_str());
  (void)rmdir(path.c_str());
}

// Distinct synthetic identities; no two share a context or namespace hash.
struct wco_oscore_identity synthetic(std::uint32_t index) {
  struct wco_oscore_identity identity{};
  std::uint8_t *fields[] = {identity.context, identity.sender_space, identity.recipient_space};
  for (std::uint8_t tag = 0; tag < 3; ++tag) {
    fields[tag][0] = tag;
    std::memcpy(fields[tag] + 1, &index, sizeof(index));
  }
  return identity;
}

// Reserves ever higher boundaries in steps of 32, the helper's reservation window.
void reserve(wco_store *store, std::uint64_t *boundary) {
  *boundary += 32;
  check(
      wco_store_reserve(store, *boundary) == WCO_STORE_OK && wco_store_boundary(store) == *boundary,
      "reserve");
}

} // namespace

int main() {
  const char *scratch = std::getenv("WCO_BENCH_SCRATCH");
  check(scratch != nullptr, "WCO_BENCH_SCRATCH");
  char resolved[PATH_MAX];
  check(realpath(scratch, resolved) != nullptr, "realpath WCO_BENCH_SCRATCH");
  const std::string root = private_directory(std::string(resolved) + "/oscore-store");

  // RFC 8613, appendix C.1: the client's context.
  static const std::uint8_t secret[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
  static const std::uint8_t salt[] = {0x9e, 0x7c, 0xa9, 0x22, 0x23, 0x78, 0x63, 0x40};
  static const std::uint8_t recipient[] = {1};
  const wco_oscore_material material = {
      {secret, sizeof(secret)}, {salt, sizeof(salt)}, {nullptr, 0},
      {recipient, 1},           {nullptr, 0},         0};
  struct wco_oscore_identity identity{};

  ankerl::nanobench::Bench bench;
  bench.title("context store").warmup(3).minEpochTime(std::chrono::milliseconds(50));

  bench.unit("identity").run("derive the storage identity", [&] {
    check(wco_oscore_identity(&material, &identity) == 1, "identity");
  });

  // Each iteration consumes the identity in a new private directory: lock
  // creation, the first registry write and its rename, and closing the store.
  std::uint64_t created = 0;
  bench.unit("store").run("consume an identity in a new store", [&] {
    const std::string directory = private_directory(root + "/fresh-" + std::to_string(created++));
    wco_store *store = nullptr;
    check(wco_store_open(directory.c_str(), &identity, 32, &store) == WCO_STORE_OK, "store open");
    wco_store_close(store);
  });
  for (std::uint64_t index = 0; index < created; ++index)
    remove_store(root + "/fresh-" + std::to_string(index));

  // One store holding only its own context, and one holding 1,023 earlier
  // consumed contexts before its own: each reservation rewrites them all.
  const std::pair<std::uint32_t, const char *> registries[] = {
      {1, "reserve a sequence boundary, 1 context"},
      {1024, "reserve a sequence boundary, 1,024 contexts"}};
  for (const auto &registry : registries) {
    const std::uint32_t contexts = registry.first;
    const std::string directory = private_directory(root + "/contexts-" + std::to_string(contexts));
    for (std::uint32_t index = 1; index < contexts; ++index) {
      const struct wco_oscore_identity earlier = synthetic(index);
      wco_store *store = nullptr;
      check(wco_store_open(directory.c_str(), &earlier, 32, &store) == WCO_STORE_OK,
            "registry fill");
      wco_store_close(store);
    }
    wco_store *store = nullptr;
    check(wco_store_open(directory.c_str(), &identity, 32, &store) == WCO_STORE_OK, "store open");
    std::uint64_t boundary = 32;
    bench.unit("reservation").run(registry.second, [&] { reserve(store, &boundary); });
    wco_store_close(store);
    remove_store(directory);
  }

  (void)rmdir(root.c_str());
  return 0;
}
