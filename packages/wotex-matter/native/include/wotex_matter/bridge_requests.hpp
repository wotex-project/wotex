#ifndef WOTEX_MATTER_BRIDGE_REQUESTS_HPP
#define WOTEX_MATTER_BRIDGE_REQUESTS_HPP

#include "wotex_matter/bridge_handoff.hpp"
#include "wotex_matter/interaction.hpp"

#include <app/CommandHandler.h>
#include <app/data-model-provider/OperationTypes.h>

#include <memory>
#include <vector>

namespace wotex::matter {

// An owned copy of callback metadata. An SDK OperationRequest itself borrows
// its SubjectDescriptor and must not be retained across the callback. Capture
// neither authenticates a supplied value nor grants consumer authorization.
struct BridgeRequestMetadata {
  enum class Operation { Read, Write, Invoke };
  Operation operation{Operation::Read};
  chip::Access::SubjectDescriptor principal;
  chip::EndpointId endpoint{chip::kInvalidEndpointId};
  chip::ClusterId cluster{chip::kInvalidClusterId};
  std::uint32_t member{0};
  bool expanded{false};
  bool timed{false};
  bool fabric_filtered{false};
  bool allows_large_payload{false};
  chip::app::ConcreteDataAttributePath::ListOperation list_operation{
      chip::app::ConcreteDataAttributePath::ListOperation::NotList};
  std::uint16_t list_index{0};
  std::optional<chip::DataVersion> data_version;
};

BridgeRequestMetadata CaptureBridgeRequest(
    const chip::app::DataModel::ReadAttributeRequest &request);
BridgeRequestMetadata CaptureBridgeRequest(
    const chip::app::DataModel::WriteAttributeRequest &request);
BridgeRequestMetadata CaptureBridgeRequest(const chip::app::DataModel::InvokeRequest &request);

struct BridgeInvocation {
  BridgeConsumerHandoff::Ticket ticket;
  BridgeRequestMetadata request;
  std::uint64_t deadline_ms{0};
  // Complete, owned command arguments with an anonymous Structure root.
  std::vector<std::uint8_t> arguments;
};

// A native, bounded response encoder for the selected command semantics. This
// callback runs on the SDK owner, never on the consumer or input-reader thread.
// It must not wait, reenter request admission, retain borrowed values or throw.
// A completed consumer result requires its explicit command-specific renderer;
// the context owner never converts queue admission into a Success response.
class BridgeInvokeReply {
 public:
  virtual ~BridgeInvokeReply() = default;
  virtual CHIP_ERROR Completed(chip::app::CommandHandler &handler,
                               const BridgeInvocation &invocation) noexcept = 0;
};

// Internal SDK command context owner. Its caller performs SDK path/ACL and
// consumer-policy admission at their respective boundaries. All methods run
// under the SDK stack lock and serialize access to the shared handoff. The
// handoff outlives this owner. Close/drain before stopping the event loop and
// retiring SDK resources. Destruction with retained handles terminates the host.
class SdkBridgeInvokeContexts final {
 public:
  static constexpr std::size_t kMaximumArgumentsBytes = kMaximumEncodedTlvBytes;
  static constexpr std::size_t kMaximumArgumentDepth = 24;
  static constexpr std::size_t kMaximumArgumentNodes = 4096;

  explicit SdkBridgeInvokeContexts(BridgeConsumerHandoff &handoff);
  ~SdkBridgeInvokeContexts();
  SdkBridgeInvokeContexts(const SdkBridgeInvokeContexts &) = delete;
  SdkBridgeInvokeContexts &operator=(const SdkBridgeInvokeContexts &) = delete;

  CHIP_ERROR Start(const chip::app::DataModel::InvokeRequest &request,
                   chip::TLV::TLVReader &arguments, chip::app::CommandHandler &handler,
                   std::uint64_t now_ms, std::uint64_t deadline_ms,
                   BridgeConsumerHandoff::Ticket &ticket);
  CHIP_ERROR Request(const BridgeConsumerHandoff::Ticket &ticket,
                     BridgeInvocation &invocation) const;
  CHIP_ERROR Respond(const BridgeConsumerHandoff::Ticket &ticket, std::uint64_t now_ms,
                     BridgeInvokeReply &reply);
  CHIP_ERROR Finish(std::uint64_t now_ms);
  std::size_t pending() const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace wotex::matter

#endif
