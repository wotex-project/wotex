#ifndef WOTEX_MATTER_STORAGE_HPP
#define WOTEX_MATTER_STORAGE_HPP

#include <lib/core/CHIPPersistentStorageDelegate.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <variant>
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

// A server has no preselected fabric or controller node. Its consumer-owned
// identity and model digest are immutable for the lifetime of this store.
struct BridgeIdentity {
  std::string bridge_id;
  std::string model_sha256;
  std::uint16_t vendor_id{0};
  std::uint16_t product_id{0};

  bool operator==(const BridgeIdentity &other) const;
};

enum class BridgedDeviceType : std::uint16_t { OnOffLight = 0x0100, TemperatureSensor = 0x0302 };

struct BridgeEndpoint {
  std::uint16_t endpoint{0};
  BridgedDeviceType device_type{BridgedDeviceType::OnOffLight};
};

class BridgeStorage;

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
  friend class BridgeStorage;

  using Values = std::map<std::string, std::vector<std::uint8_t>>;
  using Identity = std::variant<ControllerIdentity, BridgeIdentity>;
  using Endpoints = std::map<std::string, BridgeEndpoint>;

  static CHIP_ERROR OpenStore(const std::string &path, StorageMode mode, const Identity &identity,
                              std::unique_ptr<DurableStorage> &storage);

  DurableStorage(Identity identity, int directory_fd, int lock_fd, Values values,
                 Endpoints endpoints, std::uint32_t next_endpoint);

  CHIP_ERROR Commit(const Values &values);
  CHIP_ERROR Commit(const Values &values, const Endpoints &endpoints, std::uint32_t next_endpoint);
  void Poison();

#ifdef WOTEX_MATTER_STORAGE_TESTING
  void Checkpoint(CommitStage stage) const;
  CommitStage crash_stage_{CommitStage::None};
#endif

  Identity identity_;
  int directory_fd_{-1};
  int lock_fd_{-1};
  Values values_;
  Endpoints endpoints_;
  std::uint32_t next_endpoint_{3};
  bool poisoned_{false};
};

} // namespace wotex::matter

#endif
