#include "wotex_matter/bridge_guard.hpp"
#include "wotex_matter/bridge_server.hpp"

#include <access/AccessControl.h>
#include <credentials/CHIPCert.h>

#include <algorithm>
#include <cstdlib>
#include <new>

namespace wotex::matter {

SdkBridgeFabricScopes::SdkBridgeFabricScopes(chip::FabricTable &table) : table_(table) {}
SdkBridgeFabricScopes::~SdkBridgeFabricScopes() {
  if (active_) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
}
CHIP_ERROR SdkBridgeFabricScopes::Init() {
  if (used_) return CHIP_ERROR_INCORRECT_STATE;
  const auto error = table_.AddFabricDelegate(this);
  if (error != CHIP_NO_ERROR) return error;
  used_ = true;
  active_ = true;
  for (const auto &fabric : table_) Bump(fabric.GetFabricIndex());
  return CHIP_NO_ERROR;
}
void SdkBridgeFabricScopes::Finish() {
  if (active_) table_.RemoveFabricDelegate(this);
  used_ = true;
  active_ = false;
  epochs_.fill(0);
}
CHIP_ERROR SdkBridgeFabricScopes::Capture(const chip::Access::SubjectDescriptor &principal,
                                          BridgeFabricScope &scope) const {
  if (!active_) return CHIP_ERROR_INCORRECT_STATE;
  if ((principal.authMode != chip::Access::AuthMode::kCase &&
       principal.authMode != chip::Access::AuthMode::kGroup) ||
      !chip::IsValidFabricIndex(principal.fabricIndex))
    return CHIP_ERROR_ACCESS_DENIED;
  const auto *fabric = table_.FindFabricWithIndex(principal.fabricIndex);
  if (!fabric || !fabric->IsInitialized() || epochs_[principal.fabricIndex] == 0)
    return CHIP_ERROR_ACCESS_DENIED;
  BridgeFabricScope copied;
  copied.principal = principal;
  copied.epoch = epochs_[principal.fabricIndex];
  copied.fabric_id = fabric->GetFabricId();
  copied.bridge_node = fabric->GetNodeId();
  chip::Crypto::P256PublicKey root;
  auto error = fabric->FetchRootPubkey(root);
  if (error != CHIP_NO_ERROR) return error;
  if (root.Length() != copied.root.size()) return CHIP_ERROR_INVALID_ARGUMENT;
  std::copy_n(root.ConstBytes(), copied.root.size(), copied.root.begin());
  std::array<std::uint8_t, chip::Credentials::kMaxCHIPCertLength> certificate{};
  chip::MutableByteSpan noc(certificate);
  error = table_.FetchNOCCert(principal.fabricIndex, noc);
  if (error != CHIP_NO_ERROR) return error;
  error = chip::Crypto::Hash_SHA256(noc.data(), noc.size(), copied.noc_sha256.data());
  if (error != CHIP_NO_ERROR) return error;
  scope = copied;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeFabricScopes::Check(const BridgeFabricScope &scope) const {
  BridgeFabricScope current;
  const auto error = Capture(scope.principal, current);
  if (error != CHIP_NO_ERROR) return error;
  return current.epoch == scope.epoch && current.fabric_id == scope.fabric_id &&
          current.bridge_node == scope.bridge_node && current.root == scope.root &&
          current.noc_sha256 == scope.noc_sha256
      ? CHIP_NO_ERROR
      : CHIP_ERROR_ACCESS_DENIED;
}
CHIP_ERROR SdkBridgeFabricScopes::Validate(const BridgeFabricScope &scope,
                                           const chip::Access::RequestPath &path,
                                           chip::Access::Privilege privilege) const {
  const auto error = Check(scope);
  if (error != CHIP_NO_ERROR) return error;
  return chip::Access::GetAccessControl().Check(scope.principal, path, privilege);
}
void SdkBridgeFabricScopes::Bump(chip::FabricIndex index) {
  if (!active_ || !chip::IsValidFabricIndex(index)) return;
  if (last_ == std::numeric_limits<std::uint64_t>::max())
    std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
  epochs_[index] = ++last_;
}
void SdkBridgeFabricScopes::FabricWillBeRemoved(const chip::FabricTable &,
                                                chip::FabricIndex index) {
  if (chip::IsValidFabricIndex(index)) epochs_[index] = 0;
}
void SdkBridgeFabricScopes::OnFabricRemoved(const chip::FabricTable &, chip::FabricIndex index) {
  if (chip::IsValidFabricIndex(index)) epochs_[index] = 0;
}
void SdkBridgeFabricScopes::OnFabricUpdated(const chip::FabricTable &, chip::FabricIndex index) {
  Bump(index);
}
void SdkBridgeFabricScopes::OnFabricCommitted(const chip::FabricTable &, chip::FabricIndex index) {
  Bump(index);
}

SdkBridgeInvokeGuard::SdkBridgeInvokeGuard(SdkBridgeFabricScopes &fabrics,
                                           chip::app::DataModel::Provider &provider)
    : fabrics_(fabrics), provider_(provider) {}

CHIP_ERROR SdkBridgeInvokeGuard::Command(const BridgeRequestMetadata &request,
                                         chip::app::DataModel::AcceptedCommandEntry &command) {
  using namespace chip::app::DataModel;
  if (request.operation != BridgeRequestMetadata::Operation::Invoke || request.endpoint < 3 ||
      request.endpoint == chip::kInvalidEndpointId || request.cluster == chip::kInvalidClusterId ||
      !chip::IsValidCommandId(request.member))
    return CHIP_ERROR_INVALID_ARGUMENT;
  chip::ReadOnlyBufferBuilder<EndpointEntry> endpoints;
  auto error = provider_.Endpoints(endpoints);
  if (error != CHIP_NO_ERROR) return error;
  const auto endpoint_list = endpoints.TakeBuffer();
  if (std::none_of(endpoint_list.begin(), endpoint_list.end(),
                   [&](const auto &entry) { return entry.id == request.endpoint; }))
    return CHIP_IM_GLOBAL_STATUS(UnsupportedEndpoint);
  chip::ReadOnlyBufferBuilder<ServerClusterEntry> clusters;
  error = provider_.ServerClusters(request.endpoint, clusters);
  if (error != CHIP_NO_ERROR) return error;
  const auto cluster_list = clusters.TakeBuffer();
  if (std::none_of(cluster_list.begin(), cluster_list.end(),
                   [&](const auto &entry) { return entry.clusterId == request.cluster; }))
    return CHIP_IM_GLOBAL_STATUS(UnsupportedCluster);
  chip::ReadOnlyBufferBuilder<AcceptedCommandEntry> commands;
  error = provider_.AcceptedCommands(
      chip::app::ConcreteClusterPath(request.endpoint, request.cluster), commands);
  if (error != CHIP_NO_ERROR) return error;
  const auto command_list = commands.TakeBuffer();
  const auto found = std::find_if(command_list.begin(), command_list.end(), [&](const auto &entry) {
    return entry.commandId == request.member;
  });
  if (found == command_list.end()) return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
  if (found->HasFlags(CommandQualityFlags::kTimed) && !request.timed)
    return CHIP_IM_GLOBAL_STATUS(NeedsTimedInteraction);
  command = *found;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeInvokeGuard::Access(const BridgeRequestMetadata &request,
                                        const chip::app::DataModel::AcceptedCommandEntry &command) {
  chip::Access::RequestPath path;
  path.cluster = request.cluster;
  path.endpoint = request.endpoint;
  path.requestType = chip::Access::RequestType::kCommandInvokeRequest;
  path.entityId = request.member;
  return chip::Access::GetAccessControl().Check(request.principal, path,
                                                command.GetInvokePrivilege());
}
CHIP_ERROR SdkBridgeInvokeGuard::Capture(const BridgeRequestMetadata &request,
                                         BridgeInvokeScope &scope) noexcept {
  try {
    BridgeInvokeScope copied;
    copied.request = request;
    auto error = fabrics_.Capture(request.principal, copied.fabric);
    if (error != CHIP_NO_ERROR) return error;
    error = Command(request, copied.command);
    if (error != CHIP_NO_ERROR) return error;
    error = Access(request, copied.command);
    if (error != CHIP_NO_ERROR) return error;
    scope = copied;
    return CHIP_NO_ERROR;
  } catch (const std::bad_alloc &) {
    return CHIP_ERROR_NO_MEMORY;
  }
}
CHIP_ERROR SdkBridgeInvokeGuard::Validate(const BridgeInvokeScope &scope) noexcept {
  try {
    const auto &request_principal = scope.request.principal;
    const auto &fabric_principal = scope.fabric.principal;
    if (request_principal.fabricIndex != fabric_principal.fabricIndex ||
        request_principal.authMode != fabric_principal.authMode ||
        request_principal.subject != fabric_principal.subject ||
        request_principal.cats.values != fabric_principal.cats.values ||
        request_principal.isCommissioning != fabric_principal.isCommissioning)
      return CHIP_ERROR_INVALID_ARGUMENT;
    auto error = fabrics_.Check(scope.fabric);
    if (error != CHIP_NO_ERROR) return error;
    chip::app::DataModel::AcceptedCommandEntry current;
    error = Command(scope.request, current);
    if (error != CHIP_NO_ERROR) return error;
    if (current != scope.command) return CHIP_ERROR_ACCESS_DENIED;
    return Access(scope.request, current);
  } catch (const std::bad_alloc &) {
    return CHIP_ERROR_NO_MEMORY;
  }
}

} // namespace wotex::matter
