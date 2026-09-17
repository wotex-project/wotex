#ifndef WOTEX_THREAD_STREAMS_HPP
#define WOTEX_THREAD_STREAMS_HPP

#include "flow.hpp"
#include "protocol.hpp"
#include <cstdint>
#include <functional>
#include <limits>
#include <map>
#include <string>
#include <utility>

namespace wotex::thread {
// Native State subscriptions over one report-flow owner. SDK callbacks only
// record changed flags; the event loop flushes at most one coalesced snapshot
// per iteration, with the OR of that iteration's flags, to every live stream.
// Snapshots contain no Dataset bytes or credentials. A stream whose bounded
// report queue overflows receives one terminal error frame and is retired;
// other streams and the session continue. Unknown flag bits remain numeric.
class StateStreams final {
 public:
  using Snapshot = std::function<Json()>;
  using Control = std::function<bool(const std::string &frame)>;
  // Serializes one State value; the software process-flow host pads it to an exact size.
  using ValueEncoder = std::function<std::string(const Json &value)>;

  StateStreams(ReportFlow &flow, Control control,
               ValueEncoder encoder = [](const Json &value) { return value.dump(); })
      : flow_(flow), control_(std::move(control)), encoder_(std::move(encoder)) {}

  // Registers a listener without reporting, so its registration reply can precede
  // the initial snapshot. Returns the stream generation, or zero at capacity.
  std::uint64_t open(const std::string &subscription, std::size_t queue_limit) {
    if (next_generation_ == std::numeric_limits<std::uint64_t>::max() ||
        !flow_.add_stream(subscription, next_generation_, queue_limit)) return 0;
    const std::uint64_t generation = next_generation_++;
    listeners_.emplace(Key{subscription, generation}, true);
    return generation;
  }

  // Submits one listener's initial snapshot with changed flags zero.
  void initial(const std::string &subscription, std::uint64_t generation, const Json &snapshot) {
    if (listeners_.count(Key{subscription, generation}) != 0) submit(Key{subscription, generation}, snapshot, 0);
  }

  void changed(std::uint32_t flags) { pending_ |= flags; }

  // Flushes the flags recorded since the previous flush. Flags observed while
  // no listener exists are discarded instead of being attributed to a later one.
  void flush(const Snapshot &snapshot) {
    const std::uint32_t flags = pending_;
    pending_ = 0;
    if (flags == 0 || listeners_.empty()) return;
    const Json value = snapshot();
    for (auto listener = listeners_.begin(); listener != listeners_.end();) {
      const Key key = (listener++)->first;
      submit(key, value, flags);
    }
  }

  // Explicit cancellation: one retirement barrier and no later report.
  bool remove(const std::string &subscription, std::uint64_t generation) {
    const auto listener = listeners_.find(Key{subscription, generation});
    if (listener == listeners_.end()) return false;
    listeners_.erase(listener);
    if (retire(Key{subscription, generation})) return true;
    failed_ = true;
    return false;
  }

  std::size_t size() const { return listeners_.size(); }
  std::size_t stream_errors() const { return stream_errors_; }
  std::size_t retirements() const { return retirements_; }
  bool failed() const { return failed_ || flow_.failed(); }
  std::uint32_t pending_flags() const { return pending_; }

 private:
  using Key = std::pair<std::string, std::uint64_t>;

  void submit(const Key &key, const Json &value, std::uint32_t flags) {
    const std::string session = flow_.session();
    // A queued report re-encodes later with its assigned sequence, so the encoder owns its values.
    const std::string tail = ",\"metadata\":{\"changed_flags\":" + std::to_string(flags) + "},\"value\":" + encoder_(value) + "}";
    const auto result = flow_.submit(key.first, key.second, [session, key, tail](std::uint64_t sequence) {
      std::string frame = Json{{"version", 1}, {"event", "state"}, {"session_generation", session},
                               {"subscription_id", key.first}, {"generation", key.second},
                               {"report_sequence", sequence}}.dump();
      frame.pop_back();
      return frame + tail;
    });
    if (result != ReportFlow::Submission::overflow) return;
    // Terminal loss: one error frame, then the stream's retirement barrier.
    listeners_.erase(key);
    const Json error = {{"version", 1}, {"event", "stream_error"}, {"session_generation", session},
                        {"subscription_id", key.first}, {"generation", key.second},
                        {"code", "queue_overflow"}};
    ++stream_errors_;
    if (!control_(error.dump()) || !retire(key)) failed_ = true;
  }

  bool retire(const Key &key) {
    const std::string session = flow_.session();
    ++retirements_;
    return flow_.retire(key.first, key.second, [&](std::uint64_t last) {
      return Json{{"version", 1}, {"event", "stream_retired"}, {"session_generation", session},
                  {"subscription_id", key.first}, {"generation", key.second},
                  {"last_report_sequence", last}}.dump();
    });
  }

  ReportFlow &flow_;
  Control control_;
  ValueEncoder encoder_;
  std::map<Key, bool> listeners_;
  std::size_t stream_errors_ = 0;
  std::size_t retirements_ = 0;
  std::uint64_t next_generation_ = 1;
  std::uint32_t pending_ = 0;
  bool failed_ = false;
};
}  // namespace wotex::thread
#endif
