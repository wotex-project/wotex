#include "wotex_matter/sdk_storage.hpp"
#include "wotex_matter/storage.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <type_traits>
#include <unistd.h>
#include <vector>

namespace {

using wotex::matter::AuthorityMode;
using wotex::matter::CommitStage;
using wotex::matter::ControllerIdentity;
using wotex::matter::DurableStorage;
using wotex::matter::SdkStorageBinding;
using wotex::matter::StorageMode;

constexpr ControllerIdentity kIdentity{1, 0x1234, 0xFFF1};

static_assert(std::is_base_of_v<chip::PersistentStorageDelegate, DurableStorage>);
static_assert(std::is_class_v<SdkStorageBinding>);

void Require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void RequireError(CHIP_ERROR actual, CHIP_ERROR expected,
                  const std::string &message) {
  Require(actual == expected, message);
}

class TemporaryDirectory final {
 public:
  TemporaryDirectory() {
    std::array<char, 64> pattern{};
    const std::string prefix = "/tmp/wotex-matter-storage.XXXXXX";
    std::copy(prefix.begin(), prefix.end(), pattern.begin());
    char *created = mkdtemp(pattern.data());
    Require(created != nullptr, "temporary directory creation failed");
    root_ = created;
  }

  ~TemporaryDirectory() { std::filesystem::remove_all(root_); }

  std::string Store(const std::string &name = "store") const {
    return root_ + "/" + name;
  }

 private:
  std::string root_;
};

std::unique_ptr<DurableStorage> Create(const std::string &path,
                                       ControllerIdentity identity = kIdentity) {
  std::unique_ptr<DurableStorage> storage;
  RequireError(DurableStorage::Open(path, StorageMode::CreateNew,
                                    AuthorityMode::GenerateRoot, identity,
                                    storage),
               CHIP_NO_ERROR, "create_new failed");
  Require(storage != nullptr, "create_new returned no store");
  return storage;
}

CHIP_ERROR OpenExisting(const std::string &path,
                        std::unique_ptr<DurableStorage> &storage,
                        ControllerIdentity identity = kIdentity) {
  return DurableStorage::Open(path, StorageMode::OpenExisting,
                              AuthorityMode::Stored, identity, storage);
}

void WriteAll(int descriptor, const std::string &contents) {
  std::size_t offset = 0;
  while (offset < contents.size()) {
    const ssize_t count =
        write(descriptor, contents.data() + offset, contents.size() - offset);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    Require(count > 0, "fixture write failed");
    offset += static_cast<std::size_t>(count);
  }
}

void ReplaceState(const std::string &path, const std::string &contents) {
  const std::string state = path + "/store.json";
  const int descriptor =
      open(state.c_str(), O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW);
  Require(descriptor >= 0, "state fixture open failed");
  WriteAll(descriptor, contents);
  Require(fsync(descriptor) == 0, "state fixture fsync failed");
  Require(close(descriptor) == 0, "state fixture close failed");
}

nlohmann::ordered_json Document(const nlohmann::ordered_json &values) {
  return nlohmann::ordered_json{
      {"schema", "wotex.matter.store"},
      {"version", 1},
      {"fabric_id", kIdentity.fabric_id},
      {"controller_node_id", kIdentity.controller_node_id},
      {"vendor_id", kIdentity.vendor_id},
      {"authority", "generate_root"},
      {"values", values}};
}

std::vector<std::uint8_t> ReadValue(DurableStorage &storage,
                                    const std::string &key) {
  std::array<std::uint8_t, UINT16_MAX> buffer{};
  std::uint16_t size = static_cast<std::uint16_t>(buffer.size());
  RequireError(storage.SyncGetKeyValue(key.c_str(), buffer.data(), size),
               CHIP_NO_ERROR, "stored value read failed");
  return {buffer.begin(), buffer.begin() + size};
}

void TestModesIdentityLockAndPermissions() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  std::unique_ptr<DurableStorage> missing;

  RequireError(OpenExisting(path, missing), CHIP_ERROR_OPEN_FAILED,
               "open_existing accepted missing storage");
  RequireError(DurableStorage::Open("relative", StorageMode::CreateNew,
                                    AuthorityMode::GenerateRoot, kIdentity,
                                    missing),
               CHIP_ERROR_INVALID_ARGUMENT, "relative storage path accepted");
  RequireError(DurableStorage::Open(path, StorageMode::CreateNew,
                                    AuthorityMode::Stored, kIdentity, missing),
               CHIP_ERROR_INVALID_ARGUMENT,
               "create_new accepted stored authority");

  auto storage = Create(path);
  Require(storage->identity() == kIdentity, "identity was not retained");

  struct stat status {};
  Require(stat(path.c_str(), &status) == 0 && (status.st_mode & 0777) == 0700,
          "storage directory is not owner-only");
  Require(stat((path + "/store.json").c_str(), &status) == 0 &&
              (status.st_mode & 0777) == 0600,
          "state file is not owner-only");
  Require(stat((path + "/store.lock").c_str(), &status) == 0 &&
              (status.st_mode & 0777) == 0600,
          "lock file is not owner-only");

  std::unique_ptr<DurableStorage> concurrent;
  RequireError(OpenExisting(path, concurrent), CHIP_ERROR_OPEN_FAILED,
               "exclusive lock allowed a concurrent opener");
  RequireError(DurableStorage::Open(path, StorageMode::CreateNew,
                                    AuthorityMode::GenerateRoot, kIdentity,
                                    concurrent),
               CHIP_ERROR_OPEN_FAILED, "create_new reused existing storage");

  storage.reset();
  RequireError(DurableStorage::Open(path, StorageMode::OpenExisting,
                                    AuthorityMode::GenerateRoot, kIdentity,
                                    concurrent),
               CHIP_ERROR_INVALID_ARGUMENT,
               "open_existing accepted root generation");
  RequireError(OpenExisting(path, concurrent,
                            ControllerIdentity{2, kIdentity.controller_node_id,
                                               kIdentity.vendor_id}),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "wrong fabric reopened durable authority");
  RequireError(OpenExisting(path, concurrent,
                            ControllerIdentity{kIdentity.fabric_id, 9,
                                               kIdentity.vendor_id}),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "wrong controller reopened durable authority");
  RequireError(OpenExisting(path, concurrent,
                            ControllerIdentity{kIdentity.fabric_id,
                                               kIdentity.controller_node_id, 1}),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "wrong vendor reopened durable authority");
  RequireError(OpenExisting(path, concurrent), CHIP_NO_ERROR,
               "matching identity did not reopen");
}

void TestDelegateSemanticsAndDurability() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  auto storage = Create(path);
  const std::vector<std::uint8_t> authority = {0x00, 0xFF, 0x42, 0x00};

  RequireError(storage->SyncSetKeyValue("wotex/authority/root-key",
                                        authority.data(), authority.size()),
               CHIP_NO_ERROR, "authority key write failed");
  Require(storage->SyncDoesKeyExist("wotex/authority/root-key"),
          "stored authority key is absent");

  std::array<std::uint8_t, 2> partial{};
  std::uint16_t size = partial.size();
  RequireError(storage->SyncGetKeyValue("wotex/authority/root-key",
                                        partial.data(), size),
               CHIP_ERROR_BUFFER_TOO_SMALL,
               "short read did not report buffer-too-small");
  Require(size == 2 && partial[0] == 0x00 && partial[1] == 0xFF,
          "short read did not copy the admitted prefix");

  size = 1;
  RequireError(storage->SyncGetKeyValue("wotex/authority/root-key", nullptr,
                                        size),
               CHIP_ERROR_INVALID_ARGUMENT,
               "null nonempty output buffer was accepted");
  size = 0;
  RequireError(storage->SyncGetKeyValue("missing", nullptr, size),
               CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND,
               "missing key was fabricated");

  RequireError(storage->SyncSetKeyValue("empty", nullptr, 0), CHIP_NO_ERROR,
               "explicit empty value was rejected");
  size = 0;
  RequireError(storage->SyncGetKeyValue("empty", nullptr, size), CHIP_NO_ERROR,
               "explicit empty value was not retained");

  std::string long_key(256, 'k');
  RequireError(storage->SyncSetKeyValue(long_key.c_str(), nullptr, 0),
               CHIP_ERROR_INVALID_ARGUMENT, "oversized key was accepted");
  const char invalid_utf8[] = {'k', static_cast<char>(0xFF), '\0'};
  RequireError(storage->SyncSetKeyValue(invalid_utf8, nullptr, 0),
               CHIP_ERROR_INVALID_ARGUMENT, "invalid UTF-8 key was accepted");
  RequireError(storage->SyncSetKeyValue(nullptr, nullptr, 0),
               CHIP_ERROR_INVALID_ARGUMENT, "null key was accepted");
  const std::uint8_t byte = 1;
  RequireError(storage->SyncSetKeyValue("null-value", nullptr, 1),
               CHIP_ERROR_INVALID_ARGUMENT,
               "null nonempty input value was accepted");

  std::vector<std::uint8_t> maximum(UINT16_MAX, 0xA5);
  RequireError(storage->SyncSetKeyValue("maximum", maximum.data(),
                                        static_cast<std::uint16_t>(maximum.size())),
               CHIP_NO_ERROR, "maximum value was rejected");
  Require(ReadValue(*storage, "maximum") == maximum,
          "maximum value changed during persistence");
  Require(byte == 1, "test input changed unexpectedly");

  storage.reset();
  std::unique_ptr<DurableStorage> reopened;
  RequireError(OpenExisting(path, reopened), CHIP_NO_ERROR,
               "durable store did not reopen");
  Require(ReadValue(*reopened, "wotex/authority/root-key") == authority,
          "authority bytes changed after restart");
  RequireError(reopened->SyncDeleteKeyValue("wotex/authority/root-key"),
               CHIP_NO_ERROR, "authority delete failed");
  RequireError(reopened->SyncDeleteKeyValue("wotex/authority/root-key"),
               CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND,
               "missing delete was reported as success");
}

void TestCorruptAndBoundedStateFailsClosed() {
  const std::vector<std::string> corrupt = {
      "not json\n",
      "{\"schema\":\"wotex.matter.store\",\"schema\":\"wotex.matter.store\","
      "\"version\":1,\"fabric_id\":1,\"controller_node_id\":4660,"
      "\"vendor_id\":65521,\"authority\":\"generate_root\",\"values\":{}}\n",
      "{\"schema\":\"wotex.matter.store\",\"version\":1,\"fabric_id\":1,"
      "\"controller_node_id\":4660,\"vendor_id\":65521,"
      "\"authority\":\"generate_root\",\"values\":{\"key\":\"A===\"}}\n",
      "{\"schema\":\"wotex.matter.store\",\"version\":1,\"fabric_id\":1,"
      "\"controller_node_id\":4660,\"vendor_id\":65521,"
      "\"authority\":\"generate_root\",\"values\":{},\"extra\":true}\n"};

  for (std::size_t index = 0; index < corrupt.size(); ++index) {
    TemporaryDirectory temporary;
    const std::string path = temporary.Store(std::to_string(index));
    Create(path).reset();
    ReplaceState(path, corrupt[index]);
    std::unique_ptr<DurableStorage> storage;
    RequireError(OpenExisting(path, storage), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "corrupt state reopened");
  }

  TemporaryDirectory key_limit_directory;
  const std::string key_limit_path = key_limit_directory.Store();
  Create(key_limit_path).reset();
  nlohmann::ordered_json values = nlohmann::ordered_json::object();
  for (std::size_t index = 0; index < 4096; ++index) {
    values["key-" + std::to_string(index)] = "";
  }
  ReplaceState(key_limit_path, Document(values).dump() + "\n");
  std::unique_ptr<DurableStorage> full;
  RequireError(OpenExisting(key_limit_path, full), CHIP_NO_ERROR,
               "maximum key set did not load");
  RequireError(full->SyncSetKeyValue("overflow", nullptr, 0),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "4097th key was accepted");

  TemporaryDirectory oversized_directory;
  const std::string oversized_path = oversized_directory.Store();
  Create(oversized_path).reset();
  ReplaceState(oversized_path, std::string(16U * 1024U * 1024U + 1U, 'x'));
  std::unique_ptr<DurableStorage> oversized;
  RequireError(OpenExisting(oversized_path, oversized),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "oversized state was allocated and accepted");

  TemporaryDirectory symlink_directory;
  const std::string symlink_path = symlink_directory.Store();
  Create(symlink_path).reset();
  Require(unlink((symlink_path + "/store.json").c_str()) == 0,
          "state fixture unlink failed");
  Require(symlink("/dev/null", (symlink_path + "/store.json").c_str()) == 0,
          "state symlink fixture failed");
  std::unique_ptr<DurableStorage> symlinked;
  RequireError(OpenExisting(symlink_path, symlinked),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "state symlink was followed");
}

void TestCommitFailurePoisonsTheOwner() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  auto storage = Create(path);
  const int stale = open((path + "/store.tmp").c_str(),
                         O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  Require(stale >= 0 && close(stale) == 0,
          "commit-failure fixture creation failed");

  const std::uint8_t value = 1;
  RequireError(storage->SyncSetKeyValue("will-not-commit", &value, 1),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "incomplete commit state was reported as success");
  Require(storage->poisoned(), "durable-write failure did not poison the owner");
  std::uint16_t size = 0;
  RequireError(storage->SyncGetKeyValue("empty", nullptr, size),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED,
               "poisoned owner continued serving values");
}

void TestCrashBoundaries() {
  const std::vector<CommitStage> fatal = {
      CommitStage::TemporaryOpened, CommitStage::TemporaryWritten,
      CommitStage::TemporarySynced, CommitStage::IntentSynced,
      CommitStage::StateRenamed, CommitStage::StateDirectorySynced};
  const std::vector<CommitStage> durable = {CommitStage::IntentRemoved,
                                             CommitStage::FinalDirectorySynced};

  for (CommitStage stage : fatal) {
    TemporaryDirectory temporary;
    const std::string path = temporary.Store();
    Create(path).reset();
    const pid_t child = fork();
    Require(child >= 0, "crash child fork failed");
    if (child == 0) {
      std::unique_ptr<DurableStorage> storage;
      if (OpenExisting(path, storage) != CHIP_NO_ERROR) {
        _exit(10);
      }
      storage->CrashAtForTesting(stage);
      const std::uint8_t value = 1;
      if (storage->SyncSetKeyValue("crash", &value, 1) != CHIP_NO_ERROR) {
        _exit(12);
      }
      _exit(11);
    }
    int status = 0;
    Require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                WEXITSTATUS(status) == 90 + static_cast<int>(stage),
            "crash checkpoint did not terminate at its boundary");
    std::unique_ptr<DurableStorage> reopened;
    RequireError(OpenExisting(path, reopened),
                 CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "incomplete commit reopened stale state");
  }

  for (CommitStage stage : durable) {
    TemporaryDirectory temporary;
    const std::string path = temporary.Store();
    Create(path).reset();
    const pid_t child = fork();
    Require(child >= 0, "durable child fork failed");
    if (child == 0) {
      std::unique_ptr<DurableStorage> storage;
      if (OpenExisting(path, storage) != CHIP_NO_ERROR) {
        _exit(10);
      }
      storage->CrashAtForTesting(stage);
      const std::uint8_t value = 7;
      if (storage->SyncSetKeyValue("durable", &value, 1) != CHIP_NO_ERROR) {
        _exit(12);
      }
      _exit(11);
    }
    int status = 0;
    Require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                WEXITSTATUS(status) == 90 + static_cast<int>(stage),
            "durable checkpoint did not terminate at its boundary");
    std::unique_ptr<DurableStorage> reopened;
    RequireError(OpenExisting(path, reopened), CHIP_NO_ERROR,
                 "durably committed state did not reopen");
    Require(ReadValue(*reopened, "durable") == std::vector<std::uint8_t>{7},
            "durable crash boundary lost the committed value");
  }
}

} // namespace

int main() {
  try {
    TestModesIdentityLockAndPermissions();
    TestDelegateSemanticsAndDurability();
    TestCorruptAndBoundedStateFailsClosed();
    TestCommitFailurePoisonsTheOwner();
    TestCrashBoundaries();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
