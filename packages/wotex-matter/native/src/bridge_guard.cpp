#include "wotex_matter/bridge_guard.hpp"
#include "wotex_matter/bridge_server.hpp"

#include <access/AccessControl.h>
#include <credentials/CHIPCert.h>
#include <clusters/Identify/Commands.h>
#include <clusters/Groups/Commands.h>
#include <clusters/OnOff/Commands.h>
#include <clusters/ScenesManagement/Commands.h>

#include <algorithm>
#include <bitset>
#include <cstdlib>
#include <new>
#include <type_traits>

namespace wotex::matter {
namespace {
namespace Clusters = chip::app::Clusters;
using chip::TLV::TLVReader;
constexpr CHIP_ERROR InvalidCommand = CHIP_IM_GLOBAL_STATUS(InvalidCommand);
constexpr CHIP_ERROR ConstraintError = CHIP_IM_GLOBAL_STATUS(ConstraintError);

// SDK generated decoders initialize missing members to defaults. Require the
// selected model's fields independently, and remove duplicate-field ambiguity.
// Unique unknown fields remain untouched in the owned request payload.
CHIP_ERROR Fields(TLVReader reader, std::uint16_t required, std::uint16_t *present = nullptr) {
  if (reader.GetType() != chip::TLV::kTLVType_Structure) return CHIP_ERROR_WRONG_TLV_TYPE;
  chip::TLV::TLVType outer;
  ReturnErrorOnFailure(reader.EnterContainer(outer));
  std::bitset<256> seen;
  std::uint16_t mask = 0;
  CHIP_ERROR next;
  while ((next = reader.Next()) == CHIP_NO_ERROR) {
    if (!chip::TLV::IsContextTag(reader.GetTag())) continue;
    const auto tag = chip::TLV::TagNumFromTag(reader.GetTag());
    if (seen.test(tag)) return InvalidCommand;
    seen.set(tag);
    if (tag < 16) mask |= static_cast<std::uint16_t>(1U << tag);
  }
  if (next != CHIP_END_OF_TLV) return next;
  ReturnErrorOnFailure(reader.ExitContainer(outer));
  if ((mask & required) != required) return InvalidCommand;
  if (present) *present = mask;
  return CHIP_NO_ERROR;
}
CHIP_ERROR Field(TLVReader reader, unsigned tag, TLVReader &value) {
  chip::TLV::TLVType outer;
  ReturnErrorOnFailure(reader.EnterContainer(outer));
  CHIP_ERROR next;
  while ((next = reader.Next()) == CHIP_NO_ERROR) {
    if (chip::TLV::IsContextTag(reader.GetTag()) &&
        chip::TLV::TagNumFromTag(reader.GetTag()) == tag) {
      value = reader;
      return CHIP_NO_ERROR;
    }
  }
  return next == CHIP_END_OF_TLV ? InvalidCommand : next;
}
CHIP_ERROR SceneFields(TLVReader reader) {
  TLVReader list;
  ReturnErrorOnFailure(Field(reader, 4, list));
  if (list.GetType() != chip::TLV::kTLVType_Array) return CHIP_ERROR_SCHEMA_MISMATCH;
  chip::TLV::TLVType outer;
  ReturnErrorOnFailure(list.EnterContainer(outer));
  CHIP_ERROR next;
  while ((next = list.Next()) == CHIP_NO_ERROR) {
    ReturnErrorOnFailure(Fields(list, 3));
    TLVReader pairs;
    ReturnErrorOnFailure(Field(list, 1, pairs));
    if (pairs.GetType() != chip::TLV::kTLVType_Array) return CHIP_ERROR_SCHEMA_MISMATCH;
    chip::TLV::TLVType nested;
    ReturnErrorOnFailure(pairs.EnterContainer(nested));
    CHIP_ERROR pair;
    while ((pair = pairs.Next()) == CHIP_NO_ERROR) {
      std::uint16_t mask;
      ReturnErrorOnFailure(Fields(pairs, 1, &mask));
      const auto choices = static_cast<unsigned>(mask & 0x1FEU);
      if (choices == 0 || (choices & (choices - 1)) != 0) return InvalidCommand;
    }
    if (pair != CHIP_END_OF_TLV) return pair;
    ReturnErrorOnFailure(pairs.ExitContainer(nested));
  }
  if (next != CHIP_END_OF_TLV) return next;
  return list.ExitContainer(outer);
}
template <typename T> CHIP_ERROR Values(const T &) { return CHIP_NO_ERROR; }
template <typename T> CHIP_ERROR GroupName(const T &value) {
  return value.groupID != 0 && value.groupName.size() <= 16 ? CHIP_NO_ERROR : ConstraintError;
}
CHIP_ERROR Values(const Clusters::Groups::Commands::AddGroup::DecodableType &value) {
  return GroupName(value);
}
CHIP_ERROR Values(const Clusters::Groups::Commands::AddGroupIfIdentifying::DecodableType &value) {
  return GroupName(value);
}
CHIP_ERROR Values(const Clusters::Groups::Commands::ViewGroup::DecodableType &value) {
  return value.groupID != 0 ? CHIP_NO_ERROR : ConstraintError;
}
CHIP_ERROR Values(const Clusters::Groups::Commands::RemoveGroup::DecodableType &value) {
  return value.groupID != 0 ? CHIP_NO_ERROR : ConstraintError;
}
CHIP_ERROR Values(const Clusters::Groups::Commands::GetGroupMembership::DecodableType &value) {
  auto groups = value.groupList.begin();
  while (groups.Next())
    if (groups.GetValue() == 0) return ConstraintError;
  return groups.GetStatus();
}
CHIP_ERROR Values(const Clusters::OnOff::Commands::OnWithTimedOff::DecodableType &value) {
  return value.onOffControl.Raw() <= 1 && value.onTime <= 0xFFFE && value.offWaitTime <= 0xFFFE
      ? CHIP_NO_ERROR
      : ConstraintError;
}
template <typename T> CHIP_ERROR SceneId(const T &value) {
  return value.sceneID < 255 ? CHIP_NO_ERROR : ConstraintError;
}
CHIP_ERROR Values(const Clusters::ScenesManagement::Commands::ViewScene::DecodableType &value) {
  return SceneId(value);
}
CHIP_ERROR Values(const Clusters::ScenesManagement::Commands::RemoveScene::DecodableType &value) {
  return SceneId(value);
}
CHIP_ERROR Values(const Clusters::ScenesManagement::Commands::StoreScene::DecodableType &value) {
  return SceneId(value);
}
CHIP_ERROR Values(const Clusters::ScenesManagement::Commands::RecallScene::DecodableType &value) {
  ReturnErrorOnFailure(SceneId(value));
  return !value.transitionTime.HasValue() || value.transitionTime.Value().IsNull() ||
          value.transitionTime.Value().Value() <= 60000000
      ? CHIP_NO_ERROR
      : ConstraintError;
}
CHIP_ERROR Values(const Clusters::ScenesManagement::Commands::CopyScene::DecodableType &value) {
  return value.sceneIdentifierFrom < 255 && value.sceneIdentifierTo < 255 ? CHIP_NO_ERROR
                                                                          : ConstraintError;
}
CHIP_ERROR Values(const Clusters::ScenesManagement::Commands::AddScene::DecodableType &value) {
  ReturnErrorOnFailure(SceneId(value));
  if (value.transitionTime > 60000000 || value.sceneName.size() > 16) return ConstraintError;
  auto fields = value.extensionFieldSetStructs.begin();
  while (fields.Next()) {
    auto pairs = fields.GetValue().attributeValueList.begin();
    while (pairs.Next()) {} // Decode every lazy typed member, including optional values.
    ReturnErrorOnFailure(pairs.GetStatus());
  }
  return fields.GetStatus();
}
template <typename T> CHIP_ERROR Decode(TLVReader reader, chip::FabricIndex fabric,
                                        std::uint16_t required) {
  ReturnErrorOnFailure(Fields(reader, required));
  if constexpr (std::is_same_v<T, Clusters::ScenesManagement::Commands::AddScene::DecodableType>)
    ReturnErrorOnFailure(SceneFields(reader));
  T value;
  if constexpr (T::kIsFabricScoped) ReturnErrorOnFailure(value.Decode(reader, fabric));
  else ReturnErrorOnFailure(value.Decode(reader));
  return Values(value);
}
}

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

CHIP_ERROR SdkBridgeInvokeGuard::ValidateArguments(const BridgeRequestMetadata &request,
                                                   TLVReader arguments) noexcept try {
  using namespace chip::app::Clusters;
  const auto fabric = request.principal.fabricIndex;
  if (request.operation != BridgeRequestMetadata::Operation::Invoke)
    return CHIP_ERROR_INVALID_ARGUMENT;
  switch (request.cluster) {
  case Identify::Id:
    switch (request.member) {
    case 0:
      return Decode<Identify::Commands::Identify::DecodableType>(arguments, fabric, 1);
    case 64:
      return Decode<Identify::Commands::TriggerEffect::DecodableType>(arguments, fabric, 3);
    }
    break;
  case Groups::Id:
    switch (request.member) {
    case 0:
      return Decode<Groups::Commands::AddGroup::DecodableType>(arguments, fabric, 3);
    case 1:
      return Decode<Groups::Commands::ViewGroup::DecodableType>(arguments, fabric, 1);
    case 2:
      return Decode<Groups::Commands::GetGroupMembership::DecodableType>(arguments, fabric, 1);
    case 3:
      return Decode<Groups::Commands::RemoveGroup::DecodableType>(arguments, fabric, 1);
    case 4:
      return Decode<Groups::Commands::RemoveAllGroups::DecodableType>(arguments, fabric, 0);
    case 5:
      return Decode<Groups::Commands::AddGroupIfIdentifying::DecodableType>(arguments, fabric, 3);
    }
    break;
  case OnOff::Id:
    switch (request.member) {
    case 0:
      return Decode<OnOff::Commands::Off::DecodableType>(arguments, fabric, 0);
    case 1:
      return Decode<OnOff::Commands::On::DecodableType>(arguments, fabric, 0);
    case 2:
      return Decode<OnOff::Commands::Toggle::DecodableType>(arguments, fabric, 0);
    case 64:
      return Decode<OnOff::Commands::OffWithEffect::DecodableType>(arguments, fabric, 3);
    case 65:
      return Decode<OnOff::Commands::OnWithRecallGlobalScene::DecodableType>(arguments, fabric, 0);
    case 66:
      return Decode<OnOff::Commands::OnWithTimedOff::DecodableType>(arguments, fabric, 7);
    }
    break;
  case ScenesManagement::Id:
    switch (request.member) {
    case 0:
      return Decode<ScenesManagement::Commands::AddScene::DecodableType>(arguments, fabric, 31);
    case 1:
      return Decode<ScenesManagement::Commands::ViewScene::DecodableType>(arguments, fabric, 3);
    case 2:
      return Decode<ScenesManagement::Commands::RemoveScene::DecodableType>(arguments, fabric, 3);
    case 3:
      return Decode<ScenesManagement::Commands::RemoveAllScenes::DecodableType>(arguments, fabric,
                                                                                1);
    case 4:
      return Decode<ScenesManagement::Commands::StoreScene::DecodableType>(arguments, fabric, 3);
    case 5:
      return Decode<ScenesManagement::Commands::RecallScene::DecodableType>(arguments, fabric, 3);
    case 6:
      return Decode<ScenesManagement::Commands::GetSceneMembership::DecodableType>(arguments,
                                                                                   fabric, 1);
    case 64:
      return Decode<ScenesManagement::Commands::CopyScene::DecodableType>(arguments, fabric, 31);
    }
    break;
  }
  return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
} catch (...) {
  return CHIP_ERROR_NO_MEMORY;
}

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
