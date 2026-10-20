#ifndef WOTEX_MATTER_BRIDGE_SDK_OBSERVATIONS_HPP
#define WOTEX_MATTER_BRIDGE_SDK_OBSERVATIONS_HPP

#include "wotex_matter/bridge_endpoints.hpp"
#include "wotex_matter/bridge_output.hpp"

#include <thread>

namespace wotex::matter {

// Internal single-input/single-worker approved-state delivery. Submission owns
// a fixed queue slot and reserves receipt capacity before SDK work. Queue and
// output mutexes are never held across SDK acquisition or descriptor I/O.
// The worker applies under SDK->custody locking, then publishes its receipt
// outside both locks. No consumer command or physical effect is inferred.
// Start after SDK startup. Stop/join outside SDK locks after input retirement,
// before receiver/endpoint/SDK cleanup; all borrowed owners outlive this object.
class SdkBridgeObservationOwner final {
 public:
  SdkBridgeObservationOwner(SdkBridgeEndpointBinding &endpoints, BridgeHandoffOwner &custody,
                            BridgeOutputOwner &output);
  ~SdkBridgeObservationOwner();
  SdkBridgeObservationOwner(const SdkBridgeObservationOwner &) = delete;
  SdkBridgeObservationOwner &operator=(const SdkBridgeObservationOwner &) = delete;

  bool Start() noexcept;
  bool Submit(const BridgeConsumerHandoff::Generation &generation,
              BridgeObservationFrame &&frame) noexcept;
  void Stop() noexcept;

 private:
  struct Pending {
    BridgeConsumerHandoff::Generation generation{};
    BridgeObservationFrame frame;
    BridgeOutputOwner::ObservationTicket receipt;
  };
  void Run() noexcept;
  void Fail() noexcept;
  SdkBridgeEndpointBinding &endpoints_;
  BridgeHandoffOwner &custody_;
  BridgeOutputOwner &output_;
  std::mutex mutex_;
  std::condition_variable changed_;
  std::array<Pending, BridgeOutputOwner::kObservationCapacity> queue_{};
  std::size_t head_{0}, used_{0};
  bool started_{false}, stopping_{false};
  std::thread worker_;
};

} // namespace wotex::matter
#endif
