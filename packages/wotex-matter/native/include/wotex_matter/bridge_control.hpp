#ifndef WOTEX_MATTER_BRIDGE_CONTROL_HPP
#define WOTEX_MATTER_BRIDGE_CONTROL_HPP

#include "wotex_matter/bridge_input.hpp"

namespace wotex::matter {

inline constexpr char kBridgeSdkRevision[] = "250a9e6c50ee2068107f3c4808b680f5f2925415";
inline constexpr char kBridgeModelSha256[] =
    "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671";

// The first process frame supplies the explicit generation. Exactly four
// scalar fields bind v=1, matter-bridge, open and 32 lowercase hex digits.
// Parse one line without LF, within the existing 512-byte control bound.
// Failure preserves the output. A generation/receipt grants no authentication.
BridgeResultDecode DecodeBridgeOpenFrame(std::string_view line,
                                         BridgeConsumerHandoff::Generation &generation) noexcept;

enum class BridgeControlReply { Ready, Closed };
enum class BridgeControlEncode { Encoded, Malformed, NoMemory };
// Includes LF. Ready adds only the exact selected revision and generated model;
// closed has the four base fields. Failure leaves output unchanged.
BridgeControlEncode EncodeBridgeControlReply(BridgeControlReply role,
                                             const BridgeConsumerHandoff::Generation &generation,
                                             std::string &output) noexcept;

} // namespace wotex::matter
#endif
