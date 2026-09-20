#ifndef WOTEX_THREAD_JOINER_HPP
#define WOTEX_THREAD_JOINER_HPP

#include "commissioning.hpp"
#include "protocol.hpp"
#include <openthread/dataset.h>
#include <openthread/joiner.h>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <string>

namespace wotex::thread {
class JoinerError final : public std::runtime_error {
 public:
  explicit JoinerError(const char *code) : std::runtime_error(code) {}
};

// Owns one live and one retired callback context. The pinned SDK clears the
// borrowed callback synchronously from otJoinerStop(), so an older retired
// context can be replaced without retaining an unbounded attempt history.
class JoinerOwner final {
 public:
  explicit JoinerOwner(otInstance *instance) : instance_(instance) {}
  JoinerOwner(const JoinerOwner &) = delete;
  JoinerOwner &operator=(const JoinerOwner &) = delete;

  void start(const Json &parameters) {
    validate(parameters);
    if (active_ || result_) throw JoinerError("busy");
    if (otDatasetIsCommissioned(instance_)) throw JoinerError("dataset_exists");
    if (generation_ == std::numeric_limits<std::uint64_t>::max()) throw JoinerError("busy");

    std::optional<otJoinerDiscerner> discerner;
    if (!parameters.at("discerner").is_null()) {
      try {
        JoinerIdentity identity(parameters.at("discerner"));
        if (!identity.is_discerner) throw JoinerError("invalid_joiner_config");
        discerner = identity.discerner;
      } catch (const CommissioningError &) {
        throw JoinerError("invalid_joiner_config");
      }
    }

    const otError identity_status = otJoinerSetDiscerner(instance_,
                                                         discerner ? &*discerner : nullptr);
    // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is reported as bounded remote_error data
    if (identity_status != OT_ERROR_NONE) throw identity_status;

    active_ = std::make_unique<Attempt>();
    active_->owner = this;
    active_->generation = ++generation_;

    const otError status = otJoinerStart(
        instance_, parameters.at("pskd").get_ref<const std::string &>().c_str(),
        optional_text(parameters.at("provisioning_url")),
        optional_text(parameters.at("vendor_name")), optional_text(parameters.at("vendor_model")),
        optional_text(parameters.at("vendor_sw_version")),
        optional_text(parameters.at("vendor_data")), completed, active_.get());
    if (status != OT_ERROR_NONE) {
      active_->retired = true;
      active_.reset();
      // NOLINTNEXTLINE(bugprone-std-exception-baseclass): the OpenThread status is reported as bounded remote_error data
      throw status;
    }
  }

  void stop() {
    if (!active_) return;
    active_->retired = true;
    otJoinerStop(instance_);
    retired_ = std::move(active_);
  }

  std::optional<otError> take_result() {
    if (!result_) return std::nullopt;
    const otError status = result_->status;
    result_.reset();
    return status;
  }

  void close() {
    stop();
    result_.reset();
  }

 private:
  struct Attempt {
    JoinerOwner *owner = nullptr;
    std::uint64_t generation = 0;
    bool retired = false;
  };
  struct Result {
    std::uint64_t generation;
    otError status;
  };

  static void completed(otError status, void *context) {
    auto *attempt = static_cast<Attempt *>(context);
    JoinerOwner *owner = attempt->owner;
    if (attempt->retired || owner->active_.get() != attempt ||
        owner->generation_ != attempt->generation)
      return;
    attempt->retired = true;
    owner->result_ = Result{attempt->generation, status};
    owner->retired_ = std::move(owner->active_);
  }

  static const char *optional_text(const Json &value) {
    return value.is_null() ? nullptr : value.get_ref<const std::string &>().c_str();
  }

  static bool optional_text_valid(const Json &value, std::size_t maximum) {
    if (value.is_null()) return true;
    if (!value.is_string()) return false;
    const auto &text = value.get_ref<const std::string &>();
    if (text.size() > maximum) return false;
    for (unsigned char byte : text)
      if (byte < 32 || byte == 127) return false;
    return true;
  }

  static void validate(const Json &parameters) {
    if (!exact_keys(parameters,
                    {"pskd", "discerner", "provisioning_url", "vendor_name", "vendor_model",
                     "vendor_sw_version", "vendor_data"}) ||
        !valid_pskd(parameters.at("pskd")) ||
        !optional_text_valid(parameters.at("provisioning_url"), 64) ||
        !optional_text_valid(parameters.at("vendor_name"), 32) ||
        !optional_text_valid(parameters.at("vendor_model"), 32) ||
        !optional_text_valid(parameters.at("vendor_sw_version"), 32) ||
        !optional_text_valid(parameters.at("vendor_data"), 64) ||
        !(parameters.at("discerner").is_null() || parameters.at("discerner").is_object())) {
      throw JoinerError("invalid_joiner_config");
    }
  }

  otInstance *instance_;
  std::uint64_t generation_ = 0;
  std::unique_ptr<Attempt> active_;
  std::unique_ptr<Attempt> retired_;
  std::optional<Result> result_;
};
} // namespace wotex::thread
#endif
