#include "wotex_matter/bridge_input.hpp"
#include "wotex_matter/bridge_control.hpp"
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
class InputSax final : public nlohmann::json_sax<nlohmann::json> {
 public:
  explicit InputSax(std::optional<BridgeConsumerHandoff::Generation> generation)
      : generation_(generation ? FrameGeneration(*generation) : ""), opening_(!generation) {
    if (generation) frame.result.ticket.generation = *generation;
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
      if (opening_) {
        if (value != "open") return false;
        frame.kind = BridgeInputFrame::Kind::Open;
      } else if (value == "result") frame.kind = BridgeInputFrame::Kind::Result;
      else if (value == "clock-probe") frame.kind = BridgeInputFrame::Kind::ClockProbe;
      else if (value == "close") frame.kind = BridgeInputFrame::Kind::Close;
      else return false;
      accepted = true;
      break;
    case Generation:
      if (opening_) {
        if (value.size() != 32) return false;
        for (std::size_t i = 0; i < 16; ++i) {
          const auto digit = [](char byte) -> int {
            if (byte >= '0' && byte <= '9') return byte - '0';
            if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
            return -1;
          };
          const auto high = digit(value[i * 2]), low = digit(value[i * 2 + 1]);
          if (high < 0 || low < 0) return false;
          frame.result.ticket.generation[i] = static_cast<std::uint8_t>((high << 4) | low);
        }
        accepted = true;
      } else {
        accepted = value == generation_;
      }
      break;
    case Identity: {
      if (value.empty() || value.size() > 20 || value[0] == '0') return false;
      const auto parsed = std::from_chars(value.data(), value.data() + value.size(),
                                          frame.result.ticket.id);
      accepted = parsed.ec == std::errc{} && parsed.ptr == value.data() + value.size() &&
          frame.result.ticket.id != 0;
      break;
    }
    case Outcome:
      if (value == "completed") frame.result.outcome = BridgeConsumerHandoff::Outcome::Completed;
      else if (value == "denied") frame.result.outcome = BridgeConsumerHandoff::Outcome::Denied;
      else if (value == "failed") frame.result.outcome = BridgeConsumerHandoff::Outcome::Failed;
      else if (value == "unknown") frame.result.outcome = BridgeConsumerHandoff::Outcome::Unknown;
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
    const auto required = frame.kind == BridgeInputFrame::Kind::Result ? 63u
        : frame.kind == BridgeInputFrame::Kind::ClockProbe             ? 31u
                                                                       : 15u;
    closed_ = started_ && !pending_ && seen_ == required;
    return closed_;
  }
  bool parse_error(std::size_t, const std::string &, const nlohmann::detail::exception &) override {
    return false;
  }
  bool finished() const { return closed_; }
  BridgeInputFrame frame;

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
  const bool opening_;
  Field field_{Version};
  unsigned seen_{0};
  bool pending_{false};
  bool started_{false};
  bool closed_{false};
};

} // namespace

BridgeResultDecode DecodeBridgeOpenFrame(std::string_view line,
                                         BridgeConsumerHandoff::Generation &generation) noexcept {
  if (line.size() >= kMaximumBridgeResultFrameBytes) return BridgeResultDecode::Oversized;
  if (line.empty() || line.find_first_of(std::string_view("\0\n\r", 3)) != std::string_view::npos)
    return BridgeResultDecode::Malformed;
  try {
    InputSax sax(std::nullopt);
    if (!nlohmann::json::sax_parse(line.begin(), line.end(), &sax) || !sax.finished())
      return BridgeResultDecode::Malformed;
    generation = sax.frame.result.ticket.generation;
    return BridgeResultDecode::Decoded;
  } catch (const std::bad_alloc &) {
    return BridgeResultDecode::NoMemory;
  }
}

BridgeControlEncode EncodeBridgeControlReply(BridgeControlReply role,
                                             const BridgeConsumerHandoff::Generation &generation,
                                             std::string &output) noexcept {
  if (role != BridgeControlReply::Ready && role != BridgeControlReply::Closed)
    return BridgeControlEncode::Malformed;
  try {
    std::string frame = "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"";
    frame += role == BridgeControlReply::Ready ? "ready" : "closed";
    frame += "\",\"generation\":\"" + FrameGeneration(generation) + "\"";
    if (role == BridgeControlReply::Ready)
      frame += std::string(",\"sdk_revision\":\"") + kBridgeSdkRevision + "\",\"model_sha256\":\"" +
          kBridgeModelSha256 + "\"";
    frame += "}\n";
    output = std::move(frame);
    return BridgeControlEncode::Encoded;
  } catch (const std::bad_alloc &) {
    return BridgeControlEncode::NoMemory;
  }
}

BridgeResultDecode DecodeBridgeInputFrame(std::string_view line,
                                          const BridgeConsumerHandoff::Generation &generation,
                                          BridgeInputFrame &frame) noexcept {
  if (line.size() >= kMaximumBridgeResultFrameBytes) return BridgeResultDecode::Oversized;
  if (line.empty() || line.find('\0') != std::string_view::npos ||
      line.find('\n') != std::string_view::npos || line.find('\r') != std::string_view::npos)
    return BridgeResultDecode::Malformed;
  try {
    InputSax sax(generation);
    if (!nlohmann::json::sax_parse(line.begin(), line.end(), &sax) || !sax.finished())
      return BridgeResultDecode::Malformed;
    frame = sax.frame;
    return BridgeResultDecode::Decoded;
  } catch (const std::bad_alloc &) {
    return BridgeResultDecode::NoMemory;
  }
}

BridgeResultDecode DecodeBridgeResultFrame(std::string_view line,
                                           const BridgeConsumerHandoff::Generation &generation,
                                           BridgeResultFrame &result) noexcept {
  BridgeInputFrame frame;
  const auto decoded = DecodeBridgeInputFrame(line, generation, frame);
  if (decoded != BridgeResultDecode::Decoded) return decoded;
  if (frame.kind != BridgeInputFrame::Kind::Result) return BridgeResultDecode::Malformed;
  result = frame.result;
  return BridgeResultDecode::Decoded;
}

BridgeClockEncode EncodeBridgeClockSample(const BridgeConsumerHandoff::Generation &generation,
                                          std::uint64_t probe_id, std::uint64_t native_ms,
                                          std::string &output) noexcept {
  if (probe_id == 0) return BridgeClockEncode::Malformed;
  try {
    std::string frame =
        "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"clock-sample\",\"generation\":\"";
    frame += FrameGeneration(generation);
    frame += "\",\"id\":\"";
    frame += std::to_string(probe_id);
    frame += "\",\"native_ms\":\"";
    frame += std::to_string(native_ms);
    frame += "\"}\n";
    output = std::move(frame);
    return BridgeClockEncode::Encoded;
  } catch (const std::bad_alloc &) {
    return BridgeClockEncode::NoMemory;
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
    BridgeInputFrame frame;
    const auto decoded = DecodeBridgeInputFrame(std::string_view(buffer_.data(), used_),
                                                generation_, frame);
    if (decoded != BridgeResultDecode::Decoded) {
      return Close(decoded == BridgeResultDecode::NoMemory        ? State::NoMemory
                       : decoded == BridgeResultDecode::Oversized ? State::Oversized
                                                                  : State::Malformed);
    }
    used_ = 0;
    const auto &parsed = frame.result;
    if (frame.kind == BridgeInputFrame::Kind::Close) {
      const auto sampled = owner_.With(
          [&](auto &custody, auto now) { return custody.Sample(generation_, now); });
      if (sampled == BridgeConsumerHandoff::ClockSample::InvalidGeneration)
        return Close(State::Malformed);
      if (sampled == BridgeConsumerHandoff::ClockSample::InvalidClock) return Close(State::Clock);
      return Close(State::Requested);
    }
    if (frame.kind == BridgeInputFrame::Kind::ClockProbe) {
      if (parsed.ticket.id <= last_probe_id_) return Close(State::Malformed);
      last_probe_id_ = parsed.ticket.id;
      std::uint64_t native_ms = 0;
      const auto sampled = owner_.With([&](auto &custody, auto now) {
        const auto status = custody.Sample(generation_, now);
        if (status == BridgeConsumerHandoff::ClockSample::Sampled) native_ms = now;
        return status;
      });
      using Sample = BridgeConsumerHandoff::ClockSample;
      switch (sampled) {
      case Sample::Sampled:
        if (!sink_.ClockSample(parsed.ticket, native_ms)) return Close(State::Sink);
        break;
      case Sample::InvalidGeneration:
        return Close(State::Malformed);
      case Sample::InvalidClock:
        return Close(State::Clock);
      case Sample::Closed:
        return Close(State::Ended);
      }
      continue;
    }
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
