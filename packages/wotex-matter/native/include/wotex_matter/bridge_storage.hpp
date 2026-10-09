#ifndef WOTEX_MATTER_BRIDGE_STORAGE_HPP
#define WOTEX_MATTER_BRIDGE_STORAGE_HPP

#include "wotex_matter/storage.hpp"

namespace wotex::matter {

// All calls belong to the native server's serialized owner. SDK key/value
// writes and endpoint changes use the same private, locked atomic store.
class BridgeStorage final : public chip::PersistentStorageDelegate {
 public:
  static constexpr std::size_t kMaximumLiveEndpoints = 16;
  static constexpr std::uint16_t kFirstEndpoint = 3;
  static constexpr std::uint16_t kMaximumEndpoint = 65534;

  static CHIP_ERROR Open(const std::string &path, StorageMode mode, const BridgeIdentity &identity,
                         std::unique_ptr<BridgeStorage> &storage);

  ~BridgeStorage() override;
  BridgeStorage(const BridgeStorage &) = delete;
  BridgeStorage &operator=(const BridgeStorage &) = delete;

  CHIP_ERROR SyncGetKeyValue(const char *key, void *buffer, std::uint16_t &size) override;
  CHIP_ERROR SyncSetKeyValue(const char *key, const void *value, std::uint16_t size) override;
  CHIP_ERROR SyncDeleteKeyValue(const char *key) override;

  CHIP_ERROR Allocate(const std::string &thing_id, BridgedDeviceType type,
                      BridgeEndpoint &endpoint);
  CHIP_ERROR Remove(const std::string &thing_id);
  CHIP_ERROR Lookup(const std::string &thing_id, BridgeEndpoint &endpoint) const;
  CHIP_ERROR Endpoints(std::map<std::string, BridgeEndpoint> &endpoints) const;
  CHIP_ERROR Retired(std::uint16_t endpoint, bool &retired) const;

  const BridgeIdentity &identity() const;
  CHIP_ERROR EnterProcessDirectory() const;
  bool poisoned() const;

#ifdef WOTEX_MATTER_STORAGE_TESTING
  void CrashAtForTesting(CommitStage stage);
#endif

 private:
  explicit BridgeStorage(std::unique_ptr<DurableStorage> storage);

  std::unique_ptr<DurableStorage> storage_;
};

} // namespace wotex::matter

#endif
