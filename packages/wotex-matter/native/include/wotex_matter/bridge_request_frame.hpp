#ifndef WOTEX_MATTER_BRIDGE_REQUEST_FRAME_HPP
#define WOTEX_MATTER_BRIDGE_REQUEST_FRAME_HPP

#include "wotex_matter/bridge_writes.hpp"

#include <string>
#include <string_view>

namespace wotex::matter {

enum class BridgeRequestEncode { Encoded, Malformed, Oversized, NoMemory };

// Encodes one version-1 matter-bridge/request frame, including LF, within the
// output owner's bound. The scope is an owned admission-time CASE/group fabric
// snapshot with the same complete principal as the request. Thing identities,
// public credential identifiers and invoke TLV use lowercase hex; uint64
// identities and native-clock deadlines use canonical decimal strings.
// Failure preserves output. These functions perform no clock, live context,
// fabric, ACL or consumer policy lookup and neither reserve nor release custody.
BridgeRequestEncode EncodeBridgeReadFrame(const BridgeConsumerHandoff::Ticket &ticket,
                                          const BridgeRequestMetadata &request,
                                          const BridgeFabricScope &fabric,
                                          std::uint64_t deadline_ms, std::string_view thing,
                                          std::string &result) noexcept;
BridgeRequestEncode EncodeBridgeWriteFrame(const BridgeAttributeWrite &write,
                                           const BridgeFabricScope &fabric, std::string_view thing,
                                           std::string &result) noexcept;
BridgeRequestEncode EncodeBridgeInvokeFrame(const BridgeInvocation &invocation,
                                            const BridgeFabricScope &fabric, std::string_view thing,
                                            std::string &result) noexcept;

} // namespace wotex::matter
#endif
