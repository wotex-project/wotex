#ifndef WOTEX_MATTER_BRIDGE_GUARD_HPP
#define WOTEX_MATTER_BRIDGE_GUARD_HPP

#include "wotex_matter/bridge_requests.hpp"

#include <app/data-model-provider/Provider.h>
#include <access/AccessControl.h>
#include <credentials/FabricTable.h>

#include <limits>

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

} // namespace wotex::matter

#endif
