#ifndef WOTEX_MATTER_BRIDGE_WRITES_HPP
#define WOTEX_MATTER_BRIDGE_WRITES_HPP

#include "wotex_matter/bridge_requests.hpp"

#include <app/AttributeValueDecoder.h>

#include <variant>

namespace wotex::matter {

// The finite server profile accepts uint16 IdentifyTime, OnTime and OffWaitTime,
// or nullable StartUpOnOff (0 Off, 1 On, 2 Toggle). Values own their storage.
using BridgeWriteScalar = std::variant<std::uint16_t, std::optional<std::uint8_t>>;

struct BridgeAttributeWrite {
  BridgeConsumerHandoff::Ticket ticket;
  BridgeRequestMetadata request;
  std::uint64_t deadline_ms{0};
  BridgeWriteScalar value;
};

// Internal synchronous-write admission. The installed receiver must first
// establish a live compatible endpoint; the SDK owns path, ACL and data-version
// checks. Capture preserves the decoder's complete principal and copies only
// the four supported scalar attributes before reserving shared handoff custody.
// Call under the SDK stack lock and serialized custody ownership. Failure
// preserves result and acquires no slot. The caller must consume every admitted
// ticket at its original deadline before returning its SDK write response.
// Admission neither authorizes dispatch nor mutates approved/native state.
CHIP_ERROR StartBridgeWrite(BridgeConsumerHandoff &custody, BridgeRequestMetadata request,
                            chip::app::AttributeValueDecoder &decoder, std::uint64_t now_ms,
                            std::uint64_t deadline_ms, BridgeAttributeWrite &result);

} // namespace wotex::matter

#endif
