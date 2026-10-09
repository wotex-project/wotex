#ifndef WOTEX_MATTER_BRIDGE_REQUESTS_HPP
#define WOTEX_MATTER_BRIDGE_REQUESTS_HPP

#include "wotex_matter/bridge_handoff.hpp"
#include "wotex_matter/interaction.hpp"

#include <app/CommandHandler.h>
#include <app/data-model-provider/OperationTypes.h>
#include <app/data-model-provider/MetadataTypes.h>
#include <crypto/CHIPCryptoPAL.h>

#include <array>
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

// Fixed, owned fabric identity. Public key and certificate digest distinguish
// a local fabric index from its current realm and operational credential.
struct BridgeFabricScope {
  chip::Access::SubjectDescriptor principal;
  std::uint64_t epoch{0};
  chip::FabricId fabric_id{0};
  chip::NodeId bridge_node{0};
  std::array<std::uint8_t, chip::Crypto::kP256_PublicKey_Length> root{};
  std::array<std::uint8_t, chip::Crypto::kSHA256_Hash_Length> noc_sha256{};
};

struct BridgeInvokeScope {
  BridgeRequestMetadata request;
  BridgeFabricScope fabric;
  chip::app::DataModel::AcceptedCommandEntry command;
};

// Mandatory SDK admission and delayed-rendering boundary. Capture owns its
// scope before payload copying or admission; Validate runs immediately before
// a completed renderer. Calls hold the SDK stack lock and must not wait,
// reenter custody or throw. This guard does not grant consumer authorization.
class BridgeInvokeGuard {
 public:
  virtual ~BridgeInvokeGuard() = default;
  virtual CHIP_ERROR Capture(const BridgeRequestMetadata &request,
                             BridgeInvokeScope &scope) noexcept = 0;
  virtual CHIP_ERROR Validate(const BridgeInvokeScope &scope) noexcept = 0;
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

// Internal SDK command context owner. Its required guard performs SDK path/ACL
// admission and delayed revalidation; consumer policy is separately owned. All methods run
// under the SDK stack lock and serialize access to the shared handoff. The
// handoff and guard outlive this owner. Close/drain before stopping the event loop and
// retiring SDK resources. Destruction with retained handles terminates the host.
class SdkBridgeInvokeContexts final {
 public:
  static constexpr std::size_t kMaximumArgumentsBytes = kMaximumEncodedTlvBytes;
  static constexpr std::size_t kMaximumArgumentDepth = 24;
  static constexpr std::size_t kMaximumArgumentNodes = 4096;

  SdkBridgeInvokeContexts(BridgeConsumerHandoff &handoff, BridgeInvokeGuard &guard);
  ~SdkBridgeInvokeContexts();
  SdkBridgeInvokeContexts(const SdkBridgeInvokeContexts &) = delete;
  SdkBridgeInvokeContexts &operator=(const SdkBridgeInvokeContexts &) = delete;

  CHIP_ERROR Start(const chip::app::DataModel::InvokeRequest &request,
                   chip::TLV::TLVReader &arguments, chip::app::CommandHandler &handler,
                   std::uint64_t now_ms, std::uint64_t deadline_ms,
                   BridgeConsumerHandoff::Ticket &ticket);
  CHIP_ERROR Request(const BridgeConsumerHandoff::Ticket &ticket,
                     BridgeInvocation &invocation) const;
  // Copies the fabric scope captured at admission, without sampling a later
  // fabric state. Failure preserves both outputs; neither copy grants policy.
  CHIP_ERROR Request(const BridgeConsumerHandoff::Ticket &ticket, BridgeInvocation &invocation,
                     BridgeFabricScope &fabric) const;
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
