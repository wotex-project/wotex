#include "sdk_bridge_guard_test.hpp"
#include "sdk_bridge_requests_test.hpp"
#include "wotex_matter/bridge_guard.hpp"
#include "wotex_matter/bridge_endpoints.hpp"
#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <lib/core/NodeId.h>
#include <credentials/TestOnlyLocalCertificateAuthority.h>
#include <credentials/GroupDataProvider.h>
#include <app/server/Server.h>
#include <stdexcept>
#include <iostream>

namespace wotex::matter::testing {

namespace {

void ScopeRequire(bool value, const char *stage) {
  if (!value) {
    std::cerr << "fabric scope test: " << stage << '\n' << std::flush;
    std::_Exit(1);
  }
}

void ScopeSuccess(CHIP_ERROR error, const char *stage) {
  if (error != CHIP_NO_ERROR) {
    std::cerr << "fabric scope error " << error.AsInteger() << '\n';
    ScopeRequire(false, stage);
  }
}

chip::FabricIndex ScopeAdd(chip::FabricTable &table,
                           chip::Credentials::TestOnlyLocalCertificateAuthority &authority,
                           chip::FabricId fabric_id, chip::NodeId node_id) {
  std::array<std::uint8_t, chip::Crypto::kMIN_CSR_Buffer_Size> bytes{};
  chip::MutableByteSpan csr(bytes);
  ScopeSuccess(table.AllocatePendingOperationalKey(chip::NullOptional, csr), "add CSR");
  authority.GenerateNocChain(fabric_id, node_id, csr);
  ScopeSuccess(authority.GetStatus(), "add authority");
  ScopeSuccess(table.AddNewPendingTrustedRootCert(authority.GetRcac()), "add root");
  chip::FabricIndex index = 0;
  ScopeSuccess(table.AddNewPendingFabricWithOperationalKeystore(
                   authority.GetNoc(), authority.GetIcac(), static_cast<chip::VendorId>(0xFFF1),
                   &index, chip::FabricTable::AdvertiseIdentity::No),
               "add NOC");
  ScopeSuccess(table.CommitPendingFabricData(), "add commit");
  return index;
}

void ScopeUpdate(chip::FabricTable &table,
                 chip::Credentials::TestOnlyLocalCertificateAuthority &authority,
                 chip::FabricIndex index, chip::FabricId fabric_id, chip::NodeId node_id) {
  std::array<std::uint8_t, chip::Crypto::kMIN_CSR_Buffer_Size> bytes{};
  chip::MutableByteSpan csr(bytes);
  ScopeSuccess(table.AllocatePendingOperationalKey(chip::MakeOptional(index), csr), "update CSR");
  authority.GenerateNocChain(fabric_id, node_id, csr);
  ScopeSuccess(authority.GetStatus(), "update authority");
  ScopeSuccess(
      table.UpdatePendingFabricWithOperationalKeystore(
          index, authority.GetNoc(), authority.GetIcac(), chip::FabricTable::AdvertiseIdentity::No),
      "update NOC");
}

std::size_t ScopeGrant(const chip::Access::SubjectDescriptor &principal) {
  auto &access = chip::Access::GetAccessControl();
  chip::Access::AccessControl::Entry entry;
  ScopeSuccess(access.PrepareEntry(entry), "fresh ACL entry");
  ScopeSuccess(entry.SetFabricIndex(principal.fabricIndex), "fresh ACL fabric");
  ScopeSuccess(entry.SetPrivilege(chip::Access::Privilege::kOperate), "fresh ACL privilege");
  ScopeSuccess(entry.SetAuthMode(principal.authMode), "fresh ACL mode");
  ScopeSuccess(entry.AddSubject(nullptr, principal.subject), "fresh ACL subject");
  chip::Access::AccessControl::Entry::Target target{};
  target.flags = decltype(target)::kCluster | decltype(target)::kEndpoint;
  target.cluster = 6;
  target.endpoint = 3;
  ScopeSuccess(entry.AddTarget(nullptr, target), "fresh ACL target");
  std::size_t index = 0;
  ScopeSuccess(access.CreateEntry(nullptr, principal.fabricIndex, &index, entry),
               "fresh ACL create");
  return index;
}
class ScopeMetadata final : public chip::app::CodegenDataModelProvider {
 public:
  explicit ScopeMetadata(chip::app::DataModel::Provider &provider) : provider_(provider) {}
  unsigned failing_stage{0};
  std::optional<chip::app::DataModel::AcceptedCommandEntry> replacement;
  CHIP_ERROR Endpoints(
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::EndpointEntry> &builder) override {
    return failing_stage == 1 ? CHIP_ERROR_NO_MEMORY : provider_.Endpoints(builder);
  }
  CHIP_ERROR ServerClusters(
      chip::EndpointId endpoint,
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::ServerClusterEntry> &builder) override {
    return failing_stage == 2 ? CHIP_ERROR_NO_MEMORY : provider_.ServerClusters(endpoint, builder);
  }
  CHIP_ERROR AcceptedCommands(
      const chip::app::ConcreteClusterPath &path,
      chip::ReadOnlyBufferBuilder<chip::app::DataModel::AcceptedCommandEntry> &builder) override {
    if (failing_stage == 3) return CHIP_ERROR_NO_MEMORY;
    if (replacement) {
      const chip::app::DataModel::AcceptedCommandEntry commands[]{*replacement};
      return builder.AppendElements(commands);
    }
    return provider_.AcceptedCommands(path, builder);
  }
 private:
  chip::app::DataModel::Provider &provider_;
};
} // namespace

void VerifyBridgeGuard(SdkBridgeServerBinding &server, chip::app::DataModel::Provider &provider,
                       bool omit_finish) {
  // Direct SDK fabric/ACL APIs and synthetic callback principals; these tests
  // do not establish transport authentication, consumer execution or interop.
  SdkBridgeEndpointBinding children(server);
  ScopeSuccess(children.Init({}), "guard endpoints");
  BridgeEndpoint endpoint;
  ScopeSuccess(
      children.Add({"guard-light", BridgedDeviceType::OnOffLight, "Guard light", {}, {}}, endpoint),
      "guard child");
  ScopeRequire(endpoint.endpoint == 3, "guard child identity");
  using Status = chip::Protocols::InteractionModel::Status;
  auto &table = chip::Server::GetInstance().GetFabricTable();
  SdkBridgeFabricScopes scopes(table);
  chip::Access::SubjectDescriptor principal;
  principal.authMode = chip::Access::AuthMode::kCase;
  principal.subject = 42;
  principal.cats.values[0] = 0x00010002;
  BridgeFabricScope fabric_sentinel;
  fabric_sentinel.epoch = 777;
  ScopeRequire(scopes.Capture(principal, fabric_sentinel) == CHIP_ERROR_INCORRECT_STATE &&
                   fabric_sentinel.epoch == 777,
               "inactive output preserved");
  ScopeSuccess(scopes.Init(), "scope attach");
  ScopeRequire(scopes.Init() == CHIP_ERROR_INCORRECT_STATE, "second attach refused");
  ScopeRequire(scopes.Capture(principal, fabric_sentinel) == CHIP_ERROR_ACCESS_DENIED,
               "absent fabric refused");
  chip::Credentials::TestOnlyLocalCertificateAuthority authority;
  authority.Init();
  ScopeSuccess(authority.GetStatus(), "ephemeral test authority");
  const auto index = ScopeAdd(table, authority, 17, 1);
  principal.fabricIndex = index;
  ScopeMetadata metadata(provider);
  SdkBridgeInvokeGuard guard(scopes, metadata);
  BridgeRequestMetadata request;
  request.operation = BridgeRequestMetadata::Operation::Invoke;
  request.principal = principal;
  request.endpoint = 3;
  request.cluster = 6;
  request.member = 1;
  BridgeInvokeScope invoke_scope;
  invoke_scope.fabric.epoch = 777;
  ScopeRequire(guard.Capture(request, invoke_scope) == CHIP_ERROR_ACCESS_DENIED &&
                   invoke_scope.fabric.epoch == 777,
               "realm grants no invoke authority");
  BridgeFabricScope original;
  ScopeSuccess(scopes.Capture(principal, original), "fresh scope capture");
  ScopeSuccess(scopes.Check(original), "fresh scope valid");
  ScopeRequire(original.fabric_id == 17 && original.bridge_node == 1 &&
                   original.principal.subject == 42 &&
                   original.principal.cats.values[0] == 0x00010002,
               "complete scope identity retained");
  chip::Access::RequestPath path;
  path.cluster = 6;
  path.endpoint = 3;
  path.requestType = chip::Access::RequestType::kAttributeWriteRequest;
  path.entityId = 0;
  auto &access = chip::Access::GetAccessControl();
  ScopeRequire(scopes.Validate(original, path, chip::Access::Privilege::kOperate) ==
                   CHIP_ERROR_ACCESS_DENIED,
               "live fabric scope grants no ACL authority");
  std::size_t acl_index = 0;
  {
    chip::Access::AccessControl::Entry entry;
    ScopeSuccess(access.PrepareEntry(entry), "ACL entry prepare");
    ScopeSuccess(entry.SetFabricIndex(index), "ACL fabric");
    ScopeSuccess(entry.SetPrivilege(chip::Access::Privilege::kOperate), "ACL privilege");
    ScopeSuccess(entry.SetAuthMode(chip::Access::AuthMode::kCase), "ACL auth mode");
    ScopeSuccess(entry.AddSubject(nullptr, 42), "ACL subject");
    chip::Access::AccessControl::Entry::Target target{};
    target.flags = decltype(target)::kCluster | decltype(target)::kEndpoint;
    target.cluster = 6;
    target.endpoint = 3;
    ScopeSuccess(entry.AddTarget(nullptr, target), "ACL target");
    ScopeSuccess(access.CreateEntry(nullptr, index, &acl_index, entry), "explicit test ACL create");
    ScopeSuccess(access.ReadEntry(index, acl_index, entry), "test ACL readback");
    chip::FabricIndex stored_fabric = 0;
    chip::Access::AuthMode stored_auth = chip::Access::AuthMode::kNone;
    chip::Access::Privilege stored_privilege = chip::Access::Privilege::kView;
    chip::NodeId stored_subject = 0;
    chip::Access::AccessControl::Entry::Target stored_target{};
    ScopeSuccess(entry.GetFabricIndex(stored_fabric), "test ACL fabric readback");
    ScopeSuccess(entry.GetAuthMode(stored_auth), "test ACL auth readback");
    ScopeSuccess(entry.GetPrivilege(stored_privilege), "test ACL privilege readback");
    ScopeSuccess(entry.GetSubject(0, stored_subject), "test ACL subject readback");
    ScopeSuccess(entry.GetTarget(0, stored_target), "test ACL target readback");
    ScopeRequire(stored_fabric == index && stored_auth == chip::Access::AuthMode::kCase &&
                     stored_privilege == chip::Access::Privilege::kOperate &&
                     stored_subject == 42 && stored_target.flags == target.flags &&
                     stored_target.cluster == 6 && stored_target.endpoint == 3,
                 "stored ACL preserves explicit fixture");
  }
  ScopeSuccess(scopes.Validate(original, path, chip::Access::Privilege::kOperate),
               "current ACL permit");
  ScopeSuccess(guard.Capture(request, invoke_scope), "current invoke scope");
  ScopeSuccess(guard.Validate(invoke_scope), "current invoke ACL");
  VerifyGuardedCompletion(guard, principal, [] {}, CHIP_NO_ERROR, Status::Success);
  BridgeInvokeScope sentinel;
  sentinel.fabric.epoch = 777;
  for (unsigned stage = 1; stage <= 3; ++stage) {
    metadata.failing_stage = stage;
    ScopeRequire(
        guard.Capture(request, sentinel) == CHIP_ERROR_NO_MEMORY && sentinel.fabric.epoch == 777,
        "metadata error and output preserved");
    metadata.failing_stage = 0;
    VerifyGuardedCompletion(guard, principal, [&] { metadata.failing_stage = stage; },
                            CHIP_ERROR_NO_MEMORY, Status::Failure);
    metadata.failing_stage = 0;
  }
  using Command = chip::app::DataModel::AcceptedCommandEntry;
  using Flags = chip::app::DataModel::CommandQualityFlags;
  metadata.replacement = Command(1, {}, chip::Access::Privilege::kManage);
  ScopeRequire(guard.Capture(request, sentinel) == CHIP_ERROR_ACCESS_DENIED,
               "command privilege enforced");
  metadata.replacement = Command(1, chip::BitMask<Flags>(Flags::kTimed),
                                 chip::Access::Privilege::kOperate);
  ScopeRequire(guard.Capture(request, sentinel) == CHIP_IM_GLOBAL_STATUS(NeedsTimedInteraction),
               "required timed invocation enforced");
  auto timed = request;
  timed.timed = true;
  ScopeSuccess(guard.Capture(timed, sentinel), "explicit timed invocation");
  metadata.replacement.reset();
  VerifyGuardedCompletion(guard, principal, [&] {
    metadata.replacement = Command(1, {}, chip::Access::Privilege::kView);
  }, CHIP_ERROR_ACCESS_DENIED, Status::UnsupportedAccess);
  metadata.replacement.reset();
  for (const auto endpoint_id : {0, 1, 2, 65535}) {
    auto invalid = request;
    invalid.endpoint = static_cast<chip::EndpointId>(endpoint_id);
    ScopeRequire(guard.Capture(invalid, sentinel) == CHIP_ERROR_INVALID_ARGUMENT,
                 "root or dummy child guard");
  }
  auto absent = request;
  absent.endpoint = 64;
  ScopeRequire(guard.Capture(absent, sentinel) == CHIP_IM_GLOBAL_STATUS(UnsupportedEndpoint),
               "absent endpoint guard");
  absent = request;
  absent.cluster = 0x1234;
  ScopeRequire(guard.Capture(absent, sentinel) == CHIP_IM_GLOBAL_STATUS(UnsupportedCluster),
               "absent cluster guard");
  absent = request;
  absent.member = 0x7f;
  ScopeRequire(guard.Capture(absent, sentinel) == CHIP_IM_GLOBAL_STATUS(UnsupportedCommand),
               "absent command guard");
  auto foreign_scope = invoke_scope;
  foreign_scope.request.principal.cats.values[2] = 0x00030004;
  ScopeRequire(guard.Validate(foreign_scope) == CHIP_ERROR_INVALID_ARGUMENT,
               "complete scope principal agreement");
  auto group = principal;
  group.authMode = chip::Access::AuthMode::kGroup;
  group.subject = chip::NodeIdFromGroupId(7);
  auto group_request = request;
  group_request.principal = group;
  auto *groups = chip::Credentials::GetGroupDataProvider();
  ScopeRequire(groups != nullptr, "explicit group provider");
  chip::Credentials::GroupDataProvider::GroupInfo group_info;
  const auto missing_group = groups->GetGroupInfo(index, 7, group_info);
  ScopeRequire(
      missing_group != CHIP_NO_ERROR && guard.Capture(group_request, sentinel) == missing_group,
      "missing group metadata error preserved");
  ScopeSuccess(groups->SetGroupInfo(index, {7, "Guard group"}), "explicit group metadata");
  ScopeRequire(guard.Capture(group_request, sentinel) == CHIP_ERROR_ACCESS_DENIED,
               "group realm grants no ACL authority");
  const auto group_acl = ScopeGrant(group);
  ScopeSuccess(guard.Capture(group_request, sentinel), "group explicit ACL capture");
  VerifyGuardedCompletion(guard, group, [] {}, CHIP_NO_ERROR, Status::Success);
  ScopeSuccess(access.DeleteEntry(nullptr, index, group_acl), "group explicit ACL revoke");
  ScopeSuccess(groups->RemoveGroupInfo(index, 7), "explicit group metadata cleanup");
  std::cout << "\nSDK invoke guard metadata errors, timing and current ACL passed\n" << std::flush;
  ScopeRequire(
      scopes.Validate(original, path, chip::Access::Privilege::kManage) == CHIP_ERROR_ACCESS_DENIED,
      "current ACL privilege refused");
  auto foreign_path = path;
  foreign_path.cluster = 3;
  ScopeRequire(scopes.Validate(original, foreign_path, chip::Access::Privilege::kOperate) ==
                   CHIP_ERROR_ACCESS_DENIED,
               "current ACL foreign target refused");
  VerifyGuardedCompletion(guard, principal, [&] {
    ScopeSuccess(access.DeleteEntry(nullptr, index, acl_index), "explicit test ACL revoke");
  }, CHIP_ERROR_ACCESS_DENIED, Status::UnsupportedAccess);
  ScopeSuccess(scopes.Check(original), "ACL revoke did not change fabric realm");
  ScopeRequire(scopes.Validate(original, path, chip::Access::Privilege::kOperate) ==
                   CHIP_ERROR_ACCESS_DENIED,
               "current ACL revoke refused an otherwise valid captured fabric scope");
  acl_index = ScopeGrant(principal);
  VerifyGuardedCompletion(guard, principal, [&] { ScopeUpdate(table, authority, index, 17, 1); },
                          CHIP_ERROR_ACCESS_DENIED, Status::UnsupportedAccess);
  ScopeRequire(scopes.Check(original) == CHIP_ERROR_ACCESS_DENIED,
               "old scope invalidated on update");
  BridgeFabricScope pending;
  ScopeSuccess(scopes.Capture(principal, pending), "pending scope capture");
  ScopeSuccess(scopes.Check(pending), "pending scope valid");
  ScopeRequire(pending.noc_sha256 != original.noc_sha256, "rotated certificate distinguished");
  VerifyGuardedCompletion(guard, principal, [&] { table.RevertPendingFabricData(); },
                          CHIP_ERROR_ACCESS_DENIED, Status::UnsupportedAccess);
  ScopeRequire(scopes.Check(pending) == CHIP_ERROR_ACCESS_DENIED,
               "rollback cannot revive pending certificate scope without a delegate event");
  BridgeFabricScope rolled_back;
  ScopeSuccess(scopes.Capture(principal, rolled_back), "rollback fresh scope capture");
  ScopeSuccess(scopes.Check(rolled_back), "rollback fresh scope valid");
  ScopeRequire(rolled_back.epoch == pending.epoch && rolled_back.noc_sha256 == original.noc_sha256,
               "rollback did not emit a new epoch but restored original certificate");
  VerifyGuardedCompletion(guard, principal, [&] {
    ScopeUpdate(table, authority, index, 17, 1);
    ScopeSuccess(table.CommitPendingFabricData(), "update commit");
  }, CHIP_ERROR_ACCESS_DENIED, Status::UnsupportedAccess);
  ScopeRequire(scopes.Check(rolled_back) == CHIP_ERROR_ACCESS_DENIED, "commit old scope refused");
  BridgeFabricScope committed;
  ScopeSuccess(scopes.Capture(principal, committed), "committed scope capture");
  VerifyGuardedCompletion(guard, principal, [&] {
    ScopeSuccess(table.Delete(index), "fabric delete");
    ScopeRequire(scopes.Check(committed) == CHIP_ERROR_ACCESS_DENIED,
                 "deleted fabric scope refused");
    ScopeSuccess(table.SetFabricIndexForNextAddition(index), "reuse exact local index fixture");
    ScopeRequire(ScopeAdd(table, authority, 17, 1) == index, "same root/fabric/node/index reused");
    acl_index = ScopeGrant(principal);
  }, CHIP_ERROR_ACCESS_DENIED, Status::UnsupportedAccess);
  BridgeFabricScope replacement;
  ScopeSuccess(scopes.Capture(principal, replacement), "replacement scope capture");
  ScopeRequire(replacement.root == committed.root && replacement.fabric_id == committed.fabric_id &&
                   replacement.bridge_node == committed.bridge_node &&
                   replacement.epoch != committed.epoch &&
                   scopes.Check(committed) == CHIP_ERROR_ACCESS_DENIED,
               "same realm did not revive retired scope");
  ScopeSuccess(scopes.Check(replacement), "replacement fresh scope valid");
  VerifyGuardedCompletion(guard, principal, [&] {
    ScopeSuccess(children.Remove("guard-light"), "retire guard endpoint");
  }, CHIP_IM_GLOBAL_STATUS(UnsupportedEndpoint), Status::UnsupportedEndpoint);
  for (auto auth : {chip::Access::AuthMode::kPase, chip::Access::AuthMode::kNone}) {
    principal.authMode = auth;
    ScopeRequire(scopes.Capture(principal, fabric_sentinel) == CHIP_ERROR_ACCESS_DENIED &&
                     fabric_sentinel.epoch == 777,
                 "non-fabric principal refused without changing output");
  }
  ScopeSuccess(access.DeleteEntry(nullptr, index, acl_index), "final ACL revoke");
  ScopeSuccess(table.Delete(index), "final fabric delete");
  children.Finish();
  std::cout << "\nSDK invoke guard revocation, credential rollback and endpoint retirement passed\n"
            << std::flush;
  if (omit_finish) {
    std::cout << "SDK fabric scope missing detach prepared\n" << std::flush;
    return;
  }
  scopes.Finish();
  scopes.Finish();
  SdkBridgeFabricScopes closed(table);
  closed.Finish();
  ScopeRequire(closed.Init() == CHIP_ERROR_INCORRECT_STATE, "finished inactive scope refused");
  ScopeRequire(scopes.Init() == CHIP_ERROR_INCORRECT_STATE &&
                   scopes.Check(replacement) == CHIP_ERROR_INCORRECT_STATE,
               "closed scope lifetime refused");
  std::cout << "SDK fabric scope attachment and shutdown passed\n" << std::flush;
}

} // namespace wotex::matter::testing
