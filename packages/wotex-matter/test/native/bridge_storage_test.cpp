#include "wotex_matter/bridge_storage.hpp"

#include <nlohmann/json.hpp>

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

using namespace wotex::matter;
using Json = nlohmann::ordered_json;

const BridgeIdentity kIdentity{"bridge", std::string(64, 'a'), 0xFFF1, 0x8001};
constexpr auto kLight = BridgedDeviceType::OnOffLight;
constexpr auto kTemperature = BridgedDeviceType::TemperatureSensor;

void Require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}

void RequireError(CHIP_ERROR actual, CHIP_ERROR expected, const char *message) {
  Require(actual == expected, message);
}

class TemporaryDirectory final {
 public:
  TemporaryDirectory() {
    std::array<char, 64> pattern{};
    const std::string prefix = "/tmp/wotex-matter-bridge-store.XXXXXX";
    std::copy(prefix.begin(), prefix.end(), pattern.begin());
    const char *created = mkdtemp(pattern.data());
    Require(created != nullptr, "temporary directory creation failed");
    root_ = created;
  }
  ~TemporaryDirectory() { std::filesystem::remove_all(root_); }
  std::string Store(const std::string &name = "bridge") const { return root_ + "/" + name; }

 private:
  std::string root_;
};

std::unique_ptr<BridgeStorage> Create(const std::string &path,
                                      const BridgeIdentity &identity = kIdentity) {
  std::unique_ptr<BridgeStorage> store;
  RequireError(BridgeStorage::Open(path, StorageMode::CreateNew, identity, store), CHIP_NO_ERROR,
               "bridge creation failed");
  Require(store != nullptr, "bridge creation returned no owner");
  return store;
}

std::unique_ptr<BridgeStorage> Reopen(const std::string &path,
                                      const BridgeIdentity &identity = kIdentity) {
  std::unique_ptr<BridgeStorage> store;
  RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, identity, store), CHIP_NO_ERROR,
               "bridge reopen failed");
  return store;
}

BridgeEndpoint Allocate(BridgeStorage &store, const std::string &thing,
                        BridgedDeviceType type = kLight) {
  BridgeEndpoint endpoint;
  RequireError(store.Allocate(thing, type, endpoint), CHIP_NO_ERROR, "allocation failed");
  Require(endpoint.device_type == type, "allocated type changed");
  return endpoint;
}

void StoreByte(chip::PersistentStorageDelegate &store, std::uint8_t value) {
  RequireError(store.SyncSetKeyValue("sdk/fabric", &value, 1), CHIP_NO_ERROR,
               "SDK value write failed");
}

void RequireByte(chip::PersistentStorageDelegate &store, std::uint8_t expected) {
  std::uint8_t value = 0;
  std::uint16_t size = 1;
  RequireError(store.SyncGetKeyValue("sdk/fabric", &value, size), CHIP_NO_ERROR,
               "SDK value read failed");
  Require(size == 1 && value == expected, "SDK value was changed or lost");
}

Json ReadState(const std::string &path) {
  std::ifstream input(path + "/store.json");
  Require(input.good(), "fixture read failed");
  return Json::parse(input);
}

void ReplaceState(const std::string &path, const std::string &contents) {
  std::ofstream output(path + "/store.json", std::ios::trunc);
  output << contents;
  output.close();
  Require(output.good(), "fixture replacement failed");
}

void TestIdentityRoleLockAndPermissions() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  std::unique_ptr<BridgeStorage> refused;
  RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, kIdentity, refused),
               CHIP_ERROR_OPEN_FAILED, "missing store was created by reopen");
  RequireError(BridgeStorage::Open("relative", StorageMode::CreateNew, kIdentity, refused),
               CHIP_ERROR_INVALID_ARGUMENT, "relative bridge path was admitted");
  for (const BridgeIdentity &identity :
       std::vector<BridgeIdentity>{{"", kIdentity.model_sha256, 1, 1},
                                   {std::string(257, 'x'), kIdentity.model_sha256, 1, 1},
                                   {"bridge", "bad", 1, 1},
                                   {"bridge", std::string(64, 'A'), 1, 1},
                                   {"bridge", kIdentity.model_sha256, 0, 1},
                                   {"bridge", kIdentity.model_sha256, UINT16_MAX, 1},
                                   {"bridge", kIdentity.model_sha256, 1, 0}}) {
    RequireError(BridgeStorage::Open(path, StorageMode::CreateNew, identity, refused),
                 CHIP_ERROR_INVALID_ARGUMENT, "invalid bridge identity was admitted");
    Require(!std::filesystem::exists(path), "identity refusal performed filesystem creation");
  }
  // Scoped enums have a fixed underlying type; this representable cast models
  // malformed native caller input that Open must reject before filesystem I/O.
  // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
  RequireError(BridgeStorage::Open(path, static_cast<StorageMode>(99), kIdentity, refused),
               CHIP_ERROR_INVALID_ARGUMENT, "unknown storage mode was admitted");
  auto bridge = Create(path);
  Require(bridge->identity() == kIdentity, "bridge identity changed");
  RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, kIdentity, refused),
               CHIP_ERROR_OPEN_FAILED, "bridge lock allowed a second owner");
  RequireError(BridgeStorage::Open(path, StorageMode::CreateNew, kIdentity, refused),
               CHIP_ERROR_OPEN_FAILED, "bridge create reused an existing path");
  struct stat status{};
  Require(stat(path.c_str(), &status) == 0 && (status.st_mode & 0777) == 0700,
          "bridge directory is not private");
  for (const char *name : {"store.json", "store.lock"}) {
    Require(stat((path + "/" + name).c_str(), &status) == 0 && (status.st_mode & 0777) == 0600,
            "bridge file is not private");
  }
  StoreByte(*bridge, 8);
  bridge.reset();
  for (const BridgeIdentity &identity : std::vector<BridgeIdentity>{
           {"other", kIdentity.model_sha256, kIdentity.vendor_id, kIdentity.product_id},
           {"bridge", std::string(64, 'b'), kIdentity.vendor_id, kIdentity.product_id},
           {"bridge", kIdentity.model_sha256, 1, kIdentity.product_id},
           {"bridge", kIdentity.model_sha256, kIdentity.vendor_id, 1}}) {
    RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, identity, refused),
                 CHIP_ERROR_PERSISTED_STORAGE_FAILED, "mismatched bridge identity reopened");
  }
  constexpr ControllerIdentity controller_identity{1, 0x1234, 0xFFF1};
  std::unique_ptr<DurableStorage> controller;
  RequireError(DurableStorage::Open(path, StorageMode::OpenExisting, AuthorityMode::Stored,
                                    controller_identity, controller),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED, "controller opened a bridge store");
  RequireError(DurableStorage::Open(temporary.Store("controller"), StorageMode::CreateNew,
                                    AuthorityMode::GenerateRoot, controller_identity, controller),
               CHIP_NO_ERROR, "independent controller creation failed");
  StoreByte(*controller, 4);
  controller.reset();
  RequireError(BridgeStorage::Open(temporary.Store("controller"), StorageMode::OpenExisting,
                                   kIdentity, refused),
               CHIP_ERROR_PERSISTED_STORAGE_FAILED, "bridge opened a controller store");
  bridge = Reopen(path);
  RequireError(DurableStorage::Open(temporary.Store("controller"), StorageMode::OpenExisting,
                                    AuthorityMode::Stored, controller_identity, controller),
               CHIP_NO_ERROR, "independent controller reopen failed");
  RequireByte(*bridge, 8);
  RequireByte(*controller, 4);
  Require(!ReadState(path).contains("fabric_id") && !ReadState(path).contains("controller_node_id"),
          "bridge store fabricated a controller identity");
}

void TestStableIdentityTypesAndRetirement() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  const std::string opaque_thing{"\xFF\0\xFE", 3};
  const BridgeIdentity opaque_identity{opaque_thing, kIdentity.model_sha256, 0xFFF1, 0x8001};
  auto bridge = Create(path, opaque_identity);
  Require(Allocate(*bridge, opaque_thing).endpoint == 3, "first endpoint changed");
  Require(Allocate(*bridge, "temperature", kTemperature).endpoint == 4, "sensor endpoint changed");
  Require(Allocate(*bridge, opaque_thing).endpoint == 3, "idempotent allocation changed endpoint");
  BridgeEndpoint result{77, kTemperature};
  RequireError(bridge->Allocate(opaque_thing, kTemperature, result), CHIP_ERROR_INVALID_ARGUMENT,
               "existing identity silently changed Device Type");
  RequireError(bridge->Allocate("", kLight, result), CHIP_ERROR_INVALID_ARGUMENT,
               "empty identity admitted");
  RequireError(bridge->Allocate(std::string(257, 'a'), kLight, result), CHIP_ERROR_INVALID_ARGUMENT,
               "oversized identity admitted");
  // The uint16_t-backed enum can represent an unsupported Device Type. Exercise
  // its refusal without changing the allocation output or durable registry.
  // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
  RequireError(bridge->Allocate("unknown", static_cast<BridgedDeviceType>(99), result),
               CHIP_ERROR_INVALID_ARGUMENT, "unsupported type admitted");
  Require(result.endpoint == 77 && result.device_type == kTemperature,
          "refusal published an allocation");
  StoreByte(*bridge, 9);
  bridge.reset();
  bridge = Reopen(path, opaque_identity);
  Require(Allocate(*bridge, opaque_thing).endpoint == 3, "opaque identity changed at restart");
  RequireError(bridge->Remove(opaque_thing), CHIP_NO_ERROR, "removal failed");
  RequireError(bridge->Remove(opaque_thing), CHIP_ERROR_NOT_FOUND, "missing removal succeeded");
  RequireError(bridge->Lookup(opaque_thing, result), CHIP_ERROR_NOT_FOUND,
               "removed identity still live");
  bool retired = false;
  RequireError(bridge->Retired(3, retired), CHIP_NO_ERROR, "retirement lookup failed");
  Require(retired, "removed endpoint was not retired");
  RequireError(bridge->Retired(4, retired), CHIP_NO_ERROR, "active retirement lookup failed");
  Require(!retired, "active endpoint was retired");
  RequireError(bridge->Retired(5, retired), CHIP_NO_ERROR, "future retirement lookup failed");
  Require(!retired, "unallocated endpoint was retired");
  RequireError(bridge->Retired(2, retired), CHIP_ERROR_INVALID_ARGUMENT,
               "root endpoint was in registry");
  RequireError(bridge->Retired(UINT16_MAX, retired), CHIP_ERROR_INVALID_ARGUMENT,
               "invalid endpoint admitted");
  bridge.reset();
  bridge = Reopen(path, opaque_identity);
  Require(Allocate(*bridge, opaque_thing).endpoint == 5, "re-add reused a retired endpoint");
  Require(Allocate(*bridge, "other").endpoint == 6, "different identity reused an endpoint");
  RequireByte(*bridge, 9);
  std::map<std::string, BridgeEndpoint> endpoints;
  RequireError(bridge->Endpoints(endpoints), CHIP_NO_ERROR, "live endpoint list failed");
  Require(endpoints.size() == 3 && endpoints.at("temperature").device_type == kTemperature,
          "endpoint list omitted or changed the sensor");
  // The high-water mark represents every unallocated hole below it as retired;
  // tombstone storage stays bounded independently of the number of removals.
  for (unsigned int index = 0; index < 100; ++index) {
    const std::string thing(256, static_cast<char>(index));
    Require(Allocate(*bridge, thing).endpoint == index + 7, "retirement history reused an ID");
    RequireError(bridge->Remove(thing), CHIP_NO_ERROR, "retirement history removal failed");
  }
  bridge.reset();
  bridge = Reopen(path, opaque_identity);
  RequireError(bridge->Retired(106, retired), CHIP_NO_ERROR, "restart lost retirement history");
  Require(retired && std::filesystem::file_size(path + "/store.json") < 1024,
          "retirement history was lost or unbounded");
}

void TestLiveLimitAndExhaustion() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  auto bridge = Create(path);
  for (unsigned int index = 0; index < BridgeStorage::kMaximumLiveEndpoints; ++index) {
    Require(Allocate(*bridge, std::to_string(index)).endpoint == index + 3,
            "live allocation changed");
  }
  bridge.reset();
  bridge = Reopen(path);
  BridgeEndpoint result{77, kLight};
  RequireError(bridge->Allocate("overflow", kLight, result), CHIP_ERROR_ENDPOINT_POOL_FULL,
               "seventeenth live endpoint admitted");
  Require(Allocate(*bridge, "0").endpoint == 3, "existing endpoint unavailable at capacity");
  RequireError(bridge->Remove("0"), CHIP_NO_ERROR, "capacity removal failed");
  Require(Allocate(*bridge, "overflow").endpoint == 19,
          "capacity recovery reused a removed endpoint");
  bridge.reset();
  auto state = ReadState(path);
  state["endpoints"] = {{"next", 65534}, {"active", Json::array()}};
  ReplaceState(path, state.dump());
  bridge = Reopen(path);
  Require(Allocate(*bridge, "last").endpoint == 65534, "last legal endpoint rejected");
  bridge.reset();
  bridge = Reopen(path);
  RequireError(bridge->Allocate("exhausted", kLight, result), CHIP_ERROR_ENDPOINT_POOL_FULL,
               "exhausted endpoint counter wrapped");
  RequireError(bridge->Remove("last"), CHIP_NO_ERROR, "last endpoint removal failed");
  RequireError(bridge->Allocate("last", kLight, result), CHIP_ERROR_ENDPOINT_POOL_FULL,
               "exhaustion was erased by removal");
  bool retired = false;
  RequireError(bridge->Retired(65534, retired), CHIP_NO_ERROR, "last retirement lookup failed");
  Require(retired && result.endpoint == 77, "exhaustion published a reused endpoint");
}

void TestMalformedState() {
  TemporaryDirectory temporary;
  const std::string path = temporary.Store();
  auto bridge = Create(path);
  Allocate(*bridge, "light");
  Allocate(*bridge, "sensor", kTemperature);
  bridge.reset();
  const auto original = ReadState(path);
  std::vector<Json> corrupt;
  const auto changed = [&corrupt, &original](const auto &mutate) {
    auto document = original;
    mutate(document);
    corrupt.push_back(std::move(document));
  };
  changed([](auto &doc) { doc["schema"] = "wotex.matter.store"; });
  changed([](auto &doc) { doc["version"] = 2; });
  changed([](auto &doc) { doc["extra"] = true; });
  changed([](auto &doc) { doc.erase("endpoints"); });
  changed([](auto &doc) { doc["bridge_id"] = "A==="; });
  changed([](auto &doc) { doc["vendor_id"] = 65536; });
  changed([](auto &doc) { doc["product_id"] = 65536; });
  changed([](auto &doc) { doc["endpoints"]["next"] = 4; });
  changed([](auto &doc) { doc["endpoints"]["next"] = -1; });
  changed([](auto &doc) { doc["endpoints"]["next"] = 65536; });
  changed([](auto &doc) { doc["endpoints"]["next"] = 5.0; });
  changed([](auto &doc) { doc["endpoints"]["active"][0]["endpoint"] = 2; });
  changed([](auto &doc) { doc["endpoints"]["active"][0]["device_type"] = 999; });
  changed([](auto &doc) { doc["endpoints"]["active"][0]["thing"] = ""; });
  changed([](auto &doc) {
    doc["endpoints"]["active"][1]["thing"] = doc["endpoints"]["active"][0]["thing"];
  });
  changed([](auto &doc) { doc["endpoints"]["active"][1]["endpoint"] = 3; });
  changed([](auto &doc) {
    while (doc["endpoints"]["active"].size() < 17)
      doc["endpoints"]["active"].push_back(doc["endpoints"]["active"][0]);
  });
  changed([](auto &doc) { doc["values"]["key"] = "A==="; });
  for (const auto &document : corrupt) {
    ReplaceState(path, document.dump());
    std::unique_ptr<BridgeStorage> refused;
    RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, kIdentity, refused),
                 CHIP_ERROR_PERSISTED_STORAGE_FAILED, "corrupt bridge state reopened");
  }
  for (const auto &contents :
       std::vector<std::string>{"not JSON", "{\"schema\":0,\"schema\":1}",
                                std::string(1000, '[') + "0" + std::string(1000, ']')}) {
    ReplaceState(path, contents);
    std::unique_ptr<BridgeStorage> refused;
    RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, kIdentity, refused),
                 CHIP_ERROR_PERSISTED_STORAGE_FAILED, "malformed or deeply nested state reopened");
  }
  for (const char *field : {"\"version\":1", "\"endpoint\":3"}) {
    std::string duplicate = original.dump();
    const auto offset = duplicate.find(field);
    Require(offset != std::string::npos, "duplicate fixture field missing");
    duplicate.insert(offset, std::string(field) + ",");
    ReplaceState(path, duplicate);
    std::unique_ptr<BridgeStorage> refused;
    RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, kIdentity, refused),
                 CHIP_ERROR_PERSISTED_STORAGE_FAILED, "valid duplicate-member state reopened");
  }
  ReplaceState(path, original.dump());
  bridge = Reopen(path);
  Require(Allocate(*bridge, "light").endpoint == 3, "refusal mutated the valid endpoint state");
}

void TestWriteFailurePoisonsAllAccess() {
  for (unsigned int operation = 0; operation < 3; ++operation) {
    TemporaryDirectory temporary;
    const std::string path = temporary.Store();
    auto bridge = Create(path);
    Allocate(*bridge, "light");
    StoreByte(*bridge, 9);
    std::ofstream(path + "/store.tmp") << "unfinished";
    BridgeEndpoint result{77, kTemperature};
    const CHIP_ERROR error = operation == 0 ? bridge->Allocate("new", kLight, result)
        : operation == 1                    ? bridge->Remove("light")
                                            : bridge->SyncDeleteKeyValue("sdk/fabric");
    RequireError(error, CHIP_ERROR_PERSISTED_STORAGE_FAILED, "write failure was acknowledged");
    Require(bridge->poisoned() && result.endpoint == 77, "write failure published an allocation");
    RequireError(bridge->Lookup("light", result), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "poisoned store served an endpoint");
    RequireError(bridge->Allocate("light", kLight, result), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "poisoned store served an idempotent allocation");
    RequireError(bridge->Remove("light"), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "poisoned store accepted a removal");
    std::map<std::string, BridgeEndpoint> endpoints;
    RequireError(bridge->Endpoints(endpoints), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "poisoned store served endpoint enumeration");
    bool retired = false;
    RequireError(bridge->Retired(3, retired), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "poisoned store served retirement metadata");
    std::uint16_t size = 0;
    RequireError(bridge->SyncGetKeyValue("sdk/fabric", nullptr, size),
                 CHIP_ERROR_PERSISTED_STORAGE_FAILED, "poisoned store served SDK data");
    RequireError(bridge->SyncSetKeyValue("new", nullptr, 0), CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                 "poisoned store accepted SDK data");
  }
}

void TestCrashCutpoints() {
  for (bool remove : {false, true}) {
    for (const auto stage :
         {CommitStage::TemporaryOpened, CommitStage::TemporaryWritten, CommitStage::TemporarySynced,
          CommitStage::IntentSynced, CommitStage::StateRenamed, CommitStage::StateDirectorySynced,
          CommitStage::IntentRemoved, CommitStage::FinalDirectorySynced}) {
      TemporaryDirectory temporary;
      const std::string path = temporary.Store();
      auto bridge = Create(path);
      StoreByte(*bridge, 9);
      Allocate(*bridge, "original");
      bridge.reset();
      const pid_t child = fork();
      Require(child >= 0, "crash fork failed");
      if (child == 0) {
        auto owned = Reopen(path);
        owned->CrashAtForTesting(stage);
        if (remove) {
          if (owned->Remove("original") != CHIP_NO_ERROR) _exit(12);
        } else {
          Allocate(*owned, "new", kTemperature);
        }
        _exit(11);
      }
      int status = 0;
      Require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                  WEXITSTATUS(status) == 90 + static_cast<int>(stage),
              "crash cutpoint was not reached");
      const bool committed = stage == CommitStage::IntentRemoved ||
          stage == CommitStage::FinalDirectorySynced;
      std::unique_ptr<BridgeStorage> reopened;
      RequireError(BridgeStorage::Open(path, StorageMode::OpenExisting, kIdentity, reopened),
                   committed ? CHIP_NO_ERROR : CHIP_ERROR_PERSISTED_STORAGE_FAILED,
                   "crash boundary reopened ambiguous state or lost durable state");
      if (!committed) continue;
      RequireByte(*reopened, 9);
      if (remove) {
        bool retired = false;
        RequireError(reopened->Retired(3, retired), CHIP_NO_ERROR, "crash lost removal tombstone");
        Require(retired && Allocate(*reopened, "original").endpoint == 4,
                "crash reused removed endpoint");
      } else {
        Require(Allocate(*reopened, "original").endpoint == 3 &&
                    Allocate(*reopened, "new", kTemperature).endpoint == 4,
                "crash changed durable mapping");
      }
    }
  }
}

} // namespace

int main() {
  try {
    TestIdentityRoleLockAndPermissions();
    TestStableIdentityTypesAndRetirement();
    TestLiveLimitAndExhaustion();
    TestMalformedState();
    TestWriteFailurePoisonsAllAccess();
    TestCrashCutpoints();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
