#ifndef WOTEX_MATTER_BRIDGE_SDK_RECEIVER_HPP
#define WOTEX_MATTER_BRIDGE_SDK_RECEIVER_HPP

#include "wotex_matter/bridge_sdk_process.hpp"

namespace wotex::matter {

// Internal installed-provider receiver. SDK callback principals are guarded
// against current fabric/ACL/metadata before payload/custody admission and
// completed rendering. Consumer policy is separately supplied through bounded
// request/result pipes. Construction starts no SDK, filesystem or thread work.
// The explicit native command renderer outlives this receiver; admission never
// selects a renderer or manufactures a Success response.
//
// Attach/Read/Write/Invoke/Finish hold the SDK lock. ResultReady only notifies
// bounded completion work, without that lock. Retire joins this work outside
// SDK locks before Finish. The receiver outlives joined SDK shutdown.
class SdkBridgeConsumerReceiver final : public BridgeSdkProcessReceiver {
 public:
  explicit SdkBridgeConsumerReceiver(BridgeInvokeReply &renderer);
  ~SdkBridgeConsumerReceiver() override;
  SdkBridgeConsumerReceiver(const SdkBridgeConsumerReceiver &) = delete;
  SdkBridgeConsumerReceiver &operator=(const SdkBridgeConsumerReceiver &) = delete;

  CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, BridgeConsumerHandoff &shared,
                    BridgeHandoffOwner &custody, BridgeOutputOwner &output,
                    SdkBridgeObservationOwner &observations) noexcept override;
  bool ResultReady(const BridgeConsumerHandoff::Ticket &ticket) noexcept override;
  bool Retire() noexcept override;
  CHIP_ERROR Finish() noexcept override;
  chip::app::DataModel::ActionReturnStatus Read(BridgeRequestMetadata request,
                                                chip::app::AttributeValueEncoder &encoder) override;
  chip::app::DataModel::ActionReturnStatus Write(
      BridgeRequestMetadata request, chip::app::AttributeValueDecoder &decoder) override;
  std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(
      BridgeRequestMetadata request, chip::TLV::TLVReader &arguments,
      chip::app::CommandHandler *handler) override;
  void ListNotification(const chip::app::ConcreteAttributePath &,
                        chip::app::DataModel::ListWriteOperation, chip::FabricIndex) override;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace wotex::matter
#endif
