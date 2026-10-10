#include "wotex_matter/bridge_observation.hpp"
#include <nlohmann/json.hpp>
#include <array>
#include <charconv>
#include <new>
#include <stdexcept>

namespace wotex::matter {
namespace {
std::string GenerationHex(const wotex::matter::BridgeConsumerHandoff::Generation &generation) {
  constexpr char hex[] = "0123456789abcdef";
  std::string value;
  for (const auto byte : generation) {
    value += hex[byte >> 4];
    value += hex[byte & 15];
  }
  return value;
}
class Sax final : public nlohmann::json_sax<nlohmann::json> {
 public:
  explicit Sax(const wotex::matter::BridgeConsumerHandoff::Generation &generation)
      : generation_(GenerationHex(generation)) {}
  bool key(string_t &key) override {
    if (!started_ || ended_ || pending_) return false;
    static constexpr std::array<std::string_view, 10> keys{
        "v",     "backend",  "type",      "generation", "id",
        "thing", "endpoint", "reachable", "on_off",     "temperature"};
    for (unsigned index = 0; index < keys.size(); ++index) {
      if (key != keys[index]) continue;
      const auto flag = 1U << index;
      if (seen_ & flag) return false;
      seen_ |= flag;
      field_ = static_cast<Field>(index);
      pending_ = true;
      return true;
    }
    return false;
  }
  bool null() override {
    if (!pending_ || (field_ != OnOff && field_ != Temperature)) return false;
    pending_ = false;
    return true;
  }
  bool boolean(bool value) override {
    if (!pending_) return false;
    if (field_ == Reachable) frame.value.reachable = value;
    else if (field_ == OnOff) frame.value.on_off = value;
    else return false;
    pending_ = false;
    return true;
  }
  bool number_integer(number_integer_t value) override {
    if (!pending_) return false;
    if (field_ == Version && value == 1) {
    } else if (field_ == Endpoint && value >= 3 && value <= 65534)
      frame.endpoint = static_cast<std::uint16_t>(value);
    else if (field_ == Temperature && value >= -32767 && value <= 32767)
      frame.value.temperature = static_cast<std::int16_t>(value);
    else return false;
    pending_ = false;
    return true;
  }
  bool number_unsigned(number_unsigned_t value) override {
    if (!pending_) return false;
    if (field_ == Version && value == 1) {
    } else if (field_ == Endpoint && value >= 3 && value <= 65534)
      frame.endpoint = static_cast<std::uint16_t>(value);
    else if (field_ == Temperature && value <= 32767)
      frame.value.temperature = static_cast<std::int16_t>(value);
    else return false;
    pending_ = false;
    return true;
  }
  bool string(string_t &value) override {
    if (!pending_) return false;
    switch (field_) {
    case Backend:
      if (value != "matter-bridge") return false;
      break;
    case Kind:
      if (value != "observation") return false;
      break;
    case Generation:
      if (value != generation_) return false;
      break;
    case Identity: {
      if (value.empty() || value.size() > 20 || value.front() == '0') return false;
      const auto parsed = std::from_chars(value.data(), value.data() + value.size(), frame.id);
      if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size() || frame.id == 0)
        return false;
      break;
    }
    case Thing: {
      if (value.empty() || value.size() > 512 || value.size() % 2 != 0) return false;
      const auto digit = [](char byte) -> int {
        if (byte >= '0' && byte <= '9') return byte - '0';
        if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
        return -1;
      };
      for (std::size_t index = 0; index < value.size(); index += 2) {
        const auto high = digit(value[index]), low = digit(value[index + 1]);
        if (high < 0 || low < 0) return false;
        frame.thing += static_cast<char>((high << 4) | low);
      }
      break;
    }
    default:
      return false;
    }
    pending_ = false;
    return true;
  }
  bool start_object(std::size_t) override {
    if (started_) return false;
    started_ = true;
    return true;
  }
  bool end_object() override {
    if (!started_ || ended_ || pending_ || seen_ != 1023) return false;
    ended_ = true;
    return true;
  }
  bool number_float(number_float_t, const string_t &) override { return false; }
  bool binary(binary_t &) override { return false; }
  bool start_array(std::size_t) override { return false; }
  bool end_array() override { return false; }
  bool parse_error(std::size_t, const std::string &, const nlohmann::detail::exception &) override {
    return false;
  }
  bool finished() const { return ended_ && !pending_; }
  BridgeObservationFrame frame;
 private:
  enum Field {
    Version,
    Backend,
    Kind,
    Generation,
    Identity,
    Thing,
    Endpoint,
    Reachable,
    OnOff,
    Temperature
  };
  const std::string generation_;
  Field field_{Version};
  unsigned seen_{0};
  bool started_{false}, ended_{false}, pending_{false};
};
} // namespace

BridgeObservationDecode DecodeBridgeObservationFrame(
    std::string_view frame, const BridgeConsumerHandoff::Generation &generation,
    BridgeObservationFrame &output) noexcept {
  using R = BridgeObservationDecode;
  if (frame.size() > kMaximumBridgeObservationFrameBytes) return R::Oversized;
  if (frame.empty() || frame.back() != '\n') return R::Malformed;
  const auto body = frame.substr(0, frame.size() - 1);
  if (body.find_first_of("\r\n") != body.npos || body.find('\0') != body.npos) return R::Malformed;
  try {
    Sax sax(generation);
    if (!nlohmann::json::sax_parse(body.begin(), body.end(), &sax) || !sax.finished())
      return R::Malformed;
    output = std::move(sax.frame);
    return R::Decoded;
  } catch (const std::bad_alloc &) {
    return R::NoMemory;
  } catch (const std::length_error &) {
    return R::NoMemory;
  }
}

BridgeObservationEncode EncodeBridgeObservationReceipt(
    const BridgeConsumerHandoff::Generation &generation, std::uint64_t id,
    BridgeObservationOutcome outcome, std::string &output) noexcept {
  using R = BridgeObservationEncode;
  if (id == 0 ||
      (outcome != BridgeObservationOutcome::Applied &&
       outcome != BridgeObservationOutcome::Refused))
    return R::Malformed;
  try {
    auto frame = "{\"v\":1,\"backend\":\"matter-bridge\",\"type\":\"observation-receipt\","
                 "\"generation\":\"" +
        GenerationHex(generation) + "\",\"id\":\"" + std::to_string(id) + "\",\"outcome\":\"" +
        (outcome == BridgeObservationOutcome::Applied ? "applied" : "refused") + "\"}\n";
    output.swap(frame);
    return R::Encoded;
  } catch (const std::bad_alloc &) {
    return R::NoMemory;
  } catch (const std::length_error &) {
    return R::NoMemory;
  }
}
} // namespace wotex::matter
