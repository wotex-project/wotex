#ifndef WOTEX_MATTER_CONTROLLER_HPP
#define WOTEX_MATTER_CONTROLLER_HPP

#include "wotex_matter/protocol.hpp"

#include <memory>

namespace wotex::matter {

class SdkControllerBackend final : public ControllerBackend {
 public:
  SdkControllerBackend();
  ~SdkControllerBackend() override;

  SdkControllerBackend(const SdkControllerBackend &) = delete;
  SdkControllerBackend &operator=(const SdkControllerBackend &) = delete;

  BackendResult Open(const NativeOpenOptions &options) override;
  InteractionResponse Interact(const InteractionRequest &request) override;
  CommissioningResponse Commission(const CommissioningRequest &request) override;
  CommissioningWindowResponse OpenWindow(
      const CommissioningWindowRequest &request) override;
  void SetSubscriptionSinks(ReportSink report, StatusSink status,
                            FailureSink failure) override;
  void SetControlPump(std::function<bool()> pump) override;
  SubscriptionResponse Subscribe(const SubscriptionRequest &request) override;
  bool ActivateSubscription(const std::string &subscription_id,
                            std::uint64_t generation) override;
  BackendResult CancelSubscription(const std::string &subscription_id,
                                   std::uint64_t generation,
                                   std::uint32_t timeout_ms) override;
  void Close() override;
  bool IsOpen() const override;

#ifdef WOTEX_MATTER_RESOURCE_TESTING
  std::string ResourceSnapshotForTesting();
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace wotex::matter

#endif
