#include "wotex_matter/interaction.hpp"

#include <algorithm>
#include <limits>

namespace wotex::matter {
namespace {

bool ValidCluster(std::uint32_t value) {
  return value <= 0x7FFFU ||
      (value >= 0x0001FC00U && value <= 0xFFF4FFFEU &&
       value % 65536U >= 0xFC00U && value % 65536U <= 0xFFFEU);
}

bool ValidSelector(const PathSelector &path, bool concrete) {
  if (path.fabric_id == 0 || path.node_id == 0 ||
      path.node_id > 0xFFFFFFEFFFFFFFFFULL) {
    return false;
  }
  if (concrete && (!path.endpoint.has_value() || !path.cluster.has_value() ||
                   !path.member.has_value())) {
    return false;
  }
  return (!path.endpoint.has_value() || *path.endpoint <= 0xFFFEU) &&
      (!path.cluster.has_value() || ValidCluster(*path.cluster)) &&
      (!path.member.has_value() || *path.member <= 0xFFFFFFFEU);
}

bool SamePath(const ConcretePath &left, const ConcretePath &right) {
  return left.fabric_id == right.fabric_id && left.node_id == right.node_id &&
      left.endpoint == right.endpoint && left.cluster == right.cluster &&
      left.member == right.member;
}

bool Selected(const PathSelector &selector, const ConcretePath &path) {
  return selector.fabric_id == path.fabric_id && selector.node_id == path.node_id &&
      (!selector.endpoint.has_value() || *selector.endpoint == path.endpoint) &&
      (!selector.cluster.has_value() || *selector.cluster == path.cluster) &&
      (!selector.member.has_value() || *selector.member == path.member);
}

bool ValidPathResult(const InteractionRequest &request, const PathResult &result) {
  if (std::none_of(request.paths.begin(), request.paths.end(),
                   [&result](const PathSelector &path) {
                     return Selected(path, result.path);
                   })) {
    return false;
  }
  const unsigned alternatives = static_cast<unsigned>(result.attribute.has_value()) +
      static_cast<unsigned>(result.event.has_value()) +
      static_cast<unsigned>(result.error.has_value());
  if (alternatives != 1U) {
    return false;
  }
  if (result.attribute.has_value()) {
    return request.kind != InteractionKind::ReadEvents &&
        SamePath(result.path, result.attribute->path) &&
        validate_element(MemberKind::Attribute, result.path.cluster,
                         result.path.member, Operation::Read,
                         result.attribute->value) == ConversionError::None;
  }
  if (result.event.has_value()) {
    return request.kind == InteractionKind::ReadEvents &&
        SamePath(result.path, result.event->path) &&
        validate_element(MemberKind::Event, result.path.cluster,
                         result.path.member, Operation::Read,
                         result.event->value) == ConversionError::None;
  }
  return !result.error->code.empty() &&
      result.error->effect == InteractionEffect::None;
}

} // namespace

bool valid_interaction_request(const InteractionRequest &request) {
  if (request.timeout_ms == 0 || request.timeout_ms > 60000 ||
      request.fabric_id == 0 || request.node_id == 0 ||
      request.node_id > 0xFFFFFFEFFFFFFFFFULL || request.paths.empty() ||
      request.paths.size() > kMaximumInteractionPaths) {
    return false;
  }
  const bool concrete = request.kind != InteractionKind::ReadAttributes;
  if (!std::all_of(request.paths.begin(), request.paths.end(),
                   [&](const PathSelector &path) {
                     return path.fabric_id == request.fabric_id &&
                         path.node_id == request.node_id &&
                         ValidSelector(path, concrete);
                   })) {
    return false;
  }
  const bool mutation = request.kind == InteractionKind::Write ||
      request.kind == InteractionKind::Invoke;
  if (mutation != request.value.has_value()) {
    return false;
  }
  if (request.expected_data_version.has_value() &&
      request.kind != InteractionKind::Write) {
    return false;
  }
  if (request.timed_request_timeout_ms.has_value() &&
      (!mutation || *request.timed_request_timeout_ms == 0 ||
       *request.timed_request_timeout_ms > request.timeout_ms)) {
    return false;
  }
  if (request.minimum_event_number.has_value() &&
      request.kind != InteractionKind::ReadEvents) {
    return false;
  }
  if (mutation) {
    const ConcretePath path{request.fabric_id, request.node_id,
                            *request.paths[0].endpoint,
                            *request.paths[0].cluster,
                            *request.paths[0].member};
    const MemberKind member_kind = request.kind == InteractionKind::Write
        ? MemberKind::Attribute
        : MemberKind::Command;
    const Operation operation = request.kind == InteractionKind::Write
        ? Operation::Write
        : Operation::Invoke;
    return request.paths.size() == 1 &&
        validate_element(member_kind, path.cluster, path.member, operation,
                         *request.value) == ConversionError::None;
  }
  return !request.value.has_value() &&
      !request.expected_data_version.has_value() &&
      !request.timed_request_timeout_ms.has_value();
}

bool valid_interaction_response(const InteractionRequest &request,
                                const InteractionResponse &response) {
  if (!response.ok) {
    return response.error.has_value() && !response.error->code.empty() &&
        response.results.empty() && !response.response_path.has_value() &&
        !response.response_value.has_value();
  }
  if (response.error.has_value() || response.results.size() >
          kMaximumInteractionReports) {
    return false;
  }
  if (request.kind == InteractionKind::ReadAttribute ||
      request.kind == InteractionKind::ReadAttributes ||
      request.kind == InteractionKind::ReadEvents) {
    const bool all_wildcard = request.kind == InteractionKind::ReadAttributes &&
        std::all_of(request.paths.begin(), request.paths.end(),
                    [](const PathSelector &path) {
                      return !path.endpoint.has_value() || !path.cluster.has_value() ||
                          !path.member.has_value();
                    });
    return (!response.results.empty() || all_wildcard) &&
        std::all_of(response.results.begin(), response.results.end(),
                    [&](const PathResult &result) {
                      return ValidPathResult(request, result);
                    });
  }
  if (request.kind == InteractionKind::Write) {
    return response.results.empty() && response.status == 0 &&
        response.response_path.has_value() &&
        !response.response_value.has_value();
  }
  return response.results.empty() && response.status == 0 &&
      (!response.response_value.has_value() || response.response_path.has_value());
}

std::uint32_t remaining_timeout_ms(std::uint32_t timeout_ms,
                                   std::uint64_t elapsed_ms) {
  if (elapsed_ms >= timeout_ms) {
    return 0;
  }
  return static_cast<std::uint32_t>(timeout_ms - elapsed_ms);
}

bool MutationCompletion::Submit() {
  unsigned char expected = 0;
  return state_.compare_exchange_strong(expected, 1);
}

bool MutationCompletion::Complete() {
  return (state_.fetch_or(2) & 2U) == 0;
}

bool MutationCompletion::Timeout() { return Complete(); }
bool MutationCompletion::completed() const { return (state_.load() & 2U) != 0; }
bool MutationCompletion::submitted() const { return (state_.load() & 1U) != 0; }

} // namespace wotex::matter
