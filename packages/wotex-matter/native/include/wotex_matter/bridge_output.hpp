#ifndef WOTEX_MATTER_BRIDGE_OUTPUT_HPP
#define WOTEX_MATTER_BRIDGE_OUTPUT_HPP

#include "wotex_matter/bridge_handoff_owner.hpp"

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace wotex::matter {

class BridgeOutputSink {
 public:
  virtual ~BridgeOutputSink() = default;
  // Called once after output admission and shared custody close. No output or
  // custody lock is held. Must not block, acquire the SDK stack lock or throw.
  // The SDK owner separately drains contexts and retires its resources.
  virtual void Closed() noexcept = 0;
};

// Explicit single-writer owner. SDK callbacks copy bounded frame bytes with
// try-lock admission; they never wait for output or perform descriptor I/O.
// Sixteen request slots and four reserved control slots include an active
// write until every byte is sent or discarded. Controls precede queued requests
// without interleaving an already started frame; each class preserves FIFO.
// The borrowed custody/clock/sink outlive every caller. Close and join every
// user before destruction; destruction with queued bytes or an active writer
// terminates the process. This owner neither encodes wire values nor authorizes
// dispatch. Request custody remains occupied until the SDK consumes its result.
class BridgeOutputOwner final {
 public:
  static constexpr std::size_t kRequestCapacity = 16, kControlCapacity = 4;
  static constexpr std::size_t kMaximumRequestFrameBytes = 262144;
  static constexpr std::size_t kMaximumControlFrameBytes = 512;
  static constexpr int kUnjoinedExit = 70;
  enum class Kind { Request, Control };
  enum class Admission { Accepted, Busy, Full, Malformed, Oversized, Closed, NoMemory, Exhausted };
  enum class State { Open, Ended, Cancelled, Write, AlreadyRunning };

  BridgeOutputOwner(BridgeHandoffOwner &custody, BridgeOutputSink &sink);
  ~BridgeOutputOwner();
  BridgeOutputOwner(const BridgeOutputOwner &) = delete;
  BridgeOutputOwner &operator=(const BridgeOutputOwner &) = delete;

  // Frame sizes include the required final LF; no other LF, CR or NUL is
  // allowed. The selected wire encoder owns JSON/schema/role validation.
  // Refusal retains no bytes; the SDK owner explicitly resolves or closes an
  // already admitted request rather than silently retrying or granting Success.
  Admission Push(Kind kind, std::string_view frame);
  // Close acquires shared custody after unlocking output; call it outside a
  // custody With callback. Push may run inside that callback.
  void Close();

  // Call explicitly on one owned writer thread with an exclusive pipe or stream
  // socket descriptor. Uses nonblocking writes, restores settable file status
  // flags and a 50 ms poll/idle-wait timeout.
  // Caller closes the descriptor after joining. The process owner arranges
  // SIGPIPE handling. Cancellation/read-side loss closes custody without an
  // SDK lock and discards queued frames; this operation does not flush on close.
  State Run(int descriptor, const std::atomic<bool> &stop);

 private:
  friend struct BridgeOutputOwnerTestAccess;
  enum class SlotState { Free, Queued, Writing };
  struct Slot {
    std::string frame;
    std::uint64_t identity{0};
    std::size_t bytes{0};
    SlotState state{SlotState::Free};
  };
  struct Pending {
    std::size_t slot;
    std::uint64_t identity;
    std::string frame;
  };
  std::optional<std::size_t> First(std::size_t begin, std::size_t end) const;
  std::optional<Pending> Take(const std::atomic<bool> &stop);
  void Release(Pending &pending);
  State End(State state);
  bool Closed();

  BridgeHandoffOwner &custody_;
  BridgeOutputSink &sink_;
  std::mutex mutex_;
  std::condition_variable changed_;
  std::array<Slot, kRequestCapacity + kControlCapacity> slots_;
  std::uint64_t next_{0};
  State state_{State::Open};
  bool running_{false};
};

} // namespace wotex::matter
#endif
