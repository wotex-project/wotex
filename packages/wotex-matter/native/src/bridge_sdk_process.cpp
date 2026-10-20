#include "wotex_matter/bridge_sdk_process.hpp"

#include <lib/support/CHIPMem.h>
#include <cstdlib>
#include <new>
#include <utility>

namespace wotex::matter {
namespace {

// Outlives SDK retirement and contains no commissioning material. A stopped
// process lifetime cannot fall back to a sample/default commissioning provider.
class RetiredCommissioning final : public chip::DeviceLayer::CommissionableDataProvider {
 public:
  CHIP_ERROR GetSetupDiscriminator(std::uint16_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR SetSetupDiscriminator(std::uint16_t) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pIterationCount(std::uint32_t &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR GetSpake2pSalt(chip::MutableByteSpan &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pVerifier(chip::MutableByteSpan &, std::size_t &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR GetSetupPasscode(std::uint32_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR SetSetupPasscode(std::uint32_t) override { return CHIP_ERROR_INCORRECT_STATE; }
};
RetiredCommissioning retired;

class StackLock final {
 public:
  StackLock() { chip::DeviceLayer::PlatformMgr().LockChipStack(); }
  ~StackLock() { chip::DeviceLayer::PlatformMgr().UnlockChipStack(); }
  StackLock(const StackLock &) = delete;
  StackLock &operator=(const StackLock &) = delete;
};
} // namespace

SdkBridgeProcessDriver::SdkBridgeProcessDriver(std::string configuration,
                                               BridgeSdkProcessReceiver &receiver)
    : configuration_(std::move(configuration)), receiver_(receiver) {}

SdkBridgeProcessDriver::~SdkBridgeProcessDriver() {
  if (memory_ || runtime_ || bootstrap_) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
}

bool SdkBridgeProcessDriver::Start(BridgeConsumerHandoff &custody, BridgeHandoffOwner &owner,
                                   BridgeOutputOwner &output,
                                   const std::atomic<bool> &cancel) noexcept try {
  if (used_) return false;
  used_ = true;
  custody_ = &owner;
  if (configuration_.empty() || configuration_.size() > 4096 ||
      configuration_.find('\0') != std::string::npos || cancel.load())
    return false;
  if (chip::Platform::MemoryInit() != CHIP_NO_ERROR) return false;
  memory_ = true;
  if (LoadBootstrap(configuration_, bootstrap_) != BootstrapLoad::Loaded || cancel.load())
    return false;
  try {
    runtime_ = std::make_unique<SdkBridgeBootstrap>(*bootstrap_, custody, receiver_, retired);
  } catch (const std::bad_alloc &) {
    return false;
  }
  if (cancel.load() || runtime_->Init() != CHIP_NO_ERROR) return false;
  initialized_ = true;
  observations_ = std::make_unique<SdkBridgeObservationOwner>(*runtime_->endpoints(), owner,
                                                              output);
  {
    StackLock lock;
    if (cancel.load()) return false;
    attached_ = true;
    if (receiver_.Attach(*runtime_, custody, owner, output, *observations_) != CHIP_NO_ERROR)
      return false;
  }
  if (cancel.load() || runtime_->Start() != CHIP_NO_ERROR) return false;
  loop_ = true;
  if (cancel.load()) return false;
  if (!observations_->Start() || cancel.load()) return false;
  accepting_.store(true);
  return true;
} catch (...) {
  return false;
}

bool SdkBridgeProcessDriver::Ready(const BridgeConsumerHandoff::Ticket &ticket) noexcept {
  return accepting_.load() && receiver_.ResultReady(ticket);
}

bool SdkBridgeProcessDriver::Observe(const BridgeConsumerHandoff::Generation &generation,
                                     BridgeObservationFrame &&frame) noexcept {
  return accepting_.load() && observations_ && observations_->Submit(generation, std::move(frame));
}

bool SdkBridgeProcessDriver::Stop() noexcept try {
  if (!used_ || stopped_) return false;
  stopped_ = true;
  accepting_.store(false);
  if (observations_) {
    observations_->Stop();
  }
  if (initialized_) {
    {
      StackLock lock;
      if (attached_ && receiver_.Finish() != CHIP_NO_ERROR) return false;
      attached_ = false;
      if (!custody_->With(
              [](auto &custody, auto) { return custody.closed() && custody.pending() == 0; }))
        return false;
    }
    if (loop_) {
      if (runtime_->Stop() != CHIP_NO_ERROR) return false;
      loop_ = false;
    }
    // SDK callbacks can still be returning from an explicit progress call
    // after Stop joins the publication worker. Keep their borrowed owner alive
    // through receiver retirement and the joined SDK event loop.
    observations_.reset();
    // The SDK loop and input reader have joined. Holding custody during final
    // raw SDK checks now cannot reverse a live SDK->custody lock order, and
    // excludes the output writer's concurrent, idempotent closure.
    custody_->With([&](auto &, auto) { runtime_->Finish(); });
    initialized_ = false;
  }
  observations_.reset();
  runtime_.reset();
  bootstrap_.reset();
  if (memory_) {
    chip::Platform::MemoryShutdown();
    memory_ = false;
  }
  custody_ = nullptr;
  return true;
} catch (...) {
  return false;
}

} // namespace wotex::matter
