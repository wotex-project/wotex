#include "wotex_matter/bridge_request_frame.hpp"
#include "wotex_matter/bridge_output.hpp"

#include <lib/core/TLVReader.h>
#include <nlohmann/json.hpp>
#include <new>

namespace wotex::matter {
namespace {
using Json = nlohmann::json;
using Encode = BridgeRequestEncode;
using RequestOperation = BridgeRequestMetadata::Operation;
using ListOperation = chip::app::ConcreteDataAttributePath::ListOperation;
static_assert(chip::kMaxSubjectCATAttributeCount == 3, "bridge request v1 carries three CAT slots");

std::string Hex(const std::uint8_t *bytes, std::size_t size) {
  constexpr char digits[] = "0123456789abcdef";
  std::string result;
  result.reserve(size * 2);
  for (std::size_t index = 0; index < size; ++index) {
    result += digits[bytes[index] >> 4];
    result += digits[bytes[index] & 15];
  }
  return result;
}
template <class Bytes> std::string Hex(const Bytes &bytes) {
  return Hex(reinterpret_cast<const std::uint8_t *>(bytes.data()), bytes.size());
}
bool SamePrincipal(const chip::Access::SubjectDescriptor &left,
                   const chip::Access::SubjectDescriptor &right) {
  return left.fabricIndex == right.fabricIndex && left.authMode == right.authMode &&
      left.subject == right.subject && left.cats.values == right.cats.values &&
      left.isCommissioning == right.isCommissioning;
}
bool Common(const BridgeConsumerHandoff::Ticket &ticket, const BridgeRequestMetadata &request,
            const BridgeFabricScope &fabric, std::uint64_t deadline_ms, std::string_view thing) {
  return ticket.id != 0 && deadline_ms != 0 && !thing.empty() && thing.size() <= 256 &&
      request.endpoint >= 3 && request.endpoint != chip::kInvalidEndpointId &&
      chip::IsValidClusterId(request.cluster) &&
      chip::IsValidFabricIndex(request.principal.fabricIndex) &&
      (request.principal.authMode == chip::Access::AuthMode::kCase ||
       request.principal.authMode == chip::Access::AuthMode::kGroup) &&
      SamePrincipal(request.principal, fabric.principal) && fabric.epoch != 0 &&
      fabric.fabric_id != 0 && chip::IsOperationalNodeId(fabric.bridge_node) && fabric.root[0] == 4;
}
bool NoList(const BridgeRequestMetadata &request) {
  return request.list_operation == ListOperation::NotList && request.list_index == 0;
}
bool WritePath(const BridgeRequestMetadata &request, const BridgeWriteScalar &value) {
  if (std::holds_alternative<std::uint16_t>(value))
    return (request.cluster == 3 && request.member == 0) ||
        (request.cluster == 6 && (request.member == 0x4001 || request.member == 0x4002));
  const auto *scalar = std::get_if<std::optional<std::uint8_t>>(&value);
  return scalar != nullptr && request.cluster == 6 && request.member == 0x4003 &&
      (!*scalar || **scalar <= 2);
}
Encode Arguments(const std::vector<std::uint8_t> &bytes) {
  using Owner = SdkBridgeInvokeContexts;
  if (bytes.size() > Owner::kMaximumArgumentsBytes) return Encode::Oversized;
  if (bytes.empty()) return Encode::Malformed;
  chip::TLV::TLVReader scan;
  scan.Init(bytes.data(), bytes.size());
  if (scan.Next() != CHIP_NO_ERROR || scan.GetType() != chip::TLV::kTLVType_Structure ||
      scan.GetTag() != chip::TLV::AnonymousTag())
    return Encode::Malformed;
  std::array<chip::TLV::TLVType, Owner::kMaximumArgumentDepth> containers{};
  std::size_t depth = 1, nodes = 1;
  if (scan.EnterContainer(containers[0]) != CHIP_NO_ERROR) return Encode::Malformed;
  while (depth != 0) {
    const auto error = scan.Next();
    if (error == CHIP_END_OF_TLV) {
      if (scan.ExitContainer(containers[--depth]) != CHIP_NO_ERROR) return Encode::Malformed;
    } else if (error != CHIP_NO_ERROR) return Encode::Malformed;
    else {
      if (++nodes > Owner::kMaximumArgumentNodes) return Encode::Oversized;
      const auto type = scan.GetType();
      if (type == chip::TLV::kTLVType_Structure || type == chip::TLV::kTLVType_Array ||
          type == chip::TLV::kTLVType_List) {
        if (depth == containers.size()) return Encode::Oversized;
        if (scan.EnterContainer(containers[depth++]) != CHIP_NO_ERROR) return Encode::Malformed;
      }
    }
  }
  return scan.GetLengthRead() == bytes.size() ? Encode::Encoded : Encode::Malformed;
}
Json Frame(const BridgeConsumerHandoff::Ticket &ticket, const BridgeRequestMetadata &request,
           const BridgeFabricScope &fabric, std::uint64_t deadline_ms, std::string_view thing,
           const char *operation, Json payload) {
  const auto &principal = request.principal;
  return {
      {"v", 1},
      {"backend", "matter-bridge"},
      {"type", "request"},
      {"generation", Hex(ticket.generation)},
      {"id", std::to_string(ticket.id)},
      {"deadline_ms", std::to_string(deadline_ms)},
      {"thing", Hex(thing)},
      {"operation", operation},
      {"path",
       {{"endpoint", request.endpoint}, {"cluster", request.cluster}, {"member", request.member}}},
      {"principal",
       {{"fabric_index", principal.fabricIndex},
        {"auth_mode", principal.authMode == chip::Access::AuthMode::kCase ? "case" : "group"},
        {"subject", std::to_string(principal.subject)},
        {"cats", principal.cats.values},
        {"is_commissioning", principal.isCommissioning}}},
      {"fabric_scope",
       {{"epoch", std::to_string(fabric.epoch)},
        {"fabric_id", std::to_string(fabric.fabric_id)},
        {"bridge_node", std::to_string(fabric.bridge_node)},
        {"root_public_key", Hex(fabric.root)},
        {"noc_sha256", Hex(fabric.noc_sha256)}}},
      {"flags",
       {{"expanded", request.expanded},
        {"timed", request.timed},
        {"fabric_filtered", request.fabric_filtered},
        {"allows_large_payload", request.allows_large_payload}}},
      {"list", {{"operation", "not-list"}, {"index", 0}}},
      {"data_version", request.data_version ? Json(*request.data_version) : Json(nullptr)},
      {"payload", std::move(payload)}};
}
Encode Finish(const Json &frame, std::string &result) {
  auto encoded = frame.dump();
  encoded += '\n';
  if (encoded.size() > BridgeOutputOwner::kMaximumRequestFrameBytes) return Encode::Oversized;
  result.swap(encoded);
  return Encode::Encoded;
}
}

BridgeRequestEncode EncodeBridgeReadFrame(const BridgeConsumerHandoff::Ticket &ticket,
                                          const BridgeRequestMetadata &request,
                                          const BridgeFabricScope &fabric,
                                          std::uint64_t deadline_ms, std::string_view thing,
                                          std::string &result) noexcept {
  if (request.operation != RequestOperation::Read ||
      !Common(ticket, request, fabric, deadline_ms, thing) ||
      !chip::IsValidAttributeId(request.member) || request.timed || !NoList(request) ||
      request.data_version)
    return Encode::Malformed;
  try {
    return Finish(Frame(ticket, request, fabric, deadline_ms, thing, "read", nullptr), result);
  } catch (const std::bad_alloc &) {
    return Encode::NoMemory;
  } catch (const Json::exception &) {
    return Encode::Malformed;
  }
}
BridgeRequestEncode EncodeBridgeWriteFrame(const BridgeAttributeWrite &write,
                                           const BridgeFabricScope &fabric, std::string_view thing,
                                           std::string &result) noexcept {
  const auto &request = write.request;
  if (request.operation != RequestOperation::Write ||
      !Common(write.ticket, request, fabric, write.deadline_ms, thing) || request.fabric_filtered ||
      request.allows_large_payload || !NoList(request) || !WritePath(request, write.value))
    return Encode::Malformed;
  try {
    Json payload;
    if (const auto *scalar = std::get_if<std::uint16_t>(&write.value))
      payload = {{"kind", "u16"}, {"value", *scalar}};
    else {
      const auto *value = std::get_if<std::optional<std::uint8_t>>(&write.value);
      if (value == nullptr) return Encode::Malformed;
      payload = {{"kind", "nullable_enum8"}, {"value", *value ? Json(**value) : Json(nullptr)}};
    }
    return Finish(
        Frame(write.ticket, request, fabric, write.deadline_ms, thing, "write", std::move(payload)),
        result);
  } catch (const std::bad_alloc &) {
    return Encode::NoMemory;
  } catch (const Json::exception &) {
    return Encode::Malformed;
  }
}
BridgeRequestEncode EncodeBridgeInvokeFrame(const BridgeInvocation &invocation,
                                            const BridgeFabricScope &fabric, std::string_view thing,
                                            std::string &result) noexcept {
  const auto &request = invocation.request;
  if (request.operation != RequestOperation::Invoke ||
      !Common(invocation.ticket, request, fabric, invocation.deadline_ms, thing) ||
      !chip::IsValidCommandId(request.member) || request.expanded || request.fabric_filtered ||
      request.allows_large_payload || !NoList(request) || request.data_version)
    return Encode::Malformed;
  const auto arguments = Arguments(invocation.arguments);
  if (arguments != Encode::Encoded) return arguments;
  try {
    return Finish(Frame(invocation.ticket, request, fabric, invocation.deadline_ms, thing, "invoke",
                        {{"kind", "tlv"}, {"value", Hex(invocation.arguments)}}),
                  result);
  } catch (const std::bad_alloc &) {
    return Encode::NoMemory;
  } catch (const Json::exception &) {
    return Encode::Malformed;
  }
}

} // namespace wotex::matter
