#include "wotex_matter/bridge_storage.hpp"

namespace wotex::matter {
namespace {

bool ValidThing(const std::string &thing) { return !thing.empty() && thing.size() <= 256; }

bool ValidType(BridgedDeviceType type) {
  return type == BridgedDeviceType::OnOffLight || type == BridgedDeviceType::TemperatureSensor;
}

} // namespace

CHIP_ERROR BridgeStorage::Open(const std::string &path, StorageMode mode,
                               const BridgeIdentity &identity,
                               std::unique_ptr<BridgeStorage> &storage) {
  storage.reset();
  std::unique_ptr<DurableStorage> delegate;
  const CHIP_ERROR error = DurableStorage::OpenStore(path, mode, identity, delegate);
  if (error != CHIP_NO_ERROR) return error;
  storage = std::unique_ptr<BridgeStorage>(new BridgeStorage(std::move(delegate)));
  return CHIP_NO_ERROR;
}

BridgeStorage::BridgeStorage(std::unique_ptr<DurableStorage> storage)
    : storage_(std::move(storage)) {}

BridgeStorage::~BridgeStorage() = default;

CHIP_ERROR BridgeStorage::SyncGetKeyValue(const char *key, void *buffer, std::uint16_t &size) {
  return storage_->SyncGetKeyValue(key, buffer, size);
}

CHIP_ERROR BridgeStorage::SyncSetKeyValue(const char *key, const void *value, std::uint16_t size) {
  return storage_->SyncSetKeyValue(key, value, size);
}

CHIP_ERROR BridgeStorage::SyncDeleteKeyValue(const char *key) {
  return storage_->SyncDeleteKeyValue(key);
}

CHIP_ERROR BridgeStorage::Allocate(const std::string &thing_id, BridgedDeviceType type,
                                   BridgeEndpoint &endpoint) {
  if (poisoned()) return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  if (!ValidThing(thing_id) || !ValidType(type)) return CHIP_ERROR_INVALID_ARGUMENT;
  const auto found = storage_->endpoints_.find(thing_id);
  if (found != storage_->endpoints_.end()) {
    if (found->second.device_type != type) return CHIP_ERROR_INVALID_ARGUMENT;
    endpoint = found->second;
    return CHIP_NO_ERROR;
  }
  if (storage_->endpoints_.size() >= kMaximumLiveEndpoints ||
      storage_->next_endpoint_ > kMaximumEndpoint) {
    return CHIP_ERROR_ENDPOINT_POOL_FULL;
  }

  const BridgeEndpoint allocated{static_cast<std::uint16_t>(storage_->next_endpoint_), type};
  auto next = storage_->endpoints_;
  next.emplace(thing_id, allocated);
  const auto next_endpoint = storage_->next_endpoint_ + 1;
  const CHIP_ERROR error = storage_->Commit(storage_->values_, next, next_endpoint);
  if (error != CHIP_NO_ERROR) return error;
  storage_->endpoints_ = std::move(next);
  storage_->next_endpoint_ = next_endpoint;
  endpoint = allocated;
  return CHIP_NO_ERROR;
}

CHIP_ERROR BridgeStorage::Remove(const std::string &thing_id) {
  if (poisoned()) return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  if (!ValidThing(thing_id)) return CHIP_ERROR_INVALID_ARGUMENT;
  auto next = storage_->endpoints_;
  if (next.erase(thing_id) == 0) return CHIP_ERROR_NOT_FOUND;
  const CHIP_ERROR error = storage_->Commit(storage_->values_, next, storage_->next_endpoint_);
  if (error == CHIP_NO_ERROR) storage_->endpoints_ = std::move(next);
  return error;
}

CHIP_ERROR BridgeStorage::Lookup(const std::string &thing_id, BridgeEndpoint &endpoint) const {
  if (poisoned()) return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  if (!ValidThing(thing_id)) return CHIP_ERROR_INVALID_ARGUMENT;
  const auto found = storage_->endpoints_.find(thing_id);
  if (found == storage_->endpoints_.end()) return CHIP_ERROR_NOT_FOUND;
  endpoint = found->second;
  return CHIP_NO_ERROR;
}

CHIP_ERROR BridgeStorage::Endpoints(std::map<std::string, BridgeEndpoint> &endpoints) const {
  if (poisoned()) return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  endpoints = storage_->endpoints_;
  return CHIP_NO_ERROR;
}

CHIP_ERROR BridgeStorage::Retired(std::uint16_t endpoint, bool &retired) const {
  if (poisoned()) return CHIP_ERROR_PERSISTED_STORAGE_FAILED;
  if (endpoint < kFirstEndpoint || endpoint > kMaximumEndpoint) return CHIP_ERROR_INVALID_ARGUMENT;
  retired = endpoint < storage_->next_endpoint_;
  for (const auto &[thing, active] : storage_->endpoints_) {
    if (active.endpoint == endpoint) retired = false;
  }
  return CHIP_NO_ERROR;
}

const BridgeIdentity &BridgeStorage::identity() const {
  return std::get<BridgeIdentity>(storage_->identity_);
}

CHIP_ERROR BridgeStorage::EnterProcessDirectory() const {
  return storage_->EnterProcessDirectory();
}

bool BridgeStorage::poisoned() const { return storage_->poisoned(); }

#ifdef WOTEX_MATTER_STORAGE_TESTING
void BridgeStorage::CrashAtForTesting(CommitStage stage) { storage_->CrashAtForTesting(stage); }
#endif

} // namespace wotex::matter
