#include "wotex_matter/bridge_input.hpp"
#include <nlohmann/json.hpp>
#include <charconv>
#include <new>
#include <cerrno>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <string>
#include <string_view>

namespace wotex::matter {
namespace {

std::string FrameGeneration(const BridgeConsumerHandoff::Generation &generation) {
  constexpr char digits[] = "0123456789abcdef";
  std::string output;
  output.reserve(32);
  for (const auto byte : generation) {
    output += digits[byte >> 4];
    output += digits[byte & 15];
  }
  return output;
}

// Scalar-only SAX parser: no DOM, recursive values or extra fields.
// Framing/correlation proves no authorization, SDK completion or physical effect.
class ResultSax final : public nlohmann::json_sax<nlohmann::json> {
 public:
  explicit ResultSax(BridgeConsumerHandoff::Generation generation)
      : generation_(FrameGeneration(generation)) {
    result.ticket.generation = generation;
  }
  bool null() override { return false; }
  bool boolean(bool) override { return false; }
  bool number_integer(number_integer_t) override { return false; }
  bool number_float(number_float_t, const string_t &) override { return false; }
  bool binary(binary_t &) override { return false; }
  bool start_array(std::size_t) override { return false; }
  bool end_array() override { return false; }
  bool number_unsigned(number_unsigned_t value) override {
    if (!pending_ || field_ != Version || value != 1) return false;
    pending_ = false;
    return true;
  }
  bool string(string_t &value) override {
    if (!pending_) return false;
    bool accepted = false;
    switch (field_) {
    case Backend:
      accepted = value == "matter-bridge";
      break;
    case Kind:
      accepted = value == "result";
      break;
    case Generation:
      accepted = value == generation_;
      break;
    case Identity: {
      if (value.empty() || value.size() > 20 || value[0] == '0') return false;
      const auto parsed = std::from_chars(value.data(), value.data() + value.size(),
                                          result.ticket.id);
      accepted = parsed.ec == std::errc{} && parsed.ptr == value.data() + value.size() &&
          result.ticket.id != 0;
      break;
    }
    case Outcome:
      if (value == "completed") result.outcome = BridgeConsumerHandoff::Outcome::Completed;
      else if (value == "denied") result.outcome = BridgeConsumerHandoff::Outcome::Denied;
      else if (value == "failed") result.outcome = BridgeConsumerHandoff::Outcome::Failed;
      else if (value == "unknown") result.outcome = BridgeConsumerHandoff::Outcome::Unknown;
      else return false;
      accepted = true;
      break;
    default:
      return false;
    }
    pending_ = false;
    return accepted;
  }
  bool start_object(std::size_t) override {
    if (started_) return false;
    started_ = true;
    return true;
  }
  bool key(string_t &key) override {
    if (!started_ || closed_ || pending_) return false;
    if (key == "v") field_ = Version;
    else if (key == "backend") field_ = Backend;
    else if (key == "type") field_ = Kind;
    else if (key == "generation") field_ = Generation;
    else if (key == "id") field_ = Identity;
    else if (key == "outcome") field_ = Outcome;
    else return false;
    if (seen_ & field_) return false;
    seen_ |= field_;
    pending_ = true;
    return true;
  }
  bool end_object() override {
    closed_ = started_ && !pending_ && seen_ == 63;
    return closed_;
  }
  bool parse_error(std::size_t, const std::string &, const nlohmann::detail::exception &) override {
    return false;
  }
  bool finished() const { return closed_; }
  BridgeResultFrame result;

 private:
  enum Field : unsigned {
    Version = 1,
    Backend = 2,
    Kind = 4,
    Generation = 8,
    Identity = 16,
    Outcome = 32
  };
  const std::string generation_;
  Field field_{Version};
  unsigned seen_{0};
  bool pending_{false};
  bool started_{false};
  bool closed_{false};
};

} // namespace

BridgeResultDecode DecodeBridgeResultFrame(std::string_view line,
                                           const BridgeConsumerHandoff::Generation &generation,
                                           BridgeResultFrame &result) noexcept {
  if (line.size() >= kMaximumBridgeResultFrameBytes) return BridgeResultDecode::Oversized;
  if (line.empty() || line.find('\0') != std::string_view::npos ||
      line.find('\n') != std::string_view::npos || line.find('\r') != std::string_view::npos)
    return BridgeResultDecode::Malformed;
  try {
    ResultSax sax(generation);
    if (!nlohmann::json::sax_parse(line.begin(), line.end(), &sax) || !sax.finished())
      return BridgeResultDecode::Malformed;
    result = sax.result;
    return BridgeResultDecode::Decoded;
  } catch (const std::bad_alloc &) {
    return BridgeResultDecode::NoMemory;
  }
}

BridgeResultInput::BridgeResultInput(BridgeHandoffOwner &owner,
                                     BridgeConsumerHandoff::Generation generation,
                                     BridgeResultSink &sink)
    : owner_(owner), generation_(generation), sink_(sink) {}

BridgeResultInput::State BridgeResultInput::Feed(std::string_view bytes) {
  if (state_ != State::Open) return state_;
  for (const char byte : bytes) {
    if (byte != '\n') {
      if (used_ == buffer_.size() - 1) return Close(State::Oversized);
      buffer_[used_++] = byte;
      continue;
    }
    BridgeResultFrame parsed;
    const auto decoded = DecodeBridgeResultFrame(std::string_view(buffer_.data(), used_),
                                                 generation_, parsed);
    if (decoded != BridgeResultDecode::Decoded) {
      return Close(decoded == BridgeResultDecode::NoMemory        ? State::NoMemory
                       : decoded == BridgeResultDecode::Oversized ? State::Oversized
                                                                  : State::Malformed);
    }
    used_ = 0;
    using Reply = BridgeConsumerHandoff::Reply;
    switch (owner_.Resolve(parsed.ticket, parsed.outcome)) {
    case Reply::Stored:
    case Reply::Late:
      if (!sink_.Ready(parsed.ticket)) return Close(State::Sink);
      break;
    case Reply::Duplicate:
    case Reply::UnknownTicket:
      break;
    case Reply::Closed:
      return Close(State::Ended);
    case Reply::InvalidClock:
      return Close(State::Clock);
    case Reply::InvalidOutcome:
      return Close(State::Malformed);
    }
  }
  return state_;
}
BridgeResultInput::State BridgeResultInput::Close(State state) {
  if (state_ != State::Open) return state_;
  owner_.Close();
  state_ = state;
  sink_.Closed();
  return state_;
}
BridgeResultInput::State BridgeResultInput::End() {
  return state_ == State::Open ? Close(used_ == 0 ? State::Ended : State::Partial) : state_;
}

BridgeResultInput::State BridgeResultInput::Run(int descriptor, const std::atomic<bool> &stop) {
  if (state_ != State::Open) return state_;
  const int flags = fcntl(descriptor, F_GETFL);
  if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != 0) return Close(State::Read);
  std::array<char, 128> chunk{};
  while (state_ == State::Open) {
    if (stop.load()) {
      Close(State::Cancelled);
      break;
    }
    pollfd incoming{descriptor, POLLIN, 0};
    const int ready = poll(&incoming, 1, 50);
    if (ready < 0 && errno == EINTR) continue;
    if (ready < 0 || (incoming.revents & (POLLERR | POLLNVAL))) {
      Close(State::Read);
      break;
    }
    if (ready == 0) continue;
    const auto count = read(descriptor, chunk.data(), chunk.size());
    if (count > 0) Feed(std::string_view(chunk.data(), static_cast<std::size_t>(count)));
    else if (count == 0) End();
    else if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) Close(State::Read);
  }
  if (fcntl(descriptor, F_SETFL, flags) != 0) state_ = State::Read;
  return state_;
}

} // namespace wotex::matter
