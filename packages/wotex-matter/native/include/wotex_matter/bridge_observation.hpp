#ifndef WOTEX_MATTER_BRIDGE_OBSERVATION_HPP
#define WOTEX_MATTER_BRIDGE_OBSERVATION_HPP

#include "wotex_matter/bridge_handoff.hpp"

#include <optional>
#include <string>
#include <string_view>

namespace wotex::matter {

// Explicit consumer-approved state, without command authority or an inferred
// physical effect. Temperature uses signed hundredths of a degree Celsius.
// Missing values remain unavailable; capability and identity checks belong to
// the endpoint owner before it applies any of this state.
struct BridgeObservation {
  bool reachable{false};
  std::optional<bool> on_off;
  std::optional<std::int16_t> temperature;
};

inline constexpr std::size_t kMaximumBridgeObservationFrameBytes = 1024;
struct BridgeObservationFrame {
  std::uint64_t id{0};
  std::string thing;
  std::uint16_t endpoint{0};
  BridgeObservation value;
};
enum class BridgeObservationDecode { Decoded, Malformed, Oversized, NoMemory };
enum class BridgeObservationEncode { Encoded, Malformed, NoMemory };
enum class BridgeObservationOutcome { Applied, Refused };

// Parses one complete LF-delimited ten-field scalar observation for an explicit
// process generation. Identities are canonical nonzero uint64 decimal strings;
// opaque Things use 1..256 bytes of lowercase hex and endpoints use 3..65534.
// Duplicate/missing/extra keys, nested values and malformed framing are refused.
// Failure preserves the caller's output. Parsing performs no SDK mutation,
// replay tracking, capability lookup, request resolution or authorization.
BridgeObservationDecode DecodeBridgeObservationFrame(
    std::string_view frame, const BridgeConsumerHandoff::Generation &generation,
    BridgeObservationFrame &output) noexcept;

// Exact six-field observation-receipt, including LF, within control capacity.
// The explicit SDK owner chooses Applied only after endpoint validation and
// state application. It means neither physical-effect evidence nor request
// completion. Failure preserves output; zero IDs and forged outcomes fail.
BridgeObservationEncode EncodeBridgeObservationReceipt(
    const BridgeConsumerHandoff::Generation &generation, std::uint64_t id,
    BridgeObservationOutcome outcome, std::string &output) noexcept;

} // namespace wotex::matter
#endif
