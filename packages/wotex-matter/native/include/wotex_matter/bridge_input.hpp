#ifndef WOTEX_MATTER_BRIDGE_INPUT_HPP
#define WOTEX_MATTER_BRIDGE_INPUT_HPP

#include "wotex_matter/bridge_handoff_owner.hpp"

#include <atomic>
#include <array>
#include <cstddef>
#include <string>
#include <string_view>

namespace wotex::matter {

inline constexpr std::size_t kMaximumBridgeResultFrameBytes = 512;

struct BridgeResultFrame {
  BridgeConsumerHandoff::Ticket ticket;
  BridgeConsumerHandoff::Outcome outcome{BridgeConsumerHandoff::Outcome::Unknown};
};
enum class BridgeResultDecode { Decoded, Malformed, Oversized, NoMemory };

struct BridgeInputFrame {
  enum class Kind { Result, ClockProbe, Close, Open };
  Kind kind{Kind::Result};
  BridgeResultFrame result;
};

// Results retain their exact six fields; clock-probe has exactly v, backend,
// type, generation and a nonzero canonical uint64 decimal id. Probe identities
// occupy a separate namespace. Close has only v, backend, type and generation;
// open belongs only to the first-frame decoder and is refused after bootstrap.
// All input is scalar-only and bounded to 512
// bytes including LF. Failure preserves output, and probes grant no authority.
BridgeResultDecode DecodeBridgeInputFrame(std::string_view line,
                                          const BridgeConsumerHandoff::Generation &generation,
                                          BridgeInputFrame &frame) noexcept;

// Encodes the exact six-field clock-sample control reply, including LF. Native
// milliseconds may be zero. Failure preserves output; clocks remain unqualified.
enum class BridgeClockEncode { Encoded, Malformed, NoMemory };
BridgeClockEncode EncodeBridgeClockSample(const BridgeConsumerHandoff::Generation &generation,
                                          std::uint64_t probe_id, std::uint64_t native_ms,
                                          std::string &output) noexcept;

// Parses one line without its LF. Exactly six scalar fields bind version 1,
// matter-bridge/result, the expected generation, canonical decimal identity and
// one consumer outcome. Failure leaves the output unchanged. Correlation grants
// neither policy authority nor evidence of SDK completion or a physical effect.
BridgeResultDecode DecodeBridgeResultFrame(std::string_view line,
                                           const BridgeConsumerHandoff::Generation &generation,
                                           BridgeResultFrame &result) noexcept;

// Explicit bounded notification port, called on the input thread after custody
// unlocks. Implementations must not block, acquire the SDK stack lock, retain
// borrowed values or throw. Ready may repeat for late results; an asynchronous
// SDK work owner must coalesce its notifications within the sixteen-slot bound.
// False closes input and custody. Closed never performs SDK cleanup itself.
class BridgeResultSink {
 public:
  virtual ~BridgeResultSink() = default;
  virtual bool Ready(const BridgeConsumerHandoff::Ticket &ticket) noexcept = 0;
  // Called after serialized clock sampling and custody unlock. Must copy a
  // bounded reply into reserved control capacity without SDK locking or I/O.
  // Refusal closes input/custody, including a full or failed control output.
  virtual bool ClockSample(const BridgeConsumerHandoff::Ticket &probe,
                           std::uint64_t native_ms) noexcept = 0;
  virtual void Closed() noexcept = 0;
};

// One serialized input owner, retaining only a fixed partial frame. The borrowed
// custody, clock and sink outlive it. EOF, malformed input, cancellation and
// notification failure close admission and wake synchronous waits without an
// SDK lock. The native SDK owner separately drains contexts before shutdown.
class BridgeResultInput final {
 public:
  enum class State {
    Open,
    Requested,
    Ended,
    Partial,
    Malformed,
    Oversized,
    NoMemory,
    Clock,
    Sink,
    Read,
    Cancelled
  };
  BridgeResultInput(BridgeHandoffOwner &owner, BridgeConsumerHandoff::Generation generation,
                    BridgeResultSink &sink);
  BridgeResultInput(const BridgeResultInput &) = delete;
  BridgeResultInput &operator=(const BridgeResultInput &) = delete;
  State Feed(std::string_view bytes);
  State End();

  // Borrows an exclusively owned input descriptor until return. Temporarily
  // enables nonblocking reads and restores its flags; caller closes it after
  // joining this reader. A caller-owned stop flag is checked every 50 ms poll,
  // so shutdown does not depend on closing a descriptor underneath a read.
  State Run(int descriptor, const std::atomic<bool> &stop);

 private:
  State Close(State state);
  BridgeHandoffOwner &owner_;
  const BridgeConsumerHandoff::Generation generation_;
  BridgeResultSink &sink_;
  std::array<char, kMaximumBridgeResultFrameBytes> buffer_{};
  std::size_t used_{0};
  std::uint64_t last_probe_id_{0};
  State state_{State::Open};
};

} // namespace wotex::matter

#endif
