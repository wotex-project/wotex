#ifndef WOTEX_MATTER_COMMISSIONING_HPP
#define WOTEX_MATTER_COMMISSIONING_HPP

#include "wotex_matter/interaction.hpp"

#include <cstdint>
#include <optional>
#include <string>

namespace wotex::matter {

struct CommissioningError {
  std::string code;
  std::optional<std::uint32_t> sdk_status{};
  InteractionEffect effect{InteractionEffect::None};
};

struct CommissioningRequest {
  std::uint64_t node_id{0};
  std::uint32_t setup_pin{0};
  std::uint16_t discriminator{0};
  std::uint32_t timeout_ms{0};
};

struct CommissioningResponse {
  bool ok{false};
  std::optional<CommissioningError> error{};
  std::uint64_t node_id{0};
  std::uint64_t fabric_id{0};
  bool case_established{false};
};

struct CommissioningWindowRequest {
  std::uint64_t node_id{0};
  std::uint16_t timeout_s{0};
  std::uint32_t iteration_count{0};
  std::uint16_t discriminator{0};
  std::uint32_t timeout_ms{0};
};

struct CommissioningWindowResponse {
  bool ok{false};
  std::optional<CommissioningError> error{};
  std::uint64_t node_id{0};
  std::uint32_t setup_pin{0};
  std::uint16_t discriminator{0};
  std::uint16_t expires_in_s{0};
  std::string manual_code;
  std::string qr_code;
};

bool valid_setup_pin(std::uint32_t setup_pin);
bool valid_commissioning_request(const CommissioningRequest &request);
bool valid_commissioning_response(const CommissioningRequest &request,
                                  const CommissioningResponse &response);
bool valid_commissioning_window_request(
    const CommissioningWindowRequest &request);
bool valid_commissioning_window_response(
    const CommissioningWindowRequest &request,
    const CommissioningWindowResponse &response);

} // namespace wotex::matter

#endif
