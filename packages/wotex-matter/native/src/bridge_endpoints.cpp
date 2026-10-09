#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_endpoint_model.hpp"

#include <app/AttributeValueEncoder.h>
#include <app/SafeAttributePersistenceProvider.h>
#include <app/clusters/bridged-device-basic-information-server/BridgedDeviceBasicInformationCluster.h>
#include <app/clusters/bridged-device-basic-information-server/BridgedDeviceBasicInformationDelegate.h>
#include <app/clusters/temperature-measurement-server/TemperatureMeasurementCluster.h>
#include <app/reporting/reporting.h>
#include <app/server-cluster/ServerClusterExtension.h>
#include <app/util/attribute-storage.h>
#include <crypto/CHIPCryptoPAL.h>
#include <credentials/GroupDataProvider.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <lib/support/DefaultStorageKeyAllocator.h>
#include <lib/support/TimerDelegate.h>
#include <platform/DefaultTimerDelegate.h>

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <cstring>
#include <set>

namespace wotex::matter {
namespace {

using chip::app::ClusterShutdownType;
using chip::app::CodegenDataModelProvider;
using chip::app::ConcreteClusterPath;
using chip::app::RegisteredServerCluster;
using chip::app::ServerClusterRegistration;
using chip::Protocols::InteractionModel::Status;
namespace Clusters = chip::app::Clusters;

SdkBridgeEndpointBinding *active_endpoints = nullptr;

bool ValidConfiguration(const BridgeDeviceConfiguration &configuration) {
  if (configuration.thing_id.empty() || configuration.thing_id.size() > 256 ||
      configuration.node_label.size() > 32) {
    return false;
  }
  try {
    // JSON's strict string encoder checks UTF-8 without accepting a replacement
    // character or changing the caller's bytes. Labels have a 32-byte bound.
    (void)nlohmann::json(configuration.node_label).dump();
  } catch (const nlohmann::json::exception &) {
    return false;
  }
  if (configuration.device_type == BridgedDeviceType::OnOffLight) {
    return !configuration.minimum_temperature && !configuration.maximum_temperature;
  }
  if (configuration.device_type != BridgedDeviceType::TemperatureSensor) return false;
  const auto minimum = configuration.minimum_temperature;
  const auto maximum = configuration.maximum_temperature;
  return (!minimum || (*minimum >= -27315 && *minimum <= 32766)) &&
      (!maximum || *maximum >= -27314) && (!minimum || !maximum || *maximum > *minimum);
}

bool SameConfiguration(const BridgeDeviceConfiguration &left,
                       const BridgeDeviceConfiguration &right) {
  return left.thing_id == right.thing_id && left.device_type == right.device_type &&
      left.node_label == right.node_label &&
      left.minimum_temperature == right.minimum_temperature &&
      left.maximum_temperature == right.maximum_temperature;
}

CHIP_ERROR UniqueId(const BridgeIdentity &bridge, const std::string &thing, std::string &unique) {
  const std::string domain = "wotex.bridge.child@1";
  std::vector<std::uint8_t> bytes(domain.begin(), domain.end());
  for (const std::string *value : {&bridge.bridge_id, &thing}) {
    bytes.push_back(static_cast<std::uint8_t>(value->size() >> 8U));
    bytes.push_back(static_cast<std::uint8_t>(value->size() & 0xFFU));
    bytes.insert(bytes.end(), value->begin(), value->end());
  }
  std::array<std::uint8_t, chip::Crypto::kSHA256_Hash_Length> digest{};
  const CHIP_ERROR error = chip::Crypto::Hash_SHA256(bytes.data(), bytes.size(), digest.data());
  if (error != CHIP_NO_ERROR) return error;
  constexpr char hex[] = "0123456789abcdef";
  unique.clear();
  unique.reserve(32);
  for (std::size_t index = 0; index < 16; ++index) {
    unique.push_back(hex[digest[index] >> 4U]);
    unique.push_back(hex[digest[index] & 0x0FU]);
  }
  return CHIP_NO_ERROR;
}

bool Absent(CHIP_ERROR error) {
  return error == CHIP_ERROR_NOT_FOUND || error == CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND;
}

class TemperatureProfile final : public chip::app::ServerClusterExtension {
 public:
  TemperatureProfile(const ConcreteClusterPath &path, chip::app::ServerClusterInterface &underlying)
      : ServerClusterExtension(path, underlying) {}

  chip::app::DataModel::ActionReturnStatus ReadAttribute(
      const chip::app::DataModel::ReadAttributeRequest &request,
      chip::app::AttributeValueEncoder &encoder) override {
    // The pinned SDK's modern server advertises revision 4. The selected
    // revision 6 removes measured-value persistence and fixes capability
    // bounds for the registered lifetime. This owner never changes those
    // bounds and supplies only volatile, explicitly approved measurements.
    if (request.path.mAttributeId == 0xFFFD) return encoder.Encode<std::uint16_t>(6);
    return ServerClusterExtension::ReadAttribute(request, encoder);
  }
};

struct Child final {
  Child(BridgeDeviceConfiguration value, BridgeEndpoint record, std::string unique,
        Clusters::BridgedDeviceBasicInformationDelegate &delegate,
        chip::app::DefaultTimerDelegate &timer)
      : configuration(std::move(value)), endpoint(record),
        information(record.endpoint, {.reachable = false, .nodeLabel = configuration.node_label},
                    {.uniqueId = std::move(unique)},
                    {.delegate = delegate, .timerDelegate = timer}),
        registration(information) {}

  bool IsLight() const { return endpoint.device_type == BridgedDeviceType::OnOffLight; }

  BridgeDeviceConfiguration configuration;
  BridgeEndpoint endpoint;
  std::array<chip::DataVersion, 5> versions{};
  std::optional<bool> on_off;
  Clusters::BridgedDeviceBasicInformationCluster information;
  ServerClusterRegistration registration;
  std::unique_ptr<ServerClusterRegistration> restored_temperature;
  std::unique_ptr<RegisteredServerCluster<TemperatureProfile>> temperature;
};

template <typename Value>
Status Encode(Value value, std::uint8_t *buffer, std::uint16_t capacity) {
  if (capacity < sizeof(Value)) return Status::ResourceExhausted;
  std::memcpy(buffer, &value, sizeof(Value));
  return Status::Success;
}

} // namespace

class SdkBridgeEndpointBinding::Impl final {
 public:
  Impl(SdkBridgeEndpointBinding &owner, SdkBridgeServerBinding &server)
      : owner_(owner), server_(server), storage_(server.bridge_storage()) {}

  ~Impl() {
    if (initialized_) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  }

  void Healthy() const {
    if (storage_.poisoned()) std::_Exit(SdkBridgeServerBinding::kStoreFailureExit);
  }

  CHIP_ERROR Init(const std::vector<BridgeDeviceConfiguration> &configurations) {
    Healthy();
    if (used_ || active_endpoints != nullptr || !server_.initialized()) {
      return CHIP_ERROR_INCORRECT_STATE;
    }
    if (configurations.size() > children_.size()) return CHIP_ERROR_INVALID_ARGUMENT;
    std::map<std::string, BridgeEndpoint> persisted;
    const CHIP_ERROR error = storage_.Endpoints(persisted);
    if (error != CHIP_NO_ERROR) return error;
    if (persisted.size() != configurations.size()) return CHIP_ERROR_INVALID_ARGUMENT;
    std::set<std::string> things;
    std::set<std::string> unique_ids;
    std::size_t slot = 0;
    for (const auto &configuration : configurations) {
      const auto found = persisted.find(configuration.thing_id);
      if (!ValidConfiguration(configuration) || found == persisted.end() ||
          found->second.device_type != configuration.device_type ||
          !things.insert(configuration.thing_id).second) {
        ClearPrepared();
        return CHIP_ERROR_INVALID_ARGUMENT;
      }
      std::string unique;
      const CHIP_ERROR unique_error = UniqueId(storage_.identity(), configuration.thing_id, unique);
      if (unique_error != CHIP_NO_ERROR || !unique_ids.insert(unique).second) {
        ClearPrepared();
        return unique_error != CHIP_NO_ERROR ? unique_error : CHIP_ERROR_DUPLICATE_KEY_ID;
      }
      children_[slot++] = std::make_unique<Child>(configuration, found->second, std::move(unique),
                                                  delegate_, timer_);
    }
    used_ = true;
    initialized_ = true;
    active_endpoints = &owner_;
    for (std::size_t index = 0; index < slot; ++index) Install(index);
    return CHIP_NO_ERROR;
  }

  CHIP_ERROR Add(const BridgeDeviceConfiguration &configuration, BridgeEndpoint &endpoint) {
    Healthy();
    if (!initialized_) return CHIP_ERROR_INCORRECT_STATE;
    if (!ValidConfiguration(configuration)) return CHIP_ERROR_INVALID_ARGUMENT;
    const std::size_t existing = Find(configuration.thing_id);
    if (existing < children_.size()) {
      if (!SameConfiguration(configuration, children_[existing]->configuration)) {
        return CHIP_ERROR_INVALID_ARGUMENT;
      }
      endpoint = children_[existing]->endpoint;
      return CHIP_NO_ERROR;
    }
    std::size_t slot = 0;
    while (slot < children_.size() && children_[slot]) ++slot;
    if (slot == children_.size()) return CHIP_ERROR_ENDPOINT_POOL_FULL;
    std::string unique;
    const CHIP_ERROR unique_error = UniqueId(storage_.identity(), configuration.thing_id, unique);
    if (unique_error != CHIP_NO_ERROR) return unique_error;
    for (const auto &child : children_) {
      if (child && child->information.GetUniqueId() == unique) return CHIP_ERROR_DUPLICATE_KEY_ID;
    }
    BridgeEndpoint record;
    const CHIP_ERROR error = server_.Allocate(configuration.thing_id, configuration.device_type,
                                              record);
    if (error != CHIP_NO_ERROR) return error;
    children_[slot] = std::make_unique<Child>(configuration, record, std::move(unique), delegate_,
                                              timer_);
    Install(slot);
    endpoint = record;
    return CHIP_NO_ERROR;
  }

  CHIP_ERROR Remove(const std::string &thing) {
    Healthy();
    if (!initialized_) return CHIP_ERROR_INCORRECT_STATE;
    const std::size_t slot = Find(thing);
    if (slot == children_.size()) return CHIP_ERROR_NOT_FOUND;
    const CHIP_ERROR error = server_.Remove(thing);
    if (error != CHIP_NO_ERROR) return error;
    const auto endpoint = children_[slot]->endpoint.endpoint;
    auto *groups = chip::Credentials::GetGroupDataProvider();
    if (groups == nullptr) Failed();
    // Group custody can contain records left by a removed fabric. Prune this
    // endpoint from the complete bounded FabricIndex domain, including those
    // records, rather than relying on currently active FabricTable entries.
    for (unsigned fabric = chip::kMinValidFabricIndex; fabric <= chip::kMaxValidFabricIndex;
         ++fabric) {
      const CHIP_ERROR removed = groups->RemoveEndpoint(static_cast<chip::FabricIndex>(fabric),
                                                        endpoint);
      if (removed != CHIP_NO_ERROR && !Absent(removed)) Failed();
    }
    Clear(slot, MatterClusterShutdownType::kPermanentRemove);
    DeleteAttribute(endpoint, 0x0039, 5);
    for (chip::AttributeId attribute : {0U, 0x4000U, 0x4001U, 0x4002U, 0x4003U}) {
      DeleteAttribute(endpoint, 0x0006, attribute);
    }
    Healthy();
    return CHIP_NO_ERROR;
  }

  CHIP_ERROR Observe(const std::string &thing, std::uint16_t endpoint,
                     const BridgeObservation &observation) {
    Healthy();
    if (!initialized_) return CHIP_ERROR_INCORRECT_STATE;
    const std::size_t slot = Find(thing);
    if (slot == children_.size() || children_[slot]->endpoint.endpoint != endpoint) {
      return CHIP_ERROR_NOT_FOUND;
    }
    auto &child = *children_[slot];
    if (child.IsLight()) {
      if (observation.temperature) return CHIP_ERROR_INVALID_ARGUMENT;
      if (child.on_off != observation.on_off) {
        child.on_off = observation.on_off;
        MatterReportingAttributeChangeCallback(endpoint, 0x0006, 0);
      }
    } else {
      if (observation.on_off || (observation.temperature && *observation.temperature < -27315)) {
        return CHIP_ERROR_INVALID_ARGUMENT;
      }
      auto &sensor = *static_cast<Clusters::TemperatureMeasurementCluster *>(
          child.restored_temperature->serverClusterInterface);
      const auto measured = observation.temperature
          ? chip::app::DataModel::MakeNullable(*observation.temperature)
          : chip::app::DataModel::Nullable<std::int16_t>();
      const CHIP_ERROR error = sensor.SetMeasuredValue(measured);
      if (error != CHIP_NO_ERROR) return error;
    }
    child.information.SetReachable(observation.reachable);
    Healthy();
    return CHIP_NO_ERROR;
  }

  void Finish() {
    if (initialized_) {
      for (std::size_t slot = 0; slot < children_.size(); ++slot) {
        if (children_[slot]) Clear(slot, MatterClusterShutdownType::kClusterShutdown);
      }
      active_endpoints = nullptr;
      initialized_ = false;
    }
    ClearPrepared();
    used_ = true;
  }

  Status Read(chip::EndpointId endpoint, chip::ClusterId cluster,
              const EmberAfAttributeMetadata &attribute, std::uint8_t *buffer,
              std::uint16_t capacity) {
    Healthy();
    const Child *child = nullptr;
    for (const auto &value : children_) {
      if (value && value->endpoint.endpoint == endpoint) child = value.get();
    }
    if (child == nullptr) return Status::UnsupportedEndpoint;
    const auto &model = BridgeEndpointModel(child->configuration.device_type);
    bool admitted = false;
    for (std::uint8_t index = 0; index < model.clusterCount; ++index) {
      if (model.cluster[index].clusterId == cluster) admitted = true;
    }
    if (!admitted) return Status::UnsupportedCluster;
    if (attribute.attributeId == 0xFFFC) {
      return Encode<std::uint32_t>(cluster == 0x0006 ? 1 : 0, buffer, capacity);
    }
    if (attribute.attributeId == 0xFFFD) {
      const std::uint16_t revision = cluster == 0x001D ? 3
          : cluster == 0x0004                          ? 4
          : cluster == 0x0062                          ? 1
                                                       : 6;
      return Encode(revision, buffer, capacity);
    }
    if (cluster == 0x0062 && attribute.attributeId == 1) {
      return Encode<std::uint16_t>(16, buffer, capacity);
    }
    if (cluster == 0x0402 && (attribute.attributeId == 1 || attribute.attributeId == 2)) {
      const auto bound = attribute.attributeId == 1 ? child->configuration.minimum_temperature
                                                    : child->configuration.maximum_temperature;
      return Encode<std::int16_t>(bound.value_or(INT16_MIN), buffer, capacity);
    }
    if (cluster == 0x0006 && attribute.attributeId == 0) {
      return child->on_off ? Encode<std::uint8_t>(*child->on_off ? 1 : 0, buffer, capacity)
                           : Status::Failure;
    }
    if (cluster == 0x0006 && attribute.attributeId == 0x4000) {
      return Encode<std::uint8_t>(1, buffer, capacity);
    }
    if (cluster == 0x0006 && (attribute.attributeId == 0x4001 || attribute.attributeId == 0x4002)) {
      return Encode<std::uint16_t>(0, buffer, capacity);
    }
    if (cluster == 0x0006 && attribute.attributeId == 0x4003) {
      return Encode<std::uint8_t>(0xFF, buffer, capacity);
    }
    return Status::UnsupportedAttribute;
  }

  bool initialized_{false};

 private:
  [[noreturn]] void Failed() const {
    Healthy();
    std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  }

  void Install(std::size_t slot) {
    auto &child = *children_[slot];
    const auto &model = BridgeEndpointModel(child.configuration.device_type);
    if (emberAfSetDynamicEndpoint(static_cast<std::uint16_t>(slot), child.endpoint.endpoint, &model,
                                  chip::Span<chip::DataVersion>(child.versions),
                                  BridgeEndpointDeviceTypes(child.configuration.device_type),
                                  1) != CHIP_NO_ERROR) {
      Failed();
    }
    auto &registry = CodegenDataModelProvider::Instance().Registry();
    if (registry.Register(child.registration) != CHIP_NO_ERROR) Failed();
    if (!child.IsLight()) {
      const ConcreteClusterPath path(child.endpoint.endpoint, 0x0402);
      auto *underlying = registry.Get(path);
      if (underlying == nullptr || registry.Unregister(underlying) != CHIP_NO_ERROR) Failed();
      child.restored_temperature = std::make_unique<ServerClusterRegistration>(*underlying);
      child.temperature = std::make_unique<RegisteredServerCluster<TemperatureProfile>>(
          path, *underlying);
      if (registry.Register(child.temperature->Registration()) != CHIP_NO_ERROR) Failed();
    }
    Healthy();
  }

  void Clear(std::size_t slot, MatterClusterShutdownType shutdown) {
    auto &child = *children_[slot];
    auto &registry = CodegenDataModelProvider::Instance().Registry();
    const auto cluster_shutdown = shutdown == MatterClusterShutdownType::kPermanentRemove
        ? ClusterShutdownType::kPermanentRemove
        : ClusterShutdownType::kClusterShutdown;
    if (registry.Unregister(&child.information, cluster_shutdown) != CHIP_NO_ERROR) Failed();
    if (child.temperature) {
      if (registry.Unregister(&child.temperature->Cluster(), cluster_shutdown) != CHIP_NO_ERROR ||
          registry.Register(*child.restored_temperature) != CHIP_NO_ERROR) {
        Failed();
      }
    }
    if (emberAfClearDynamicEndpoint(static_cast<std::uint16_t>(slot), shutdown) !=
        child.endpoint.endpoint) {
      Failed();
    }
    auto remaining = registry.ClustersOnEndpoint(child.endpoint.endpoint);
    if (remaining.begin() != remaining.end()) Failed();
    children_[slot].reset();
    Healthy();
  }

  void DeleteAttribute(chip::EndpointId endpoint, chip::ClusterId cluster,
                       chip::AttributeId attribute) {
    const auto key = chip::DefaultStorageKeyAllocator::AttributeValue(endpoint, cluster, attribute);
    const CHIP_ERROR removed = server_.storage_delegate().SyncDeleteKeyValue(key.KeyName());
    if (removed != CHIP_NO_ERROR && !Absent(removed)) Failed();
    const CHIP_ERROR safe_removed = chip::app::GetSafeAttributePersistenceProvider()
                                        ->SafeDeleteValue({endpoint, cluster, attribute});
    if (safe_removed != CHIP_NO_ERROR && !Absent(safe_removed)) Failed();
  }

  std::size_t Find(const std::string &thing) const {
    for (std::size_t slot = 0; slot < children_.size(); ++slot) {
      if (children_[slot] && children_[slot]->configuration.thing_id == thing) return slot;
    }
    return children_.size();
  }

  void ClearPrepared() {
    for (auto &child : children_) child.reset();
  }

  SdkBridgeEndpointBinding &owner_;
  SdkBridgeServerBinding &server_;
  BridgeStorage &storage_;
  Clusters::BridgedDeviceBasicInformationDelegate delegate_;
  chip::app::DefaultTimerDelegate timer_;
  std::array<std::unique_ptr<Child>, BridgeStorage::kMaximumLiveEndpoints> children_;
  bool used_{false};
};

SdkBridgeEndpointBinding::SdkBridgeEndpointBinding(SdkBridgeServerBinding &server)
    : impl_(std::make_unique<Impl>(*this, server)) {}

SdkBridgeEndpointBinding::~SdkBridgeEndpointBinding() = default;

CHIP_ERROR SdkBridgeEndpointBinding::Init(
    const std::vector<BridgeDeviceConfiguration> &configurations) {
  return impl_->Init(configurations);
}

CHIP_ERROR SdkBridgeEndpointBinding::Add(const BridgeDeviceConfiguration &configuration,
                                         BridgeEndpoint &endpoint) {
  return impl_->Add(configuration, endpoint);
}

CHIP_ERROR SdkBridgeEndpointBinding::Remove(const std::string &thing_id) {
  return impl_->Remove(thing_id);
}

CHIP_ERROR SdkBridgeEndpointBinding::Observe(const std::string &thing_id, std::uint16_t endpoint,
                                             const BridgeObservation &observation) {
  return impl_->Observe(thing_id, endpoint, observation);
}

void SdkBridgeEndpointBinding::Finish() { impl_->Finish(); }

bool SdkBridgeEndpointBinding::initialized() const { return impl_->initialized_; }

Status SdkBridgeEndpointBinding::ReadExternal(chip::EndpointId endpoint, chip::ClusterId cluster,
                                              const EmberAfAttributeMetadata *attribute,
                                              std::uint8_t *buffer, std::uint16_t capacity) {
  if (active_endpoints == nullptr || attribute == nullptr || buffer == nullptr) {
    return Status::UnsupportedAttribute;
  }
  return active_endpoints->impl_->Read(endpoint, cluster, *attribute, buffer, capacity);
}

} // namespace wotex::matter

chip::Protocols::InteractionModel::Status emberAfExternalAttributeReadCallback(
    chip::EndpointId endpoint, chip::ClusterId cluster, const EmberAfAttributeMetadata *attribute,
    std::uint8_t *buffer, std::uint16_t capacity) {
  return wotex::matter::SdkBridgeEndpointBinding::ReadExternal(endpoint, cluster, attribute, buffer,
                                                               capacity);
}
