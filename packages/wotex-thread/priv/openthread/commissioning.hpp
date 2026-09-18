#ifndef WOTEX_THREAD_COMMISSIONING_HPP
#define WOTEX_THREAD_COMMISSIONING_HPP

#include "protocol.hpp"
#include <openthread/commissioner.h>
#include <charconv>
#include <chrono>
#include <map>

namespace wotex::thread {
class CommissioningError final : public std::runtime_error {
 public:
  explicit CommissioningError(const char *code) : std::runtime_error(code) {}
};

struct JoinerIdentity {
  bool is_discerner = false;
  otExtAddress eui {};
  otJoinerDiscerner discerner {};
  std::string key;

  explicit JoinerIdentity(const Json &value) {
    if (!value.is_object() || !value.contains("type")) invalid();
    if (value.at("type") == "eui64") {
      if (!exact_keys(value, {"type", "value"}) || !value.at("value").is_string()) invalid();
      const auto &text = value.at("value").get_ref<const std::string &>();
      if (text.size() != 16) invalid();
      for (std::size_t index = 0; index < 8; ++index) {
        eui.m8[index] = static_cast<std::uint8_t>((hex(text[index * 2]) << 4) | hex(text[index * 2 + 1]));
      }
    } else if (value.at("type") == "discerner") {
      if (!exact_keys(value, {"type", "length", "value"}) || !value.at("length").is_number_integer() ||
          value.at("length") < 1 || value.at("length") > 64 || !value.at("value").is_string()) invalid();
      discerner.mLength = value.at("length").get<std::uint8_t>();
      const auto &text = value.at("value").get_ref<const std::string &>();
      if (text.empty() || text.size() > 20 || (text.size() > 1 && text.front() == '0')) invalid();
      for (char byte : text) if (byte < '0' || byte > '9') invalid();
      const auto parsed = std::from_chars(text.data(), text.data() + text.size(), discerner.mValue);
      if (parsed.ec != std::errc{} || parsed.ptr != text.data() + text.size() ||
          (discerner.mLength < 64 && discerner.mValue >= (std::uint64_t{1} << discerner.mLength))) invalid();
      is_discerner = true;
    } else { invalid(); }
    key = value.dump();
  }
 private:
  [[noreturn]] static void invalid() { throw CommissioningError("invalid_joiner_identity"); }
  static unsigned hex(char byte) {
    if (byte >= '0' && byte <= '9') return static_cast<unsigned>(byte - '0');
    if (byte >= 'A' && byte <= 'F') return static_cast<unsigned>(byte - 'A' + 10);
    invalid();
  }
};

inline bool valid_pskd(const Json &value) {
  if (!value.is_string()) return false;
  const auto &text = value.get_ref<const std::string &>();
  if (text.size() < 6 || text.size() > 32) return false;
  for (char byte : text) {
    if (!((byte >= '0' && byte <= '9') ||
          (byte >= 'A' && byte <= 'Y' && byte != 'I' && byte != 'O' && byte != 'Q'))) return false;
  }
  return true;
}

class Commissioning final {
 public:
  explicit Commissioning(otInstance *instance) : instance_(instance) {}
  Commissioning(const Commissioning &) = delete;
  Commissioning &operator=(const Commissioning &) = delete;

  void start() {
    if (owned_ || otCommissionerGetState(instance_) != OT_COMMISSIONER_STATE_DISABLED) {
      throw CommissioningError("busy");
    }
    const otError status = otCommissionerStart(instance_, commissioner_state, joiner_event, this);
    // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is thrown as a value; the host reports it as remote_error
    if (status != OT_ERROR_NONE) throw status;
    owned_ = true;
  }
  otCommissionerState observed_state() const { return observed_; }
  otCommissionerState state() const { return otCommissionerGetState(instance_); }
  void stop() {
    if (!owned_) {
      if (state() != OT_COMMISSIONER_STATE_DISABLED) throw CommissioningError("not_owned");
      admissions_.clear(); return;
    }
    const otError status = otCommissionerStop(instance_);
    // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is thrown as a value; the host reports it as remote_error
    if (status != OT_ERROR_NONE && status != OT_ERROR_ALREADY) throw status;
    owned_ = false;
    admissions_.clear();
  }
  void add(const Json &parameters) {
    if (!exact_keys(parameters, {"identity", "pskd", "lifetime"}) || !valid_pskd(parameters.at("pskd")) ||
        !parameters.at("lifetime").is_number_integer() || parameters.at("lifetime") < 1 ||
        parameters.at("lifetime") > 3600) throw CommissioningError("invalid_joiner_admission");
    JoinerIdentity identity(parameters.at("identity"));
    require_active();
    expire();
    if (admissions_.size() >= 64 && admissions_.count(identity.key) == 0) throw CommissioningError("busy");
    const auto lifetime = parameters.at("lifetime").get<std::uint32_t>();
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(lifetime);
    const auto &pskd = parameters.at("pskd").get_ref<const std::string &>();
    const otError status = identity.is_discerner
        ? otCommissionerAddJoinerWithDiscerner(instance_, &identity.discerner, pskd.c_str(), lifetime)
        : otCommissionerAddJoiner(instance_, &identity.eui, pskd.c_str(), lifetime);
    // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is thrown as a value; the host reports it as remote_error
    if (status != OT_ERROR_NONE) throw status;
    admissions_[identity.key] = deadline;
  }
  void remove(const Json &parameters) {
    if (!exact_keys(parameters, {"identity"})) throw ProtocolError();
    JoinerIdentity identity(parameters.at("identity"));
    require_active();
    const otError status = identity.is_discerner
        ? otCommissionerRemoveJoinerWithDiscerner(instance_, &identity.discerner)
        : otCommissionerRemoveJoiner(instance_, &identity.eui);
    // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is thrown as a value; the host reports it as remote_error
    if (status != OT_ERROR_NONE) throw status;
    admissions_.erase(identity.key);
  }
  void close() {
    if (owned_) (void)otCommissionerStop(instance_);
    owned_ = false;
    admissions_.clear();
  }
 private:
  void require_active() const {
    if (!owned_ || state() != OT_COMMISSIONER_STATE_ACTIVE) throw CommissioningError("invalid_state");
  }
  void expire() {
    const auto now = std::chrono::steady_clock::now();
    for (auto entry = admissions_.begin(); entry != admissions_.end();) {
      if (entry->second <= now) entry = admissions_.erase(entry); else ++entry;
    }
  }
  static void commissioner_state(otCommissionerState state, void *context) {
    auto *owner = static_cast<Commissioning *>(context);
    owner->observed_ = state;
    if (state == OT_COMMISSIONER_STATE_DISABLED) owner->admissions_.clear();
  }
  static void joiner_event(otCommissionerJoinerEvent event, const otJoinerInfo *info,
                           const otExtAddress *, void *context) {
    if (event != OT_COMMISSIONER_JOINER_REMOVED || info == nullptr) return;
    Json identity;
    if (info->mType == OT_JOINER_INFO_TYPE_EUI64) {
      std::string value;
      constexpr char digits[] = "0123456789ABCDEF";
      for (auto byte : info->mSharedId.mEui64.m8) { value += digits[byte >> 4]; value += digits[byte & 15]; }
      identity = {{"type", "eui64"}, {"value", value}};
    } else if (info->mType == OT_JOINER_INFO_TYPE_DISCERNER) {
      identity = {{"type", "discerner"}, {"length", info->mSharedId.mDiscerner.mLength},
                  {"value", std::to_string(info->mSharedId.mDiscerner.mValue)}};
    } else { return; }
    static_cast<Commissioning *>(context)->admissions_.erase(identity.dump());
  }
  otInstance *instance_;
  bool owned_ = false;
  otCommissionerState observed_ = OT_COMMISSIONER_STATE_DISABLED;
  std::map<std::string, std::chrono::steady_clock::time_point> admissions_;
};
}  // namespace wotex::thread
#endif
