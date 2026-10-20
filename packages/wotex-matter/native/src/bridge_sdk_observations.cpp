#include "wotex_matter/bridge_sdk_observations.hpp"

#include <platform/CHIPDeviceLayer.h>
#include <cstdlib>
#include <type_traits>
#include <utility>

namespace wotex::matter {
namespace {
class StackLock final {
 public:
  StackLock() { chip::DeviceLayer::PlatformMgr().LockChipStack(); }
  ~StackLock() { chip::DeviceLayer::PlatformMgr().UnlockChipStack(); }
  StackLock(const StackLock &) = delete;
  StackLock &operator=(const StackLock &) = delete;
};
}

SdkBridgeObservationOwner::SdkBridgeObservationOwner(SdkBridgeEndpointBinding &endpoints,
                                                     BridgeHandoffOwner &custody,
                                                     BridgeOutputOwner &output)
    : endpoints_(endpoints), custody_(custody), output_(output) {}

SdkBridgeObservationOwner::~SdkBridgeObservationOwner() {
  if (worker_.joinable()) std::_Exit(70);
}

bool SdkBridgeObservationOwner::Start() noexcept try {
  std::lock_guard<std::mutex> lock(mutex_);
  if (started_ || stopping_) return false;
  started_ = true;
  worker_ = std::thread([this] { Run(); });
  return true;
} catch (...) {
  return false;
}

bool SdkBridgeObservationOwner::Submit(const BridgeConsumerHandoff::Generation &generation,
                                       BridgeObservationFrame &&frame) noexcept try {
  if (frame.id == 0 || frame.thing.empty() || frame.thing.size() > 256 || frame.endpoint < 3 ||
      frame.endpoint > 65534)
    return false;
  std::lock_guard<std::mutex> lock(mutex_);
  if (!started_ || stopping_ || used_ == queue_.size()) return false;
  BridgeOutputOwner::ObservationTicket receipt;
  if (output_.ReserveObservation(receipt) != BridgeOutputOwner::Admission::Accepted) return false;
  // Reservation cannot be stranded by a throwing queue move.
  static_assert(std::is_nothrow_move_assignable_v<Pending>);
  auto &pending = queue_[(head_ + used_) % queue_.size()];
  pending = {generation, std::move(frame), receipt};
  ++used_;
  changed_.notify_one();
  return true;
} catch (...) {
  return false;
}

void SdkBridgeObservationOwner::Stop() noexcept try {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
    changed_.notify_all();
  }
  if (worker_.joinable()) worker_.join();
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto &pending : queue_) pending = {};
  used_ = 0;
} catch (...) {
  std::_Exit(70);
}

void SdkBridgeObservationOwner::Fail() noexcept try { output_.Close(); } catch (...) {
  std::_Exit(70);
}

void SdkBridgeObservationOwner::Run() noexcept try {
  while (true) {
    Pending pending;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      changed_.wait(lock, [&] { return stopping_ || used_ != 0; });
      if (stopping_) return;
      pending = std::move(queue_[head_]);
      queue_[head_] = {};
      head_ = (head_ + 1) % queue_.size();
      --used_;
    }
    auto sampled = BridgeConsumerHandoff::ClockSample::Closed;
    CHIP_ERROR observed = CHIP_ERROR_INCORRECT_STATE;
    {
      StackLock sdk;
      custody_.With([&](auto &custody, auto now) {
        sampled = custody.Sample(pending.generation, now);
        if (sampled != BridgeConsumerHandoff::ClockSample::Sampled) return;
        observed = endpoints_.Observe(pending.frame.thing, pending.frame.endpoint,
                                      pending.frame.value);
      });
    }
    if (sampled != BridgeConsumerHandoff::ClockSample::Sampled) {
      if (sampled != BridgeConsumerHandoff::ClockSample::Closed) Fail();
      return;
    }
    std::string receipt;
    const auto outcome = observed == CHIP_NO_ERROR ? BridgeObservationOutcome::Applied
                                                   : BridgeObservationOutcome::Refused;
    if (EncodeBridgeObservationReceipt(pending.generation, pending.frame.id, outcome, receipt) !=
            BridgeObservationEncode::Encoded ||
        output_.CommitObservation(pending.receipt, receipt) !=
            BridgeOutputOwner::Admission::Accepted) {
      Fail();
      return;
    }
  }
} catch (...) {
  Fail();
}

} // namespace wotex::matter
