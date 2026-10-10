#ifndef WOTEX_MATTER_BRIDGE_GUARD_HPP
#define WOTEX_MATTER_BRIDGE_GUARD_HPP

#include "wotex_matter/bridge_requests.hpp"

#include <app/data-model-provider/Provider.h>
#include <access/AccessControl.h>
#include <credentials/FabricTable.h>

#include <limits>
#include <algorithm>
#include <new>

namespace wotex::matter {

// One explicit fabric-table attachment under the SDK stack lock. The table
// outlives this owner. Drain command contexts, then Finish before SDK shutdown.
// Deletion, update and commit retire prior epochs; an exact NOC digest also
// detects rollback, which need not produce a delegate notification. These
// mechanics do not authenticate an externally supplied principal.
class SdkBridgeFabricScopes final : private chip::FabricTable::Delegate {
 public:
  explicit SdkBridgeFabricScopes(chip::FabricTable &table);
  ~SdkBridgeFabricScopes();
  SdkBridgeFabricScopes(const SdkBridgeFabricScopes &) = delete;
  SdkBridgeFabricScopes &operator=(const SdkBridgeFabricScopes &) = delete;
  CHIP_ERROR Init();
  void Finish();
  CHIP_ERROR Capture(const chip::Access::SubjectDescriptor &principal,
                     BridgeFabricScope &scope) const;
  CHIP_ERROR Check(const BridgeFabricScope &scope) const;
  CHIP_ERROR Validate(const BridgeFabricScope &scope, const chip::Access::RequestPath &path,
                      chip::Access::Privilege privilege) const;

 private:
  void Bump(chip::FabricIndex index);
  void FabricWillBeRemoved(const chip::FabricTable &, chip::FabricIndex index) override;
  void OnFabricRemoved(const chip::FabricTable &, chip::FabricIndex index) override;
  void OnFabricUpdated(const chip::FabricTable &, chip::FabricIndex index) override;
  void OnFabricCommitted(const chip::FabricTable &, chip::FabricIndex index) override;
  chip::FabricTable &table_;
  std::array<std::uint64_t, std::numeric_limits<chip::FabricIndex>::max() + 1> epochs_{};
  std::uint64_t last_{0};
  bool used_{false};
  bool active_{false};
};

// Borrowed current provider and fabric scope owner, both outliving the retained
// contexts. Preserves metadata errors and checks the actual current SDK ACL.
// A changed command contract, missing child or retired fabric denies rendering.
// No original handler session/exchange or consumer policy is consulted.
class SdkBridgeInvokeGuard final : public BridgeInvokeGuard {
 public:
  SdkBridgeInvokeGuard(SdkBridgeFabricScopes &fabrics, chip::app::DataModel::Provider &provider);
  CHIP_ERROR Capture(const BridgeRequestMetadata &request,
                     BridgeInvokeScope &scope) noexcept override;
  CHIP_ERROR Validate(const BridgeInvokeScope &scope) noexcept override;

 private:
  CHIP_ERROR Command(const BridgeRequestMetadata &request,
                     chip::app::DataModel::AcceptedCommandEntry &command);
  static CHIP_ERROR Access(const BridgeRequestMetadata &request,
                           const chip::app::DataModel::AcceptedCommandEntry &command);
  SdkBridgeFabricScopes &fabrics_;
  chip::app::DataModel::Provider &provider_;
};


// Internal synchronous attribute guard. The SDK callback supplies its owned
// principal; these checks do not authenticate externally supplied values or
// grant consumer policy. Calls hold the SDK stack lock and never wait. The
// borrowed provider and fabric attachment outlive every captured scope. Capture
// precedes payload/custody admission; Validate precedes completed rendering or
// mutation after a consumer wait. Failure preserves the previous captured scope.
// Attribute contracts retain both privileges and all five SDK quality flags.
struct BridgeAttributeContract {
  std::optional<chip::Access::Privilege> read;
  std::optional<chip::Access::Privilege> write;
  std::array<bool, 5> flags{};
  bool operator==(const BridgeAttributeContract &other) const {
    return read == other.read && write == other.write && flags == other.flags;
  }
};
struct BridgeAttributeScope {
  BridgeRequestMetadata request;
  BridgeFabricScope fabric;
  BridgeAttributeContract attribute;
};

class SdkBridgeAttributeGuard final {
 public:
  SdkBridgeAttributeGuard(SdkBridgeFabricScopes &fabrics, chip::app::DataModel::Provider &provider)
      : fabrics_(fabrics), provider_(provider) {}

  CHIP_ERROR Capture(const BridgeRequestMetadata &request, BridgeAttributeScope &scope) noexcept {
    try {
      BridgeAttributeScope copied;
      copied.request = request;
      ReturnErrorOnFailure(fabrics_.Capture(request.principal, copied.fabric));
      ReturnErrorOnFailure(Attribute(request, copied.attribute));
      ReturnErrorOnFailure(Access(request, copied.attribute, copied.fabric));
      scope = copied;
      return CHIP_NO_ERROR;
    } catch (const std::bad_alloc &) {
      return CHIP_ERROR_NO_MEMORY;
    }
  }

  CHIP_ERROR Validate(const BridgeAttributeScope &scope) noexcept {
    try {
      const auto &left = scope.request.principal;
      const auto &right = scope.fabric.principal;
      if (left.fabricIndex != right.fabricIndex || left.authMode != right.authMode ||
          left.subject != right.subject || left.cats.values != right.cats.values ||
          left.isCommissioning != right.isCommissioning)
        return CHIP_ERROR_INVALID_ARGUMENT;
      ReturnErrorOnFailure(fabrics_.Check(scope.fabric));
      BridgeAttributeContract current;
      ReturnErrorOnFailure(Attribute(scope.request, current));
      if (!(current == scope.attribute)) return CHIP_ERROR_ACCESS_DENIED;
      return Access(scope.request, current, scope.fabric);
    } catch (const std::bad_alloc &) {
      return CHIP_ERROR_NO_MEMORY;
    }
  }

 private:
  CHIP_ERROR Attribute(const BridgeRequestMetadata &request, BridgeAttributeContract &result) {
    using namespace chip::app::DataModel;
    using AttributeOperation = BridgeRequestMetadata::Operation;
    if ((request.operation != AttributeOperation::Read &&
         request.operation != AttributeOperation::Write) ||
        request.endpoint < 3 || request.endpoint == chip::kInvalidEndpointId ||
        request.cluster == chip::kInvalidClusterId || !chip::IsValidAttributeId(request.member))
      return CHIP_ERROR_INVALID_ARGUMENT;
    chip::ReadOnlyBufferBuilder<EndpointEntry> endpoint_builder;
    ReturnErrorOnFailure(provider_.Endpoints(endpoint_builder));
    const auto endpoints = endpoint_builder.TakeBuffer();
    if (std::none_of(endpoints.begin(), endpoints.end(),
                     [&](const auto &entry) { return entry.id == request.endpoint; }))
      return CHIP_IM_GLOBAL_STATUS(UnsupportedEndpoint);
    chip::ReadOnlyBufferBuilder<ServerClusterEntry> cluster_builder;
    ReturnErrorOnFailure(provider_.ServerClusters(request.endpoint, cluster_builder));
    const auto clusters = cluster_builder.TakeBuffer();
    const auto cluster = std::find_if(clusters.begin(), clusters.end(), [&](const auto &entry) {
      return entry.clusterId == request.cluster;
    });
    if (cluster == clusters.end()) return CHIP_IM_GLOBAL_STATUS(UnsupportedCluster);
    chip::ReadOnlyBufferBuilder<AttributeEntry> attribute_builder;
    ReturnErrorOnFailure(provider_.Attributes(
        chip::app::ConcreteClusterPath(request.endpoint, request.cluster), attribute_builder));
    const auto attributes = attribute_builder.TakeBuffer();
    const auto found = std::find_if(attributes.begin(), attributes.end(), [&](const auto &entry) {
      return entry.attributeId == request.member;
    });
    if (found == attributes.end()) return CHIP_IM_GLOBAL_STATUS(UnsupportedAttribute);
    const auto privilege = request.operation == AttributeOperation::Read
        ? found->GetReadPrivilege()
        : found->GetWritePrivilege();
    if (!privilege)
      return request.operation == AttributeOperation::Read
          ? CHIP_IM_GLOBAL_STATUS(UnsupportedRead)
          : CHIP_IM_GLOBAL_STATUS(UnsupportedWrite);
    if (request.operation == AttributeOperation::Write) {
      if (found->HasFlags(AttributeQualityFlags::kTimed) && !request.timed)
        return CHIP_IM_GLOBAL_STATUS(NeedsTimedInteraction);
      if (request.data_version && *request.data_version != cluster->dataVersion)
        return CHIP_IM_GLOBAL_STATUS(DataVersionMismatch);
    }
    result.read = found->GetReadPrivilege();
    result.write = found->GetWritePrivilege();
    result.flags = {found->HasFlags(AttributeQualityFlags::kListAttribute),
                    found->HasFlags(AttributeQualityFlags::kFabricScoped),
                    found->HasFlags(AttributeQualityFlags::kFabricSensitive),
                    found->HasFlags(AttributeQualityFlags::kChangesOmitted),
                    found->HasFlags(AttributeQualityFlags::kTimed)};
    return CHIP_NO_ERROR;
  }
  CHIP_ERROR Access(const BridgeRequestMetadata &request, const BridgeAttributeContract &attribute,
                    const BridgeFabricScope &fabric) {
    chip::Access::RequestPath path;
    path.cluster = request.cluster;
    path.endpoint = request.endpoint;
    path.entityId = request.member;
    const bool read = request.operation == BridgeRequestMetadata::Operation::Read;
    path.requestType = read ? chip::Access::RequestType::kAttributeReadRequest
                            : chip::Access::RequestType::kAttributeWriteRequest;
    const auto privilege = read ? attribute.read : attribute.write;
    if (!privilege) return CHIP_ERROR_INCORRECT_STATE;
    return fabrics_.Validate(fabric, path, *privilege);
  }
  SdkBridgeFabricScopes &fabrics_;
  chip::app::DataModel::Provider &provider_;
};

} // namespace wotex::matter

#endif
