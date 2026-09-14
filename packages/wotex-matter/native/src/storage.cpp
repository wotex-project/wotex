#include "wotex_matter/storage.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <set>
#include <string_view>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace wotex::matter {
namespace {

using Json = nlohmann::json;
using OrderedJson = nlohmann::ordered_json;
using Values = std::map<std::string, std::vector<std::uint8_t>>;

constexpr char kSchema[] = "wotex.matter.store";
constexpr char kStateFile[] = "store.json";
constexpr char kLockFile[] = "store.lock";
constexpr char kTemporaryFile[] = "store.tmp";
constexpr char kIntentFile[] = "store.pending";
constexpr std::size_t kMaximumFileBytes = 16U * 1024U * 1024U;
constexpr std::size_t kMaximumKeys = 4096;
constexpr std::size_t kMaximumKeyBytes = 255;
constexpr std::size_t kMaximumValueBytes = 65535;
constexpr std::uint64_t kMaximumOperationalNode = 0xFFFFFFEFFFFFFFFFULL;

bool ValidIdentity(const ControllerIdentity &identity) {
  return identity.fabric_id > 0 && identity.controller_node_id > 0 &&
         identity.controller_node_id <= kMaximumOperationalNode &&
         identity.vendor_id > 0 && identity.vendor_id < UINT16_MAX;
}

bool ValidUtf8(std::string_view value) {
  std::size_t index = 0;
  while (index < value.size()) {
    const auto first = static_cast<unsigned char>(value[index]);
    if (first == 0) {
      return false;
    }
    if (first <= 0x7F) {
      ++index;
      continue;
    }

    std::size_t continuation = 0;
    std::uint32_t codepoint = 0;
    if (first >= 0xC2 && first <= 0xDF) {
      continuation = 1;
      codepoint = first & 0x1F;
    } else if (first >= 0xE0 && first <= 0xEF) {
      continuation = 2;
      codepoint = first & 0x0F;
    } else if (first >= 0xF0 && first <= 0xF4) {
      continuation = 3;
      codepoint = first & 0x07;
    } else {
      return false;
    }

    if (index + continuation >= value.size()) {
      return false;
    }
    for (std::size_t offset = 1; offset <= continuation; ++offset) {
      const auto byte = static_cast<unsigned char>(value[index + offset]);
      if ((byte & 0xC0) != 0x80) {
        return false;
      }
      codepoint = (codepoint << 6U) | (byte & 0x3F);
    }

    if ((continuation == 2 && codepoint < 0x800) ||
        (continuation == 3 && codepoint < 0x10000) ||
        (codepoint >= 0xD800 && codepoint <= 0xDFFF) ||
        codepoint > 0x10FFFF) {
      return false;
    }

    index += continuation + 1;
  }
  return true;
}

bool ValidKey(const char *key, std::string &normalized) {
  if (key == nullptr) {
    return false;
  }
  const std::size_t length = strnlen(key, kMaximumKeyBytes + 1);
  if (length == 0 || length > kMaximumKeyBytes) {
    return false;
  }
  normalized.assign(key, length);
  return ValidUtf8(normalized);
}

std::string Base64Encode(const std::vector<std::uint8_t> &bytes) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve(((bytes.size() + 2) / 3) * 4);

  for (std::size_t index = 0; index < bytes.size(); index += 3) {
    const std::uint32_t first = bytes[index];
    const std::uint32_t second =
        index + 1 < bytes.size() ? bytes[index + 1] : 0;
    const std::uint32_t third =
        index + 2 < bytes.size() ? bytes[index + 2] : 0;
    const std::uint32_t value = (first << 16U) | (second << 8U) | third;

    encoded.push_back(alphabet[(value >> 18U) & 0x3F]);
    encoded.push_back(alphabet[(value >> 12U) & 0x3F]);
    encoded.push_back(index + 1 < bytes.size()
                          ? alphabet[(value >> 6U) & 0x3F]
                          : '=');
    encoded.push_back(index + 2 < bytes.size() ? alphabet[value & 0x3F]
                                               : '=');
  }
  return encoded;
}

int Base64Value(char value) {
  if (value >= 'A' && value <= 'Z') {
    return value - 'A';
  }
  if (value >= 'a' && value <= 'z') {
    return value - 'a' + 26;
  }
  if (value >= '0' && value <= '9') {
    return value - '0' + 52;
  }
  if (value == '+') {
    return 62;
  }
  if (value == '/') {
    return 63;
  }
  return -1;
}

bool Base64Decode(const std::string &encoded,
                  std::vector<std::uint8_t> &bytes) {
  if (encoded.size() % 4 != 0) {
    return false;
  }
  bytes.clear();
  bytes.reserve((encoded.size() / 4) * 3);

  for (std::size_t index = 0; index < encoded.size(); index += 4) {
    const bool last = index + 4 == encoded.size();
    const int a = Base64Value(encoded[index]);
    const int b = Base64Value(encoded[index + 1]);
    const bool pad_c = encoded[index + 2] == '=';
    const bool pad_d = encoded[index + 3] == '=';
    const int c = pad_c ? 0 : Base64Value(encoded[index + 2]);
    const int d = pad_d ? 0 : Base64Value(encoded[index + 3]);

    if (a < 0 || b < 0 || c < 0 || d < 0 || (!last && (pad_c || pad_d)) ||
        (pad_c && !pad_d)) {
      return false;
    }

    const std::uint32_t value = (static_cast<std::uint32_t>(a) << 18U) |
        (static_cast<std::uint32_t>(b) << 12U) |
        (static_cast<std::uint32_t>(c) << 6U) |
        static_cast<std::uint32_t>(d);
    bytes.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xFF));
    if (!pad_c) {
      bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFF));
    }
    if (!pad_d) {
      bytes.push_back(static_cast<std::uint8_t>(value & 0xFF));
    }
  }

  return bytes.size() <= kMaximumValueBytes && Base64Encode(bytes) == encoded;
}

bool WriteAll(int descriptor, std::string_view bytes) {
  std::size_t written = 0;
  while (written < bytes.size()) {
    const ssize_t count =
        write(descriptor, bytes.data() + written, bytes.size() - written);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return false;
    }
    written += static_cast<std::size_t>(count);
  }
  return true;
}

bool ExactRegularFile(int descriptor) {
  struct stat status {};
  return fstat(descriptor, &status) == 0 && S_ISREG(status.st_mode) &&
      status.st_uid == geteuid() && (status.st_mode & 0777) == 0600;
}

bool CleanCommitState(int directory_fd) {
  struct stat status {};
  for (const char *name : {kTemporaryFile, kIntentFile}) {
    if (fstatat(directory_fd, name, &status, AT_SYMLINK_NOFOLLOW) == 0 ||
        errno != ENOENT) {
      return false;
    }
  }
  return true;
}

bool ReadState(int directory_fd, std::string &contents) {
  const int descriptor =
      openat(directory_fd, kStateFile, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0 || !ExactRegularFile(descriptor)) {
    if (descriptor >= 0) {
      close(descriptor);
    }
    return false;
  }

  struct stat status {};
  if (fstat(descriptor, &status) != 0 || status.st_size <= 0 ||
      static_cast<std::uint64_t>(status.st_size) > kMaximumFileBytes) {
    close(descriptor);
    return false;
  }

  contents.assign(static_cast<std::size_t>(status.st_size), '\0');
  std::size_t offset = 0;
  while (offset < contents.size()) {
    const ssize_t count =
        read(descriptor, contents.data() + offset, contents.size() - offset);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      close(descriptor);
      return false;
    }
    offset += static_cast<std::size_t>(count);
  }

  const bool closed = close(descriptor) == 0;
  return closed;
}

bool ExactKeys(const Json &document) {
  static const std::set<std::string> expected = {
      "authority", "controller_node_id", "fabric_id", "schema", "values",
      "vendor_id", "version"};
  if (!document.is_object() || document.size() != expected.size()) {
    return false;
  }
  std::set<std::string> actual;
  for (const auto &entry : document.items()) {
    actual.insert(entry.key());
  }
  return actual == expected;
}

bool ParseState(const std::string &contents,
                const ControllerIdentity &expected_identity, Values &values) {
  bool duplicate = false;
  std::map<int, std::set<std::string>> keys;
  const auto callback = [&duplicate, &keys](int depth, Json::parse_event_t event,
                                            Json &parsed) {
    if (event == Json::parse_event_t::object_start) {
      keys[depth].clear();
    } else if (event == Json::parse_event_t::key) {
      const std::string key = parsed.get<std::string>();
      if (!keys[depth].insert(key).second) {
        duplicate = true;
      }
    }
    return true;
  };

  Json document;
  try {
    document = Json::parse(contents, callback, false, false);
  } catch (...) {
    return false;
  }

  if (duplicate || document.is_discarded() || !ExactKeys(document) ||
      !document["schema"].is_string() ||
      document["schema"].get<std::string>() != kSchema ||
      !document["version"].is_number_unsigned() ||
      document["version"].get<std::uint64_t>() != 1 ||
      !document["fabric_id"].is_number_unsigned() ||
      !document["controller_node_id"].is_number_unsigned() ||
      !document["vendor_id"].is_number_unsigned() ||
      !document["authority"].is_string() ||
      document["authority"].get<std::string>() != "generate_root" ||
      !document["values"].is_object()) {
    return false;
  }

  const std::uint64_t vendor_id = document["vendor_id"].get<std::uint64_t>();
  if (vendor_id == 0 || vendor_id >= UINT16_MAX) {
    return false;
  }
  const ControllerIdentity identity{
      document["fabric_id"].get<std::uint64_t>(),
      document["controller_node_id"].get<std::uint64_t>(),
      static_cast<std::uint16_t>(vendor_id)};
  if (!ValidIdentity(identity) || !(identity == expected_identity) ||
      document["values"].size() > kMaximumKeys) {
    return false;
  }

  Values loaded;
  for (const auto &entry : document["values"].items()) {
    if (entry.key().empty() || entry.key().size() > kMaximumKeyBytes ||
        !ValidUtf8(entry.key()) || !entry.value().is_string()) {
      return false;
    }
    std::vector<std::uint8_t> decoded;
    if (!Base64Decode(entry.value().get<std::string>(), decoded)) {
      return false;
    }
    loaded.emplace(entry.key(), std::move(decoded));
  }

  values = std::move(loaded);
  return true;
}

bool SerializeState(const ControllerIdentity &identity, const Values &values,
                    std::string &contents) {
  try {
    OrderedJson encoded_values = OrderedJson::object();
    for (const auto &[key, value] : values) {
      encoded_values[key] = Base64Encode(value);
    }

    OrderedJson document = OrderedJson::object();
    document["schema"] = kSchema;
    document["version"] = 1;
    document["fabric_id"] = identity.fabric_id;
    document["controller_node_id"] = identity.controller_node_id;
    document["vendor_id"] = identity.vendor_id;
    document["authority"] = "generate_root";
    document["values"] = std::move(encoded_values);
    contents = document.dump();
    contents.push_back('\n');
    return contents.size() <= kMaximumFileBytes;
  } catch (...) {
    return false;
  }
}

bool ValidDirectory(const std::string &path) {
  struct stat status {};
  return lstat(path.c_str(), &status) == 0 && S_ISDIR(status.st_mode) &&
      status.st_uid == geteuid() && (status.st_mode & 0777) == 0700;
}

int OpenDirectory(const std::string &path) {
  return open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
}

CHIP_ERROR OpenLock(int directory_fd, bool create, int &lock_fd) {
  const int flags = O_RDWR | O_CLOEXEC | O_NOFOLLOW |
      (create ? O_CREAT | O_EXCL : 0);
  lock_fd = openat(directory_fd, kLockFile, flags, 0600);
  if (lock_fd < 0 || !ExactRegularFile(lock_fd) ||
      flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
    if (lock_fd >= 0) {
      close(lock_fd);
      lock_fd = -1;
    }
    return CHIP_ERROR_OPEN_FAILED;
  }
  return CHIP_NO_ERROR;
}

} // namespace

bool ControllerIdentity::operator==(const ControllerIdentity &other) const {
  return fabric_id == other.fabric_id &&
      controller_node_id == other.controller_node_id &&
      vendor_id == other.vendor_id;
}

CHIP_ERROR DurableStorage::Open(const std::string &path,
                                StorageMode storage_mode,
                                AuthorityMode authority_mode,
                                const ControllerIdentity &identity,
                                std::unique_ptr<DurableStorage> &storage) {
  storage.reset();
  if (!std::filesystem::path(path).is_absolute() || path.find('\0') != std::string::npos ||
      !ValidIdentity(identity) ||
      (storage_mode == StorageMode::CreateNew &&
       authority_mode != AuthorityMode::GenerateRoot) ||
      (storage_mode == StorageMode::OpenExisting &&
       authority_mode != AuthorityMode::Stored)) {
    return CHIP_ERROR_INVALID_ARGUMENT;
  }

  const bool create = storage_mode == StorageMode::CreateNew;
  if (create) {
    struct stat status {};
    if (lstat(path.c_str(), &status) == 0 || errno != ENOENT ||
        mkdir(path.c_str(), 0700) != 0) {
      return CHIP_ERROR_OPEN_FAILED;
    }
  }

  if (!ValidDirectory(path)) {
    return CHIP_ERROR_OPEN_FAILED;
  }

  int directory_fd = OpenDirectory(path);
  if (directory_fd < 0) {
    return CHIP_ERROR_OPEN_FAILED;
  }

  int lock_fd = -1;
  const CHIP_ERROR lock_error = OpenLock(directory_fd, create, lock_fd);
  if (lock_error != CHIP_NO_ERROR) {
    close(directory_fd);
    return lock_error;
  }

  Values values;
  if (!CleanCommitState(directory_fd)) {
    close(lock_fd);
    close(directory_fd);
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  }

  if (!create) {
    std::string contents;
    if (!ReadState(directory_fd, contents) ||
        !ParseState(contents, identity, values)) {
      close(lock_fd);
      close(directory_fd);
      return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
    }
  }

  auto opened = std::unique_ptr<DurableStorage>(
      new DurableStorage(path, identity, directory_fd, lock_fd,
                         std::move(values)));
  if (create) {
    const CHIP_ERROR commit_error = opened->Commit(opened->values_);
    if (commit_error != CHIP_NO_ERROR) {
      return commit_error;
    }
  }

  storage = std::move(opened);
  return CHIP_NO_ERROR;
}

DurableStorage::DurableStorage(std::string path, ControllerIdentity identity,
                               int directory_fd, int lock_fd, Values values)
    : path_(std::move(path)), identity_(identity), directory_fd_(directory_fd),
      lock_fd_(lock_fd), values_(std::move(values)) {}

DurableStorage::~DurableStorage() {
  if (lock_fd_ >= 0) {
    flock(lock_fd_, LOCK_UN);
    close(lock_fd_);
  }
  if (directory_fd_ >= 0) {
    close(directory_fd_);
  }
}

CHIP_ERROR DurableStorage::SyncGetKeyValue(const char *key, void *buffer,
                                           std::uint16_t &size) {
  if (poisoned_) {
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  }
  std::string normalized;
  if (!ValidKey(key, normalized) || (buffer == nullptr && size > 0)) {
    return CHIP_ERROR_INVALID_ARGUMENT;
  }

  const auto found = values_.find(normalized);
  if (found == values_.end()) {
    return CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND;
  }

  const std::size_t available = size;
  const std::size_t copied = std::min(available, found->second.size());
  if (copied > 0) {
    std::memcpy(buffer, found->second.data(), copied);
  }
  size = static_cast<std::uint16_t>(copied);
  return copied < found->second.size() ? CHIP_ERROR_BUFFER_TOO_SMALL
                                      : CHIP_NO_ERROR;
}

CHIP_ERROR DurableStorage::SyncSetKeyValue(const char *key, const void *value,
                                           std::uint16_t size) {
  if (poisoned_) {
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  }
  std::string normalized;
  if (!ValidKey(key, normalized) || (value == nullptr && size > 0)) {
    return CHIP_ERROR_INVALID_ARGUMENT;
  }
  if (values_.find(normalized) == values_.end() &&
      values_.size() >= kMaximumKeys) {
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  }

  Values next = values_;
  const auto *bytes = static_cast<const std::uint8_t *>(value);
  next[normalized] = size == 0
      ? std::vector<std::uint8_t>{}
      : std::vector<std::uint8_t>(bytes, bytes + size);
  const CHIP_ERROR error = Commit(next);
  if (error == CHIP_NO_ERROR) {
    values_ = std::move(next);
  }
  return error;
}

CHIP_ERROR DurableStorage::SyncDeleteKeyValue(const char *key) {
  if (poisoned_) {
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  }
  std::string normalized;
  if (!ValidKey(key, normalized)) {
    return CHIP_ERROR_INVALID_ARGUMENT;
  }
  if (values_.find(normalized) == values_.end()) {
    return CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND;
  }

  Values next = values_;
  next.erase(normalized);
  const CHIP_ERROR error = Commit(next);
  if (error == CHIP_NO_ERROR) {
    values_ = std::move(next);
  }
  return error;
}

const ControllerIdentity &DurableStorage::identity() const { return identity_; }

CHIP_ERROR DurableStorage::EnterProcessDirectory() const {
  return directory_fd_ >= 0 && fchdir(directory_fd_) == 0
      ? CHIP_NO_ERROR
      : CHIP_ERROR_OPEN_FAILED;
}

bool DurableStorage::poisoned() const { return poisoned_; }

void DurableStorage::Poison() { poisoned_ = true; }

CHIP_ERROR DurableStorage::Commit(const Values &values) {
  std::string contents;
  if (poisoned_ || !SerializeState(identity_, values, contents) ||
      !CleanCommitState(directory_fd_)) {
    Poison();
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  }

  int temporary_fd = openat(directory_fd_, kTemporaryFile,
                            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                            0600);
  int intent_fd = -1;
  const auto fail = [this, &temporary_fd, &intent_fd]() {
    if (temporary_fd >= 0) {
      close(temporary_fd);
      temporary_fd = -1;
    }
    if (intent_fd >= 0) {
      close(intent_fd);
      intent_fd = -1;
    }
    Poison();
    return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  };

  if (temporary_fd < 0 || fchmod(temporary_fd, 0600) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::TemporaryOpened);
#endif
  if (!WriteAll(temporary_fd, contents)) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::TemporaryWritten);
#endif
  if (fsync(temporary_fd) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::TemporarySynced);
#endif
  if (close(temporary_fd) != 0) {
    temporary_fd = -1;
    return fail();
  }
  temporary_fd = -1;

  intent_fd = openat(directory_fd_, kIntentFile,
                     O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                     0600);
  if (intent_fd < 0 || fchmod(intent_fd, 0600) != 0 ||
      !WriteAll(intent_fd, "pending\n") || fsync(intent_fd) != 0) {
    return fail();
  }
  if (close(intent_fd) != 0) {
    intent_fd = -1;
    return fail();
  }
  intent_fd = -1;
  if (fsync(directory_fd_) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::IntentSynced);
#endif

  if (renameat(directory_fd_, kTemporaryFile, directory_fd_, kStateFile) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::StateRenamed);
#endif
  if (fsync(directory_fd_) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::StateDirectorySynced);
#endif
  if (unlinkat(directory_fd_, kIntentFile, 0) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::IntentRemoved);
#endif
  if (fsync(directory_fd_) != 0) {
    return fail();
  }
#ifdef WOTEX_MATTER_STORAGE_TESTING
  Checkpoint(CommitStage::FinalDirectorySynced);
#endif
  return CHIP_NO_ERROR;
}

#ifdef WOTEX_MATTER_STORAGE_TESTING
void DurableStorage::CrashAtForTesting(CommitStage stage) {
  crash_stage_ = stage;
}

void DurableStorage::Checkpoint(CommitStage stage) const {
  if (crash_stage_ == stage) {
    _exit(90 + static_cast<int>(stage));
  }
}
#endif

} // namespace wotex::matter
