#include "wotex_matter/commissioning.hpp"

#include <array>

namespace wotex::matter {
namespace {

constexpr std::uint64_t kMaximumOperationalNode = 0xFFFFFFEFFFFFFFFFULL;

bool ValidFailure(const std::optional<CommissioningError> &error) {
  return error.has_value() && !error->code.empty() && error->code.size() <= 64U;
}

bool RepeatedDigit(std::uint32_t setup_pin) {
  std::array<std::uint8_t, 8> digits{};
  for (std::size_t index = 0; index < digits.size(); ++index) {
    digits[index] = static_cast<std::uint8_t>(setup_pin % 10U);
    setup_pin /= 10U;
  }
  for (std::size_t index = 1; index < digits.size(); ++index) {
    if (digits[index] != digits[0]) {
      return false;
    }
  }
  return true;
}

} // namespace

bool valid_setup_pin(std::uint32_t setup_pin) {
  return setup_pin >= 1U && setup_pin <= 99999998U &&
      setup_pin != 12345678U && setup_pin != 87654321U &&
      !RepeatedDigit(setup_pin);
}

bool valid_commissioning_request(const CommissioningRequest &request) {
  return request.node_id >= 1U && request.node_id <= kMaximumOperationalNode &&
      valid_setup_pin(request.setup_pin) && request.discriminator <= 4095U &&
      request.timeout_ms >= 1U && request.timeout_ms <= 60000U;
}

bool valid_commissioning_response(const CommissioningRequest &request,
                                  const CommissioningResponse &response) {
  if (!response.ok) {
    return ValidFailure(response.error) && response.node_id == 0U &&
        response.fabric_id == 0U && !response.case_established;
  }
  return !response.error.has_value() && response.node_id == request.node_id &&
      response.fabric_id > 0U && response.case_established;
}

bool valid_commissioning_window_request(
    const CommissioningWindowRequest &request) {
  return request.node_id >= 1U && request.node_id <= kMaximumOperationalNode &&
      request.timeout_s >= 180U && request.timeout_s <= 900U &&
      request.iteration_count >= 1000U &&
      request.iteration_count <= 100000U && request.discriminator <= 4095U &&
      request.timeout_ms >= 1U && request.timeout_ms <= 60000U;
}

bool valid_commissioning_window_response(
    const CommissioningWindowRequest &request,
    const CommissioningWindowResponse &response) {
  if (!response.ok) {
    return ValidFailure(response.error) && response.node_id == 0U &&
        response.setup_pin == 0U && response.discriminator == 0U &&
        response.expires_in_s == 0U && response.manual_code.empty() &&
        response.qr_code.empty();
  }
  return !response.error.has_value() && response.node_id == request.node_id &&
      valid_setup_pin(response.setup_pin) &&
      response.discriminator == request.discriminator &&
      response.expires_in_s == request.timeout_s &&
      response.manual_code.size() >= 10U && response.manual_code.size() <= 21U &&
      response.qr_code.size() >= 4U && response.qr_code.size() <= 512U &&
      response.qr_code.rfind("MT:", 0) == 0U;
}

} // namespace wotex::matter
