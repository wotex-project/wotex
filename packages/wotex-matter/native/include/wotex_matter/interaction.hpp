#ifndef WOTEX_MATTER_INTERACTION_HPP
#define WOTEX_MATTER_INTERACTION_HPP

#include "wotex_matter/value.hpp"

#include <atomic>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace wotex::matter {

inline constexpr std::size_t kMaximumInteractionPaths = 64;
inline constexpr std::size_t kMaximumInteractionReports = 1024;
inline constexpr std::size_t kMaximumInteractionResultBytes = 98304;
inline constexpr std::size_t kMaximumEncodedTlvBytes = 65536;

enum class InteractionKind { ReadAttribute, ReadAttributes, ReadEvents, Write, Invoke };
enum class InteractionEffect { None, Unknown };

struct PathSelector {
  std::uint64_t fabric_id{0};
  std::uint64_t node_id{0};
  std::optional<std::uint16_t> endpoint{};
  std::optional<std::uint32_t> cluster{};
  std::optional<std::uint32_t> member{};
};

struct ConcretePath {
  std::uint64_t fabric_id{0};
  std::uint64_t node_id{0};
  std::uint16_t endpoint{0};
  std::uint32_t cluster{0};
  std::uint32_t member{0};
};

struct InteractionRequest {
  InteractionKind kind{InteractionKind::ReadAttribute};
  std::uint64_t fabric_id{0};
  std::uint64_t node_id{0};
  std::vector<PathSelector> paths{};
  std::optional<Element> value{};
  std::optional<std::uint32_t> expected_data_version{};
  std::optional<std::uint16_t> timed_request_timeout_ms{};
  std::optional<std::uint64_t> minimum_event_number{};
  std::uint32_t timeout_ms{0};
};

struct InteractionError {
  std::string code;
  std::optional<std::uint8_t> status{};
  std::optional<std::uint8_t> cluster_status{};
  InteractionEffect effect{InteractionEffect::None};
};

struct AttributeData {
  ConcretePath path{};
  Element value{};
  std::optional<std::uint32_t> data_version{};
};

struct EventData {
  ConcretePath path{};
  Element value{};
  std::uint64_t event_number{0};
  std::uint8_t priority{0};
  enum class TimestampKind { System, Epoch } timestamp_kind{TimestampKind::System};
  std::uint64_t timestamp_value{0};
};

struct PathResult {
  ConcretePath path{};
  std::optional<AttributeData> attribute{};
  std::optional<EventData> event{};
  std::optional<InteractionError> error{};
};

struct InteractionResponse {
  bool ok{false};
  std::optional<InteractionError> error{};
  std::vector<PathResult> results{};
  std::optional<ConcretePath> response_path{};
  std::optional<Element> response_value{};
  std::uint8_t status{0};
  std::optional<std::uint8_t> cluster_status{};
};

bool valid_interaction_request(const InteractionRequest &request);
bool valid_interaction_response(const InteractionRequest &request,
                                const InteractionResponse &response);
std::uint32_t remaining_timeout_ms(std::uint32_t timeout_ms,
                                   std::uint64_t elapsed_ms);

class MutationCompletion final {
 public:
  bool Submit();
  bool Complete();
  bool Timeout();
  bool completed() const;
 bool submitted() const;

 private:
  std::atomic<unsigned char> state_{0};
};

} // namespace wotex::matter

#endif
