#ifndef WOTEX_MATTER_BRIDGE_ENDPOINT_MODEL_HPP
#define WOTEX_MATTER_BRIDGE_ENDPOINT_MODEL_HPP

#include "wotex_matter/storage.hpp"

#include <app/util/af-types.h>
#include <lib/support/Span.h>

namespace wotex::matter {

// Internal static metadata for an already validated finite Device Type. The
// SDK retains these arrays; their lifetime is the native process lifetime.
const EmberAfEndpointType &BridgeEndpointModel(BridgedDeviceType type);
chip::Span<const EmberAfDeviceType> BridgeEndpointDeviceTypes(BridgedDeviceType type);

} // namespace wotex::matter

#endif
