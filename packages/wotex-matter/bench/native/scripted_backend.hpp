// SPDX-License-Identifier: Apache-2.0
// The controller backend of the host benchmarks: it stands in for the
// connectedhomeip controller behind HostProtocol and answers as a node with an
// OnOff light and a thermostat on endpoint 1 and four Descriptor endpoints
// would, so the benchmarks measure the host's own framing, JSON, TLV and
// report handling and never the SDK.
#ifndef WOTEX_MATTER_BENCH_SCRIPTED_BACKEND_HPP
#define WOTEX_MATTER_BENCH_SCRIPTED_BACKEND_HPP

#include <cstdint>
#include <string>
#include <utility>

#include "wotex_matter/protocol.hpp"

namespace wotex::matter::bench {

inline constexpr std::uint64_t kFabric = 1;
inline constexpr std::uint64_t kNode = 0x1234;
inline constexpr std::uint16_t kEndpoints = 4;
inline constexpr char kSessionGeneration[] = "0123456789abcdef0123456789abcdef";

inline Element typed(ElementType type, std::uint64_t value = 0) {
  Element element;
  element.type = type;
  element.unsigned_value = value;
  return element;
}

inline Element tagged(ElementType type, std::uint8_t tag, std::uint64_t value = 0) {
  Element element = typed(type, value);
  element.tag = Tag{TagKind::Context, tag};
  return element;
}

// The value a node reports for one of the four Descriptor attributes.
inline Element descriptor_value(std::uint16_t endpoint, std::uint32_t member) {
  Element value = typed(ElementType::Array);
  if (member == 0) {
    Element entry = typed(ElementType::Structure);
    entry.children.push_back(tagged(ElementType::U32, 0, endpoint == 0 ? 0x0016 : 0x0100));
    entry.children.push_back(tagged(ElementType::U16, 1, 3));
    value.children.push_back(std::move(entry));
  } else if (member == 3) {
    if (endpoint == 0)
      for (std::uint16_t part = 1; part < kEndpoints; ++part)
        value.children.push_back(typed(ElementType::U16, part));
  } else {
    for (const std::uint64_t cluster : {0x0003U, 0x0004U, 0x0006U, 0x001DU, 0x0039U, 0x0201U})
      value.children.push_back(typed(ElementType::U32, cluster));
  }
  return value;
}

class ScriptedBackend final : public ControllerBackend {
 public:
  BackendResult Open(const NativeOpenOptions &) override {
    open_ = true;
    return {true, {}};
  }

  InteractionResponse Interact(const InteractionRequest &request) override {
    ++interactions;
    InteractionResponse response;
    response.ok = true;
    // HostProtocol passes only validated requests, which name at least one path.
    const PathSelector &first = request.paths.front();
    switch (request.kind) {
    case InteractionKind::ReadAttribute: {
      PathResult result;
      result.path = concrete(first);
      Element on = typed(ElementType::Boolean);
      on.boolean_value = true;
      result.attribute = AttributeData{result.path, std::move(on), 7U};
      response.results.push_back(std::move(result));
      break;
    }
    case InteractionKind::ReadAttributes:
      for (const PathSelector &selector : request.paths) {
        PathResult result;
        result.path = concrete(selector);
        result.attribute = AttributeData{
            result.path, descriptor_value(result.path.endpoint, result.path.member), 11U};
        response.results.push_back(std::move(result));
      }
      break;
    case InteractionKind::Write:
      response.response_path = concrete(first);
      break;
    case InteractionKind::Invoke:
    case InteractionKind::ReadEvents:
      break;
    }
    return response;
  }

  void SetSubscriptionSinks(ReportSink report, StatusSink status, FailureSink failure) override {
    report_sink = std::move(report);
    status_sink = std::move(status);
    failure_sink = std::move(failure);
  }

  SubscriptionResponse Subscribe(const SubscriptionRequest &request) override {
    SubscriptionResponse response;
    response.ok = true;
    response.subscription_id = request.subscription_id;
    response.generation = 1;
    response.min_interval_s = request.min_interval_s;
    response.max_interval_s = request.max_interval_s;
    response.sdk_subscription_id = 1;
    return response;
  }

  bool ActivateSubscription(const std::string &, std::uint64_t) override { return true; }

  BackendResult CancelSubscription(const std::string &, std::uint64_t, std::uint32_t) override {
    return {true, {}};
  }

  void Close() override { open_ = false; }
  bool IsOpen() const override { return open_; }

  std::uint64_t interactions{0};
  ReportSink report_sink;
  StatusSink status_sink;
  FailureSink failure_sink;

 private:
  static ConcretePath concrete(const PathSelector &selector) {
    return {selector.fabric_id, selector.node_id, selector.endpoint.value_or(0),
            selector.cluster.value_or(0), selector.member.value_or(0)};
  }

  bool open_{false};
};

// The JSON members of one concrete path in a request's parameters.
inline std::string path_members(std::uint16_t endpoint, std::uint32_t cluster,
                                std::uint32_t member) {
  return R"("fabric_id":)" + std::to_string(kFabric) + R"(,"node_id":)" + std::to_string(kNode) +
      R"(,"endpoint":)" + std::to_string(endpoint) + R"(,"cluster":)" + std::to_string(cluster) +
      R"(,"member":)" + std::to_string(member);
}

// A request line split around its id, which must grow with every request.
struct RequestLine {
  std::string head;
  std::string tail;

  std::string with_id(std::uint64_t id) const { return head + std::to_string(id) + tail; }
};

inline RequestLine request_line(const std::string &operation, const std::string &parameters) {
  return {R"({"version":1,"id":")",
          R"(","operation":")" + operation + R"(","parameters":{)" + parameters +
              R"(},"timeout_ms":30000})"};
}

inline std::string flow_open_line() {
  return std::string(R"({"version":1,"event":"flow_open","session_generation":")") +
      kSessionGeneration + R"("})";
}

// The open request of a controller with stored authority; the backend opens
// nothing, so the absolute paths only satisfy the host's validation.
inline std::string open_line() {
  return R"({"version":1,"id":"1","operation":"open","parameters":{"lifecycle":"persistent",)"
         R"("storage_path":"/var/lib/matter/controller","storage_mode":"open_existing",)"
         R"("authority":"stored","vendor_id":65521,"fabric_id":1,"controller_node_id":112233,)"
         R"("paa_trust_store":"/var/lib/matter/paa"},"timeout_ms":30000})";
}

inline bool succeeded(const ProcessResult &result) {
  return result.keep_running && result.frame &&
      result.frame->find(R"("ok":true)") != std::string::npos;
}

} // namespace wotex::matter::bench

#endif
