#ifndef WOTEX_MATTER_STORAGE_HPP
#define WOTEX_MATTER_STORAGE_HPP

#include <lib/core/CHIPPersistentStorageDelegate.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace wotex::matter {

enum class StorageMode { CreateNew, OpenExisting };
enum class AuthorityMode { GenerateRoot, Stored };

struct ControllerIdentity {
  std::uint64_t fabric_id{0};
  std::uint64_t controller_node_id{0};
  std::uint16_t vendor_id{0};

  bool operator==(const ControllerIdentity &other) const;
};

#ifdef WOTEX_MATTER_STORAGE_TESTING
enum class CommitStage {
  None,
  TemporaryOpened,
  TemporaryWritten,
  TemporarySynced,
  IntentSynced,
  StateRenamed,
  StateDirectorySynced,
  IntentRemoved,
  FinalDirectorySynced
};
#endif

class DurableStorage final : public chip::PersistentStorageDelegate {
 public:
  static CHIP_ERROR Open(const std::string &path, StorageMode storage_mode,
                         AuthorityMode authority_mode,
                         const ControllerIdentity &identity,
                         std::unique_ptr<DurableStorage> &storage);

  ~DurableStorage() override;
  DurableStorage(const DurableStorage &) = delete;
  DurableStorage &operator=(const DurableStorage &) = delete;

  CHIP_ERROR SyncGetKeyValue(const char *key, void *buffer,
                             std::uint16_t &size) override;
  CHIP_ERROR SyncSetKeyValue(const char *key, const void *value,
                             std::uint16_t size) override;
  CHIP_ERROR SyncDeleteKeyValue(const char *key) override;

  const ControllerIdentity &identity() const;
  CHIP_ERROR EnterProcessDirectory() const;
  bool poisoned() const;

#ifdef WOTEX_MATTER_STORAGE_TESTING
  void CrashAtForTesting(CommitStage stage);
#endif

 private:
  using Values = std::map<std::string, std::vector<std::uint8_t>>;

  DurableStorage(std::string path, ControllerIdentity identity, int directory_fd,
                 int lock_fd, Values values);

  CHIP_ERROR Commit(const Values &values);
  void Poison();

#ifdef WOTEX_MATTER_STORAGE_TESTING
  void Checkpoint(CommitStage stage) const;
  CommitStage crash_stage_{CommitStage::None};
#endif

  std::string path_;
  ControllerIdentity identity_;
  int directory_fd_{-1};
  int lock_fd_{-1};
  Values values_;
  bool poisoned_{false};
};

} // namespace wotex::matter

#endif
