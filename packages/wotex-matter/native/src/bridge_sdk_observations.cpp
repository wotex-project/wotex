#include "wotex_matter/bridge_sdk_observations.hpp"

#include <platform/CHIPDeviceLayer.h>
#include <cstdlib>
#include <chrono>
#include <type_traits>
#include <utility>

namespace wotex::matter {
namespace {
class TryStackLock final {
 public:
  TryStackLock() : owns_(chip::DeviceLayer::PlatformMgr().TryLockChipStack()) {}
  ~TryStackLock() {
    if (owns_) chip::DeviceLayer::PlatformMgr().UnlockChipStack();
  }
  TryStackLock(const TryStackLock &) = delete;
  TryStackLock &operator=(const TryStackLock &) = delete;
  bool owns() const { return owns_; }
 private:
  const bool owns_;
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
  for (auto &publication : publications_) publication = {};
  used_ = 0;
  published_ = 0;
} catch (...) {
  std::_Exit(70);
}

void SdkBridgeObservationOwner::Fail() noexcept try { output_.Close(); } catch (...) {
  std::_Exit(70);
}

SdkBridgeObservationOwner::Applied SdkBridgeObservationOwner::ApplyOne() {
  Pending pending;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopping_ || used_ == 0) return Applied::Idle;
    pending = std::move(queue_[head_]);
    queue_[head_] = {};
    head_ = (head_ + 1) % queue_.size();
    --used_;
  }
  auto sampled = BridgeConsumerHandoff::ClockSample::Closed;
  CHIP_ERROR observed = CHIP_ERROR_INCORRECT_STATE;
  custody_.With([&](auto &custody, auto now) {
    sampled = custody.Sample(pending.generation, now);
    if (sampled == BridgeConsumerHandoff::ClockSample::Sampled)
      observed = endpoints_.Observe(pending.frame.thing, pending.frame.endpoint,
                                    pending.frame.value);
  });
  if (sampled != BridgeConsumerHandoff::ClockSample::Sampled)
    return sampled == BridgeConsumerHandoff::ClockSample::Closed ? Applied::Done : Applied::Failed;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopping_) return Applied::Done;
    // Input reserves one of 64 output slots before any work enters. Work,
    // this publication queue and writer bytes share those same reservations.
    if (published_ == publications_.size()) std::_Exit(70);
    publications_[(publication_head_ + published_) % publications_.size()] = {
        pending.generation, pending.frame.id,
        observed == CHIP_NO_ERROR ? BridgeObservationOutcome::Applied
                                  : BridgeObservationOutcome::Refused,
        pending.receipt};
    ++published_;
    changed_.notify_one();
  }
  return Applied::Done;
}

bool SdkBridgeObservationOwner::Advance() noexcept try {
#if CHIP_STACK_LOCK_TRACKING_ENABLED
  if (!chip::DeviceLayer::PlatformMgr().IsChipStackLockedByCurrentThread()) return false;
#endif
  if (ApplyOne() != Applied::Failed) return true;
  Fail();
  return false;
} catch (...) {
  Fail();
  return false;
}

void SdkBridgeObservationOwner::Run() noexcept try {
  while (true) {
    Publication publication;
    bool publish = false;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      changed_.wait(lock, [&] { return stopping_ || used_ != 0 || published_ != 0; });
      if (stopping_) return;
      if (published_ != 0) {
        publication = publications_[publication_head_];
        publications_[publication_head_] = {};
        publication_head_ = (publication_head_ + 1) % publications_.size();
        --published_;
        publish = true;
      }
    }
    if (publish) {
      std::string receipt;
      if (EncodeBridgeObservationReceipt(publication.generation, publication.id,
                                         publication.outcome,
                                         receipt) != BridgeObservationEncode::Encoded ||
          output_.CommitObservation(publication.receipt, receipt) !=
              BridgeOutputOwner::Admission::Accepted) {
        Fail();
        return;
      }
      continue;
    }
    bool acquired = false;
    Applied applied = Applied::Idle;
    {
      TryStackLock sdk;
      acquired = sdk.owns();
      if (acquired) applied = ApplyOne();
    }
    if (applied == Applied::Failed) {
      Fail();
      return;
    }
    if (!acquired) {
      // Leave queued work available to the callback holding the SDK lock.
      // Publication wakes this wait and never requires that SDK lock.
      std::unique_lock<std::mutex> lock(mutex_);
      changed_.wait_for(lock, std::chrono::milliseconds(5),
                        [&] { return stopping_ || published_ != 0 || used_ == 0; });
    }
  }
} catch (...) {
  Fail();
}

} // namespace wotex::matter
