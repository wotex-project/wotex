#include "wotex_matter/protocol.hpp"
#include "wotex_matter/input.hpp"

#ifdef WOTEX_MATTER_FLOW_TESTING
#include "wotex_matter/flow_testing.hpp"
#endif

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <condition_variable>
#include <deque>
#include <limits>
#include <mutex>
#include <set>
#include <string_view>
#include <thread>
#include <vector>

namespace wotex::matter {
namespace {

using Json = nlohmann::json;

// JSON wrappers and child arrays are distinct from the eight-level TLV bound.
constexpr std::size_t kMaximumDepth = 24;
constexpr std::size_t kMaximumCollectionEntries = 1024;
constexpr std::size_t kMaximumNodes = 4096;
constexpr std::uint64_t kMaximumOperationalNode = 0xFFFFFFEFFFFFFFFFULL;

class BoundedSax final : public nlohmann::json_sax<Json> {
 public:
  bool null() override { return Value(); }
  bool boolean(bool) override { return Value(); }
  bool number_integer(number_integer_t) override { return Value(); }
  bool number_unsigned(number_unsigned_t) override { return Value(); }
  bool number_float(number_float_t, const string_t &) override {
    return Value();
  }
  bool string(string_t &) override { return Value(); }
  bool binary(binary_t &) override { return false; }

  bool start_object(std::size_t) override {
    return StartCollection(Collection::Object);
  }

  bool key(string_t &key) override {
    if (collections_.empty() || collections_.back() != Collection::Object ||
        ++counts_.back() > kMaximumCollectionEntries || ++nodes_ > kMaximumNodes) {
      return false;
    }
    return keys_.back().insert(key).second;
  }

  bool end_object() override { return EndCollection(Collection::Object); }

  bool start_array(std::size_t) override {
    return StartCollection(Collection::Array);
  }

  bool end_array() override { return EndCollection(Collection::Array); }

  bool parse_error(std::size_t, const std::string &,
                   const nlohmann::detail::exception &) override {
    return false;
  }

 private:
  enum class Collection { Object, Array };

  bool Value() {
    if (!collections_.empty() && collections_.back() == Collection::Array &&
        ++counts_.back() > kMaximumCollectionEntries) {
      return false;
    }
    return ++nodes_ <= kMaximumNodes;
  }

  bool StartCollection(Collection collection) {
    if (!Value() || collections_.size() + 1 > kMaximumDepth) {
      return false;
    }
    collections_.push_back(collection);
    counts_.push_back(0);
    keys_.emplace_back();
    return true;
  }

  bool EndCollection(Collection expected) {
    if (collections_.empty() || collections_.back() != expected) {
      return false;
    }
    collections_.pop_back();
    counts_.pop_back();
    keys_.pop_back();
    return true;
  }

  std::size_t nodes_{0};
  std::vector<Collection> collections_;
  std::vector<std::size_t> counts_;
  std::vector<std::set<std::string>> keys_;
};

bool ExactKeys(const Json &value, std::initializer_list<std::string_view> keys) {
  if (!value.is_object() || value.size() != keys.size()) {
    return false;
  }
  return std::all_of(keys.begin(), keys.end(), [&value](std::string_view key) {
    return value.contains(std::string(key));
  });
}

bool ParseBounded(const std::string &line, Json &document) {
  if (line.empty() || line.size() + 1 > kMaximumFrameBytes ||
      line.find('\0') != std::string::npos) {
    return false;
  }

  BoundedSax sax;
  if (!Json::sax_parse(line, &sax)) {
    return false;
  }

  document = Json::parse(line, nullptr, false, false);
  return !document.is_discarded();
}

bool CanonicalGeneration(const Json &value, std::string &generation) {
  if (!value.is_string()) {
    return false;
  }
  generation = value.get<std::string>();
  return generation.size() == 32 &&
      std::all_of(generation.begin(), generation.end(), [](unsigned char byte) {
        return std::isdigit(byte) != 0 || (byte >= 'a' && byte <= 'f');
      });
}

bool CanonicalSubscriptionId(const Json &value, std::string &identity) {
  return CanonicalGeneration(value, identity);
}

bool CanonicalRequestId(const Json &value, std::uint64_t &request_id) {
  if (!value.is_string()) {
    return false;
  }
  const std::string text = value.get<std::string>();
  if (text.empty() || text.front() == '0') {
    return false;
  }
  const auto result = std::from_chars(text.data(), text.data() + text.size(),
                                      request_id);
  return result.ec == std::errc{} && result.ptr == text.data() + text.size() &&
      request_id > 0;
}

bool ValidRequestEnvelope(const Json &request, std::uint64_t &request_id) {
  return ExactKeys(request,
                   {"version", "id", "operation", "parameters", "timeout_ms"}) &&
      request["version"].is_number_unsigned() &&
      request["version"].get<std::uint64_t>() == kProtocolVersion &&
      request["operation"].is_string() && request["parameters"].is_object() &&
      (CanonicalRequestId(request["id"], request_id) ||
       (request["id"] == "close" && request["operation"] == "close" &&
        request["parameters"].empty())) &&
      request["timeout_ms"].is_number_unsigned() &&
      request["timeout_ms"].get<std::uint64_t>() >= 1 &&
      request["timeout_ms"].get<std::uint64_t>() <= 60000;
}

bool AbsolutePath(const Json &value, std::string &path) {
  if (!value.is_string()) {
    return false;
  }
  path = value.get<std::string>();
  return !path.empty() && path.front() == '/' && path.find('\0') == std::string::npos;
}

bool OpenOptions(const Json &parameters, NativeOpenOptions &options) {
  if (!ExactKeys(parameters,
                 {"lifecycle", "storage_path", "storage_mode", "authority",
                  "vendor_id", "fabric_id", "controller_node_id",
                  "paa_trust_store"}) ||
      !parameters["lifecycle"].is_string() ||
      !parameters["storage_mode"].is_string() ||
      !parameters["authority"].is_string() ||
      !parameters["vendor_id"].is_number_unsigned() ||
      !parameters["fabric_id"].is_number_unsigned() ||
      !parameters["controller_node_id"].is_number_unsigned()) {
    return false;
  }

  options.lifecycle = parameters["lifecycle"].get<std::string>();
  options.storage_mode = parameters["storage_mode"].get<std::string>();
  options.authority = parameters["authority"].get<std::string>();
  const auto vendor = parameters["vendor_id"].get<std::uint64_t>();
  options.fabric_id = parameters["fabric_id"].get<std::uint64_t>();
  options.controller_node_id =
      parameters["controller_node_id"].get<std::uint64_t>();

  const bool mode =
      (options.storage_mode == "create_new" &&
       options.authority == "generate_root") ||
      (options.storage_mode == "open_existing" && options.authority == "stored");

  if (options.lifecycle != "persistent" || !mode || vendor == 0 ||
      vendor >= std::numeric_limits<std::uint16_t>::max() ||
      options.fabric_id == 0 || options.controller_node_id == 0 ||
      options.controller_node_id > kMaximumOperationalNode ||
      !AbsolutePath(parameters["storage_path"], options.storage_path) ||
      !AbsolutePath(parameters["paa_trust_store"], options.paa_trust_store)) {
    return false;
  }
  options.vendor_id = static_cast<std::uint16_t>(vendor);
  return true;
}

bool Unsigned(const Json &value, std::uint64_t maximum, std::uint64_t &result) {
  if (!value.is_number_unsigned()) {
    return false;
  }
  result = value.get<std::uint64_t>();
  return result <= maximum;
}

bool PathComponent(const Json &value, std::uint64_t maximum,
                   std::optional<std::uint64_t> &result) {
  if (value.is_string() && value.get<std::string>() == "any") {
    result.reset();
    return true;
  }
  std::uint64_t parsed = 0;
  if (!Unsigned(value, maximum, parsed)) {
    return false;
  }
  result = parsed;
  return true;
}

bool ValidCluster(std::uint32_t value) {
  return value <= 0x7FFFU ||
      (value >= 0x0001FC00U && value <= 0xFFF4FFFEU &&
       value % 65536U >= 0xFC00U && value % 65536U <= 0xFFFEU);
}

bool Selector(const Json &value, bool wildcards, PathSelector &result) {
  if (!ExactKeys(value, {"fabric_id", "node_id", "endpoint", "cluster", "member"}) ||
      !Unsigned(value["fabric_id"], std::numeric_limits<std::uint64_t>::max(),
                result.fabric_id) ||
      !Unsigned(value["node_id"], kMaximumOperationalNode, result.node_id) ||
      result.fabric_id == 0 || result.node_id == 0) {
    return false;
  }
  std::optional<std::uint64_t> endpoint;
  std::optional<std::uint64_t> cluster;
  std::optional<std::uint64_t> member;
  if (!PathComponent(value["endpoint"], 0xFFFEU, endpoint) ||
      !PathComponent(value["cluster"], 0xFFF4FFFEU, cluster) ||
      !PathComponent(value["member"], 0xFFFFFFFEU, member) ||
      (!wildcards && (!endpoint || !cluster || !member)) ||
      (cluster && !ValidCluster(static_cast<std::uint32_t>(*cluster)))) {
    return false;
  }
  if (endpoint) {
    result.endpoint = static_cast<std::uint16_t>(*endpoint);
  }
  if (cluster) {
    result.cluster = static_cast<std::uint32_t>(*cluster);
  }
  if (member) {
    result.member = static_cast<std::uint32_t>(*member);
  }
  return true;
}

bool TagValue(const Json &value, Tag &tag) {
  if (value.is_string() && value.get<std::string>() == "anonymous") {
    tag = Tag{TagKind::Anonymous, 0};
    return true;
  }
  if (value.is_array() && value.size() == 2 && value[0].is_string() &&
      value[0].get<std::string>() == "context" &&
      value[1].is_number_unsigned() && value[1].get<std::uint64_t>() <= 255) {
    tag = Tag{TagKind::Context,
              static_cast<std::uint8_t>(value[1].get<std::uint64_t>())};
    return true;
  }
  return false;
}

bool ElementValue(const Json &value, Element &result, std::size_t depth = 0,
                  std::size_t *nodes = nullptr) {
  std::size_t local_nodes = 0;
  if (nodes == nullptr) {
    nodes = &local_nodes;
  }
  if (++*nodes > 1024 || depth > 8 ||
      !ExactKeys(value, {"tag", "type", "value"}) ||
      !TagValue(value["tag"], result.tag) || !value["type"].is_string()) {
    return false;
  }
  const std::string type = value["type"].get<std::string>();
  const Json &body = value["value"];
  if (type == "null" && body.is_null()) {
    result.type = ElementType::Null;
    return true;
  }
  if (type == "i16" && body.is_number_integer()) {
    const auto integer = body.get<std::int64_t>();
    if (integer < std::numeric_limits<std::int16_t>::min() ||
        integer > std::numeric_limits<std::int16_t>::max()) {
      return false;
    }
    result.type = ElementType::I16;
    result.signed_value = integer;
    return true;
  }
  if ((type == "u8" || type == "u16" || type == "u32" || type == "u64") &&
      body.is_number_unsigned()) {
    const auto integer = body.get<std::uint64_t>();
    const std::uint64_t maximum = type == "u8" ? 0xFFU :
        (type == "u16" ? 0xFFFFU :
         (type == "u32" ? 0xFFFFFFFFULL :
          std::numeric_limits<std::uint64_t>::max()));
    if (integer > maximum) {
      return false;
    }
    result.type = type == "u8" ? ElementType::U8
        : (type == "u16" ? ElementType::U16
                         : (type == "u32" ? ElementType::U32
                                          : ElementType::U64));
    result.unsigned_value = integer;
    return true;
  }
  if (type == "boolean" && body.is_boolean()) {
    result.type = ElementType::Boolean;
    result.boolean_value = body.get<bool>();
    return true;
  }
  if ((type == "structure" || type == "array") && body.is_array() &&
      body.size() <= 1023) {
    result.type = type == "structure" ? ElementType::Structure : ElementType::Array;
    for (const Json &child : body) {
      Element parsed;
      if (!ElementValue(child, parsed, depth + 1, nodes)) {
        return false;
      }
      result.children.push_back(std::move(parsed));
    }
    return true;
  }
  return false;
}

bool OptionalUint(const Json &parameters, std::string_view key,
                  std::uint64_t maximum, std::optional<std::uint64_t> &result) {
  const auto iterator = parameters.find(std::string(key));
  if (iterator == parameters.end()) {
    result.reset();
    return true;
  }
  std::uint64_t parsed = 0;
  if (!Unsigned(*iterator, maximum, parsed)) {
    return false;
  }
  result = parsed;
  return true;
}

bool InteractionParameters(const std::string &operation, const Json &parameters,
                           std::uint32_t timeout_ms, InteractionRequest &result) {
  const bool single = operation == "read" || operation == "write" ||
      operation == "invoke";
  const bool paths = operation == "read_paths" || operation == "read_events";
  if (!single && !paths) {
    return false;
  }
  result.timeout_ms = timeout_ms;
  result.kind = operation == "read" ? InteractionKind::ReadAttribute
      : operation == "read_paths" ? InteractionKind::ReadAttributes
      : operation == "read_events" ? InteractionKind::ReadEvents
      : operation == "write" ? InteractionKind::Write
      : InteractionKind::Invoke;

  if (single) {
    Json path;
    for (std::string_view key : {"fabric_id", "node_id", "endpoint", "cluster", "member"}) {
      if (!parameters.contains(std::string(key))) {
        return false;
      }
      path[std::string(key)] = parameters[std::string(key)];
    }
    PathSelector selector;
    if (!Selector(path, false, selector)) {
      return false;
    }
    result.paths.push_back(selector);
  } else {
    if (!parameters.contains("paths") || !parameters["paths"].is_array() ||
        parameters["paths"].empty() ||
        parameters["paths"].size() > kMaximumInteractionPaths) {
      return false;
    }
    for (const Json &path : parameters["paths"]) {
      PathSelector selector;
      if (!Selector(path, operation == "read_paths", selector)) {
        return false;
      }
      result.paths.push_back(std::move(selector));
    }
  }
  result.fabric_id = result.paths.front().fabric_id;
  result.node_id = result.paths.front().node_id;

  std::optional<std::uint64_t> expected;
  std::optional<std::uint64_t> timed;
  std::optional<std::uint64_t> minimum_event;
  if (!OptionalUint(parameters, "expected_data_version", 0xFFFFFFFFU, expected) ||
      !OptionalUint(parameters, "timed_request_timeout_ms", 65535, timed) ||
      !OptionalUint(parameters, "min_event_number",
                    std::numeric_limits<std::uint64_t>::max(), minimum_event)) {
    return false;
  }
  if (expected) {
    result.expected_data_version = static_cast<std::uint32_t>(*expected);
  }
  if (timed && *timed > 0) {
    result.timed_request_timeout_ms = static_cast<std::uint16_t>(*timed);
  } else if (timed) {
    return false;
  }
  result.minimum_event_number = minimum_event;
  if (operation == "write" || operation == "invoke") {
    if (!parameters.contains("value")) {
      return false;
    }
    Element element;
    if (!ElementValue(parameters["value"], element)) {
      return false;
    }
    result.value = std::move(element);
  }

  const std::size_t expected_keys = single ? 5U : 1U;
  const std::size_t option_keys = static_cast<std::size_t>(parameters.contains("value")) +
      static_cast<std::size_t>(parameters.contains("expected_data_version")) +
      static_cast<std::size_t>(parameters.contains("timed_request_timeout_ms")) +
      static_cast<std::size_t>(parameters.contains("min_event_number"));
  return parameters.size() == expected_keys + option_keys &&
      valid_interaction_request(result);
}

bool SubscriptionParameters(const Json &parameters, std::uint32_t timeout_ms,
                            SubscriptionRequest &result) {
  if (!ExactKeys(parameters,
                 {"subscription_id", "kind", "paths", "min_interval_s",
                  "max_interval_s", "resubscribe", "queue_limit"}) ||
      !CanonicalSubscriptionId(parameters["subscription_id"],
                               result.subscription_id) ||
      !parameters["kind"].is_string() || !parameters["paths"].is_array() ||
      parameters["paths"].empty() || parameters["paths"].size() > 64 ||
      !parameters["resubscribe"].is_boolean()) {
    return false;
  }
  const std::string kind = parameters["kind"].get<std::string>();
  if (kind == "attribute") {
    result.kind = SubscriptionKind::Attribute;
  } else if (kind == "event") {
    result.kind = SubscriptionKind::Event;
  } else {
    return false;
  }
  std::uint64_t minimum = 0;
  std::uint64_t maximum = 0;
  std::uint64_t queue_limit = 0;
  if (!Unsigned(parameters["min_interval_s"], 65535, minimum) ||
      !Unsigned(parameters["max_interval_s"], 65535, maximum) || maximum == 0 ||
      !Unsigned(parameters["queue_limit"], 10000, queue_limit) || queue_limit == 0) {
    return false;
  }
  for (const Json &path : parameters["paths"]) {
    PathSelector selector;
    if (!Selector(path, false, selector)) {
      return false;
    }
    result.paths.push_back(std::move(selector));
  }
  result.fabric_id = result.paths.front().fabric_id;
  result.node_id = result.paths.front().node_id;
  result.min_interval_s = static_cast<std::uint16_t>(minimum);
  result.max_interval_s = static_cast<std::uint16_t>(maximum);
  result.resubscribe = parameters["resubscribe"].get<bool>();
  result.queue_limit = static_cast<std::uint16_t>(queue_limit);
  result.timeout_ms = timeout_ms;
  return valid_subscription_request(result);
}

bool UnsubscribeParameters(const Json &parameters, std::string &subscription_id,
                           std::uint64_t &generation) {
  return ExactKeys(parameters, {"subscription_id", "generation"}) &&
      CanonicalSubscriptionId(parameters["subscription_id"], subscription_id) &&
      Unsigned(parameters["generation"],
               std::numeric_limits<std::uint64_t>::max(), generation) &&
      generation > 0;
}

bool CommissioningParameters(const Json &parameters, std::uint32_t timeout_ms,
                             CommissioningRequest &result) {
  std::uint64_t setup_pin = 0;
  std::uint64_t discriminator = 0;
  if (!ExactKeys(parameters, {"node_id", "setup_pin", "discriminator"}) ||
      !Unsigned(parameters["node_id"], kMaximumOperationalNode,
                result.node_id) ||
      !Unsigned(parameters["setup_pin"], 99999998U, setup_pin) ||
      !Unsigned(parameters["discriminator"], 4095U, discriminator)) {
    return false;
  }
  result.setup_pin = static_cast<std::uint32_t>(setup_pin);
  result.discriminator = static_cast<std::uint16_t>(discriminator);
  result.timeout_ms = timeout_ms;
  return valid_commissioning_request(result);
}

bool CommissioningWindowParameters(const Json &parameters,
                                   std::uint32_t timeout_ms,
                                   CommissioningWindowRequest &result) {
  std::uint64_t timeout_s = 0;
  std::uint64_t iteration_count = 0;
  std::uint64_t discriminator = 0;
  if (!ExactKeys(parameters,
                 {"node_id", "timeout_s", "iteration_count", "discriminator"}) ||
      !Unsigned(parameters["node_id"], kMaximumOperationalNode,
                result.node_id) ||
      !Unsigned(parameters["timeout_s"], 900U, timeout_s) ||
      !Unsigned(parameters["iteration_count"], 100000U, iteration_count) ||
      !Unsigned(parameters["discriminator"], 4095U, discriminator)) {
    return false;
  }
  result.timeout_s = static_cast<std::uint16_t>(timeout_s);
  result.iteration_count = static_cast<std::uint32_t>(iteration_count);
  result.discriminator = static_cast<std::uint16_t>(discriminator);
  result.timeout_ms = timeout_ms;
  return valid_commissioning_window_request(result);
}

Json PathJson(const ConcretePath &path) {
  return {{"fabric_id", path.fabric_id}, {"node_id", path.node_id},
          {"endpoint", path.endpoint}, {"cluster", path.cluster},
          {"member", path.member}};
}

Json ElementJson(const Element &element) {
  Json tag = element.tag.kind == TagKind::Anonymous
      ? Json("anonymous")
      : Json::array({"context", element.tag.id});
  Json value;
  std::string_view type;
  switch (element.type) {
  case ElementType::Null: type = "null"; value = nullptr; break;
  case ElementType::I16: type = "i16"; value = element.signed_value; break;
  case ElementType::U8: type = "u8"; value = element.unsigned_value; break;
  case ElementType::U16: type = "u16"; value = element.unsigned_value; break;
  case ElementType::U32: type = "u32"; value = element.unsigned_value; break;
  case ElementType::U64: type = "u64"; value = element.unsigned_value; break;
  case ElementType::Boolean: type = "boolean"; value = element.boolean_value; break;
  case ElementType::Structure:
  case ElementType::Array:
    type = element.type == ElementType::Structure ? "structure" : "array";
    value = Json::array();
    for (const Element &child : element.children) {
      value.push_back(ElementJson(child));
    }
    break;
  }
  return {{"tag", std::move(tag)}, {"type", type}, {"value", std::move(value)}};
}

Json ErrorJson(const InteractionError &error) {
  Json result{{"code", error.code},
              {"effect", error.effect == InteractionEffect::Unknown ? "unknown" : "none"}};
  if (error.status) {
    result["status"] = *error.status;
  }
  if (error.cluster_status) {
    result["cluster_status"] = *error.cluster_status;
  }
  return result;
}

Json AttributeJson(const AttributeData &attribute) {
  return {{"path", PathJson(attribute.path)},
          {"value", ElementJson(attribute.value)},
          {"data_version", attribute.data_version
               ? Json(*attribute.data_version) : Json(nullptr)}};
}

Json EventJson(const EventData &event) {
  return {{"path", PathJson(event.path)}, {"value", ElementJson(event.value)},
          {"event_number", event.event_number}, {"priority", event.priority},
          {"timestamp", {{"kind", event.timestamp_kind == EventData::TimestampKind::Epoch
                                      ? "epoch" : "system"},
                         {"value", event.timestamp_value}}},
          {"status", 0}};
}

Json SubscriptionFrame(const SubscriptionReport &report,
                       const std::string &session_generation,
                       std::uint64_t report_sequence) {
  Json metadata{{"path", PathJson(report.result.path)},
                {"initial", report.initial},
                {"report_id", report.report_id},
                {"min_interval_s", report.min_interval_s},
                {"max_interval_s", report.max_interval_s},
                {"sdk_subscription_id", report.sdk_subscription_id}};
  Json value;
  std::string_view kind;
  if (report.kind == SubscriptionKind::Attribute) {
    kind = "attribute";
    value = ElementJson(report.result.attribute->value);
    metadata["data_version"] = report.result.attribute->data_version
        ? Json(*report.result.attribute->data_version) : Json(nullptr);
  } else {
    kind = "event";
    value = ElementJson(report.result.event->value);
    metadata["event_number"] = report.result.event->event_number;
    metadata["priority"] = report.result.event->priority;
    metadata["timestamp"] = {
        {"kind", report.result.event->timestamp_kind == EventData::TimestampKind::Epoch
                     ? "epoch" : "system"},
        {"value", report.result.event->timestamp_value}};
  }
  return {{"version", kProtocolVersion},
          {"event", "subscription_report"},
          {"session_generation", session_generation},
          {"subscription_id", report.subscription_id},
          {"generation", report.generation},
          {"report_sequence", report_sequence},
          {"kind", kind},
          {"value", std::move(value)},
          {"metadata", std::move(metadata)}};
}

std::optional<Json> InteractionJson(const InteractionRequest &request,
                                    const InteractionResponse &response) {
  if (!valid_interaction_response(request, response)) {
    return std::nullopt;
  }
  if (!response.ok) {
    return std::nullopt;
  }
  if (request.kind == InteractionKind::ReadAttribute) {
    if (response.results.size() != 1 || response.results[0].error) {
      return std::nullopt;
    }
    return AttributeJson(*response.results[0].attribute);
  }
  if (request.kind == InteractionKind::ReadAttributes ||
      request.kind == InteractionKind::ReadEvents) {
    Json results = Json::array();
    for (const PathResult &path : response.results) {
      Json outcome;
      if (path.error) {
        outcome = {{"error", ErrorJson(*path.error)}};
      } else if (path.attribute) {
        outcome = {{"ok", AttributeJson(*path.attribute)}};
      } else {
        outcome = {{"ok", EventJson(*path.event)}};
      }
      results.push_back({{"path", PathJson(path.path)},
                         {"result", std::move(outcome)}});
    }
    return results;
  }
  if (request.kind == InteractionKind::Write) {
    return Json{{"path", PathJson(*response.response_path)}, {"status", 0}};
  }
  return Json{{"path", response.response_path ? PathJson(*response.response_path)
                                                : Json(nullptr)},
              {"value", response.response_value ? ElementJson(*response.response_value)
                                                  : Json(nullptr)},
              {"status", 0}};
}

std::string Success(const Json &request, Json result) {
  return Json{{"version", kProtocolVersion},
              {"id", request["id"]},
              {"ok", true},
              {"result", std::move(result)}}
      .dump();
}

std::string Failure(const Json &request, std::string_view code) {
  return Json{{"version", kProtocolVersion},
              {"id", request["id"]},
              {"ok", false},
              {"error", {{"code", code}}}}
      .dump();
}

std::string InteractionFailure(const Json &request, const InteractionError &error) {
  return Json{{"version", kProtocolVersion}, {"id", request["id"]},
              {"ok", false}, {"error", ErrorJson(error)}}.dump();
}

std::string CommissioningFailure(const Json &request,
                                 const CommissioningError &error) {
  Json detail{{"code", error.code},
              {"effect", error.effect == InteractionEffect::Unknown
                   ? "unknown" : "none"}};
  if (error.sdk_status) {
    detail["sdk_status"] = *error.sdk_status;
  }
  return Json{{"version", kProtocolVersion}, {"id", request["id"]},
              {"ok", false}, {"error", std::move(detail)}}.dump();
}

bool ReadLineBounded(std::istream &input, std::string &line) {
  line.clear();
  char byte = 0;
  while (input.get(byte)) {
    if (byte == '\n') {
      return true;
    }
    if (line.size() >= kMaximumFrameBytes - 1) {
      return false;
    }
    line.push_back(byte);
  }
  return line.empty();
}

class BoundedOutput final {
 public:
  BoundedOutput(std::ostream &output, std::function<void()> failure)
      : output_(output), failure_(std::move(failure)) {
    worker_ = std::thread([this] { Write(); });
  }

  ~BoundedOutput() { Stop(); }

  bool EnqueueReport(const std::string &frame) {
    return Enqueue(frame, Class::Report, 64, 1048576, kMaximumFrameBytes);
  }

  bool EnqueueControl(const std::string &frame) {
    return Enqueue(frame, Class::Control, 256, 256 * 4096, 4096);
  }

  bool EnqueueReply(const std::string &frame) {
    return Enqueue(frame, Class::Reply, 64, 64 * kMaximumFrameBytes,
                   kMaximumFrameBytes);
  }

  void Stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
    }
    condition_.notify_one();
    if (worker_.joinable()) {
      worker_.join();
    }
  }

  bool healthy() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return healthy_;
  }

 private:
  enum class Class { Report, Control, Reply };
  struct PendingOutput {
    std::string frame;
    Class classification;
  };

  bool Enqueue(const std::string &frame, Class classification,
               std::size_t maximum_frames, std::size_t maximum_bytes,
               std::size_t maximum_frame_bytes) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!healthy_ || stopping_) {
      return false;
    }
    if (frame.empty() || frame.size() >= maximum_frame_bytes) {
      Fail();
      return false;
    }
    const std::size_t bytes = frame.size() + 1;
    std::size_t *frames = classification == Class::Report ? &report_frames_
        : classification == Class::Control ? &control_frames_ : &reply_frames_;
    std::size_t *retained = classification == Class::Report ? &report_bytes_
        : classification == Class::Control ? &control_bytes_ : &reply_bytes_;
    if (*frames >= maximum_frames || *retained > maximum_bytes ||
        bytes > maximum_bytes - *retained) {
      Fail();
      return false;
    }
    ++*frames;
    *retained += bytes;
    pending_.push_back({frame, classification});
#ifdef WOTEX_MATTER_FLOW_TESTING
    flow_testing::ObserveOutput(frame, report_frames_, report_bytes_,
                                control_frames_, control_bytes_, reply_frames_,
                                reply_bytes_);
#endif
    condition_.notify_one();
    return true;
  }

  // Called with mutex_ held. The callback only signals the lifetime owner;
  // it must not wait for this writer or invoke controller destruction.
  void Fail() {
    if (!healthy_) {
      return;
    }
    healthy_ = false;
    stopping_ = true;
    pending_.clear();
    condition_.notify_one();
    if (failure_) {
      failure_();
    }
  }

  void Write() {
    while (true) {
      PendingOutput pending;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock, [this] { return stopping_ || !pending_.empty(); });
        if (pending_.empty()) {
          if (stopping_) {
            return;
          }
          continue;
        }
        pending = std::move(pending_.front());
        pending_.pop_front();
      }

      bool written = false;
      try {
        output_ << pending.frame << '\n';
        output_.flush();
        written = static_cast<bool>(output_);
      } catch (const std::ios_base::failure &) {
        // Exception-enabled streams share the ordinary failed-write path.
      }

      std::lock_guard<std::mutex> lock(mutex_);
      const std::size_t bytes = pending.frame.size() + 1;
      if (pending.classification == Class::Report) {
        --report_frames_;
        report_bytes_ -= bytes;
      } else if (pending.classification == Class::Control) {
        --control_frames_;
        control_bytes_ -= bytes;
      } else {
        --reply_frames_;
        reply_bytes_ -= bytes;
      }
      if (!written) {
        Fail();
        return;
      }
    }
  }

  std::ostream &output_;
  std::function<void()> failure_;
  mutable std::mutex mutex_;
  std::condition_variable condition_;
  std::deque<PendingOutput> pending_;
  std::size_t report_frames_{0};
  std::size_t report_bytes_{0};
  std::size_t control_frames_{0};
  std::size_t control_bytes_{0};
  std::size_t reply_frames_{0};
  std::size_t reply_bytes_{0};
  bool healthy_{true};
  bool stopping_{false};
  std::thread worker_;
};

} // namespace

HostProtocol::HostProtocol(ControllerBackend &backend,
                           std::function<void()> channel_failure)
    : backend_(backend), channel_failure_(std::move(channel_failure)),
      output_sink_([](const std::string &) { return true; }) {
  backend_.SetSubscriptionSinks(
      [this](const SubscriptionReport &report) { return EmitReport(report); },
      [this](const SubscriptionStatus &status) { return EmitStatus(status); },
      [this](const std::string &id, std::uint64_t generation,
             const InteractionError &error) {
        EmitFailure(id, generation, error);
      });
}

HostProtocol::~HostProtocol() { Close(); }

std::string HostProtocol::ReadyFrame() {
  return Json{{"version", kProtocolVersion},
              {"event", "ready"},
              {"backend", kBackend},
              {"revision", kSdkRevision}}
      .dump();
}

bool HostProtocol::ParseDocumentAccepted(const std::string &line) {
  Json document;
  return ParseBounded(line, document);
}

bool HostProtocol::ParseRequestAccepted(const std::string &line) {
  Json request;
  std::uint64_t request_id = 0;
  return ParseBounded(line, request) && ValidRequestEnvelope(request, request_id);
}

void HostProtocol::SetOutputSink(std::function<bool(const std::string &)> sink) {
  std::lock_guard<std::mutex> lock(subscription_mutex_);
  output_sink_ = std::move(sink);
}

#ifdef WOTEX_MATTER_PROTOCOL_TESTING
bool HostProtocol::SeedReportCountersForTesting(std::uint64_t sequence,
                                               std::uint64_t bytes) {
  std::lock_guard<std::mutex> lock(subscription_mutex_);
  return report_flow_ && report_flow_->SeedCountersForTesting(sequence, bytes);
}
#endif

ProcessResult HostProtocol::ProcessLine(const std::string &line) {
  ProcessResult result;
  {
    struct DepthOwner {
      unsigned &depth;
      explicit DepthOwner(unsigned &value) : depth(value) { ++depth; }
      ~DepthOwner() { --depth; }
    } depth_owner{processing_depth_};
    result = ProcessLineImpl(line);
  }
  if (processing_depth_ == 0 && (close_requested_ || !healthy())) {
    Close();
    return {};
  }
  return result;
}

ProcessResult HostProtocol::ProcessLineImpl(const std::string &line) {
  if (!healthy()) {
    Close();
    return {};
  }
  Json request;
  if (!ParseBounded(line, request)) {
    Close();
    return {};
  }

  if (state_ == State::AwaitFlow) {
    std::string generation;
    if (!ExactKeys(request, {"version", "event", "session_generation"}) ||
        !request["version"].is_number_unsigned() ||
        request["version"].get<std::uint64_t>() != kProtocolVersion ||
        !request["event"].is_string() ||
        request["event"].get<std::string>() != "flow_open" ||
        !CanonicalGeneration(request["session_generation"], generation)) {
      Close();
      return {};
    }
    session_generation_ = std::move(generation);
    report_flow_ = std::make_unique<ReportCreditManager>(
        session_generation_, [this](const std::string &frame) {
          return WriteFrame(frame);
        });
    state_ = State::AwaitOpen;
    return {true, std::nullopt};
  }

  if (state_ == State::Open &&
      ExactKeys(request,
                {"version", "event", "session_generation", "report_sequence",
                 "acknowledged_bytes"})) {
    std::string generation;
    std::uint64_t sequence = 0;
    std::uint64_t bytes = 0;
    const bool valid = request["version"].is_number_unsigned() &&
        request["version"].get<std::uint64_t>() == kProtocolVersion &&
        request["event"].is_string() &&
        request["event"].get<std::string>() == "report_ack" &&
        CanonicalGeneration(request["session_generation"], generation) &&
        generation == session_generation_ &&
        Unsigned(request["report_sequence"],
                 std::numeric_limits<std::uint64_t>::max(), sequence) &&
        Unsigned(request["acknowledged_bytes"],
                 std::numeric_limits<std::uint64_t>::max(), bytes);
    bool accepted = false;
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      accepted = valid && report_flow_ &&
          report_flow_->Acknowledge(sequence, bytes);
#ifdef WOTEX_MATTER_FLOW_TESTING
      if (report_flow_) {
        const auto credit = report_flow_->snapshot();
        flow_testing::ObserveCredit(credit.queued, credit.queued_bytes,
                                    64 - credit.frame_credit,
                                    1048576 - credit.byte_credit);
      }
#endif
    }
    if (!accepted) {
      FailChannel();
      Close();
      return {};
    }
    return {true, std::nullopt};
  }

  std::uint64_t request_id = 0;
  if (!ValidRequestEnvelope(request, request_id)) {
    Close();
    return {};
  }
  const bool reserved_close = request["id"] == "close";
  if ((reserved_close && state_ != State::Open) ||
      (!reserved_close && request_id <= greatest_request_id_)) {
    Close();
    return {};
  }
  if (!reserved_close) {
    greatest_request_id_ = request_id;
  }
  const std::string operation = request["operation"].get<std::string>();

  if (state_ == State::AwaitOpen) {
    NativeOpenOptions options;
    if (operation != "open" || !OpenOptions(request["parameters"], options)) {
      Close();
      return {false, Failure(request, "invalid_request")};
    }
    options.timeout_ms =
        static_cast<std::uint32_t>(request["timeout_ms"].get<std::uint64_t>());
    const BackendResult result = backend_.Open(options);
    if (close_requested_ || !healthy()) {
      return {};
    }
    if (!result.ok) {
      Close();
      return {false, Failure(request, result.error_code.empty()
                                          ? "controller_start_failed"
                                          : result.error_code)};
    }
    fabric_id_ = options.fabric_id;
    state_ = State::Open;
    return {true,
            Success(request,
                    {{"lifecycle", "persistent"},
                     {"fabric_id", options.fabric_id},
                     {"controller_node_id", options.controller_node_id},
                     {"vendor_id", options.vendor_id}})};
  }

  if (state_ != State::Open) {
    return {};
  }

  if (operation == "close" && request["parameters"].empty()) {
    const std::string frame = Success(request, nullptr);
    Close();
    return {false, frame};
  }

  if (operation == "health" && request["parameters"].empty()) {
    return {true, Success(request, {{"status", "ready"},
                                    {"fabric_id", fabric_id_}})};
  }

  // The BEAM admission owner queues ordinary work. Native waits accept only
  // bounded controls; a second data operation cannot recursively enter the SDK.
  if (processing_depth_ > 1 && operation != "unsubscribe") {
    return {true, Failure(request, "interaction_busy")};
  }

  if (operation == "commission_on_network") {
    CommissioningRequest commissioning;
    if (!CommissioningParameters(
            request["parameters"],
            static_cast<std::uint32_t>(request["timeout_ms"].get<std::uint64_t>()),
            commissioning)) {
      return {true, Failure(request, "invalid_request")};
    }
    CommissioningResponse response = backend_.Commission(commissioning);
    if (close_requested_ || !healthy()) {
      return {};
    }
    if (!valid_commissioning_response(commissioning, response)) {
      return {true, Failure(request, "invalid_backend_result")};
    }
    if (!response.ok) {
      return {true, CommissioningFailure(request, *response.error)};
    }
    return {true,
            Success(request,
                    {{"node_id", response.node_id},
                     {"fabric_id", response.fabric_id},
                     {"case", "established"}})};
  }

  if (operation == "open_window") {
    CommissioningWindowRequest window;
    if (!CommissioningWindowParameters(
            request["parameters"],
            static_cast<std::uint32_t>(request["timeout_ms"].get<std::uint64_t>()),
            window)) {
      return {true, Failure(request, "invalid_request")};
    }
    CommissioningWindowResponse response = backend_.OpenWindow(window);
    if (close_requested_ || !healthy()) {
      return {};
    }
    if (!valid_commissioning_window_response(window, response)) {
      return {true, Failure(request, "invalid_backend_result")};
    }
    if (!response.ok) {
      return {true, CommissioningFailure(request, *response.error)};
    }
    return {true,
            Success(request,
                    {{"node_id", response.node_id},
                     {"setup_pin", response.setup_pin},
                     {"discriminator", response.discriminator},
                     {"manual_code", response.manual_code},
                     {"qr_code", response.qr_code},
                     {"expires_in_s", response.expires_in_s}})};
  }

  if (operation == "subscribe") {
    SubscriptionRequest subscription;
    if (!SubscriptionParameters(
            request["parameters"],
            static_cast<std::uint32_t>(request["timeout_ms"].get<std::uint64_t>()),
            subscription)) {
      return {true, Failure(request, "invalid_request")};
    }
    if (subscription.fabric_id != fabric_id_) {
      return {true, Failure(request, "fabric_mismatch")};
    }
    SubscriptionResponse response = backend_.Subscribe(subscription);
    if (close_requested_ || !healthy()) {
      return {};
    }
    if (!response.ok) {
      return {true, Failure(request, response.error_code.empty()
                                        ? "subscription_failed"
                                        : response.error_code)};
    }
    if (response.subscription_id != subscription.subscription_id ||
        response.generation == 0 || response.max_interval_s == 0 ||
        response.min_interval_s > response.max_interval_s) {
      return {true, Failure(request, "invalid_backend_result")};
    }
    bool admitted = false;
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      admitted = report_flow_ &&
          report_flow_->AddStream(response.subscription_id, response.generation,
                                  subscription.queue_limit);
      if (admitted) {
        subscriptions_.emplace(
            response.subscription_id,
            ActiveSubscription{response.generation, subscription.queue_limit,
                               subscription.resubscribe, false, 0});
      }
    }
    if (!admitted) {
        backend_.CancelSubscription(response.subscription_id,
                                    response.generation, subscription.timeout_ms);
      return {true, Failure(request, "subscription_busy")};
    }
    Json result{{"subscription_id", response.subscription_id},
                {"generation", response.generation},
                {"min_interval_s", response.min_interval_s},
                {"max_interval_s", response.max_interval_s},
                {"sdk_subscription_id", response.sdk_subscription_id}};
    return {true, Success(request, std::move(result)),
            std::make_pair(response.subscription_id, response.generation)};
  }

  if (operation == "unsubscribe") {
    if (cancellation_pending_) {
      return {true, Failure(request, "subscription_busy")};
    }
    std::string subscription_id;
    std::uint64_t generation = 0;
    if (!UnsubscribeParameters(request["parameters"], subscription_id,
                               generation)) {
      return {true, Failure(request, "invalid_request")};
    }
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      const auto active = subscriptions_.find(subscription_id);
      if (active != subscriptions_.end() && active->second.generation != generation) {
        return {true, Failure(request, "invalid_subscription")};
      }
      // A retirement barrier can cross an already submitted cancellation.
      // Its bounded outstanding-credit record identifies that exact stream;
      // acknowledging cancellation neither repeats the barrier nor mints credit.
      if (report_flow_ && report_flow_->IsRetired(subscription_id, generation)) {
        return {true, Success(request, nullptr)};
      }
      if (!report_flow_ || !report_flow_->IsLive(subscription_id, generation)) {
        return {true, Failure(request, "invalid_subscription")};
      }
    }
    cancellation_pending_ = true;
    BackendResult cancelled =
        backend_.CancelSubscription(
            subscription_id, generation,
            static_cast<std::uint32_t>(request["timeout_ms"].get<std::uint64_t>()));
    cancellation_pending_ = false;
    if (close_requested_ || !healthy()) {
      return {};
    }
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      const auto active = subscriptions_.find(subscription_id);
      if (active == subscriptions_.end() ||
          (active->second.generation == generation && report_flow_ &&
           report_flow_->IsRetired(subscription_id, generation))) {
        return {true, Success(request, nullptr)};
      }
    }
    if (!cancelled.ok) {
      return {true, Failure(request, cancelled.error_code.empty()
                                        ? "invalid_subscription"
                                        : cancelled.error_code)};
    }
    bool retired = false;
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      if (report_flow_ && report_flow_->IsLive(subscription_id, generation)) {
        const std::uint64_t last =
            report_flow_->last_transmitted(subscription_id, generation);
        const std::string barrier =
            Json{{"version", kProtocolVersion},
                 {"event", "stream_retired"},
                 {"session_generation", session_generation_},
                 {"subscription_id", subscription_id},
                 {"generation", generation},
                 {"last_report_sequence", last}}
                .dump();
        retired = report_flow_->Retire(subscription_id, generation, barrier);
      }
    }
    if (!retired) {
      Close();
      return {};
    }
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      subscriptions_.erase(subscription_id);
    }
    return {true, Success(request, nullptr)};
  }

  if (request["parameters"].contains("fabric_id") &&
      request["parameters"]["fabric_id"].is_number_unsigned() &&
      request["parameters"]["fabric_id"].get<std::uint64_t>() != fabric_id_) {
    return {true, Failure(request, "fabric_mismatch")};
  }

  InteractionRequest interaction;
  if (InteractionParameters(
          operation, request["parameters"],
          static_cast<std::uint32_t>(request["timeout_ms"].get<std::uint64_t>()),
          interaction)) {
    if (interaction.fabric_id != fabric_id_) {
      return {true, Failure(request, "fabric_mismatch")};
    }
    InteractionResponse response = backend_.Interact(interaction);
    if (close_requested_ || !healthy()) {
      return {};
    }
    if (!response.ok) {
      if (!response.error.has_value() || response.error->code.empty()) {
        return {true, Failure(request, "invalid_backend_result")};
      }
      return {true, InteractionFailure(request, *response.error)};
    }
    if (interaction.kind == InteractionKind::ReadAttribute &&
        response.results.size() == 1 && response.results[0].error.has_value()) {
      return {true, InteractionFailure(request, *response.results[0].error)};
    }
    std::optional<Json> result = InteractionJson(interaction, response);
    if (!result.has_value()) {
      return {true, Failure(request, "invalid_backend_result")};
    }
    const std::string encoded = result->dump();
    if (!valid_encoded_result_size(encoded.size())) {
      return {true, Failure(request, "response_limit")};
    }
    return {true, Success(request, std::move(*result))};
  }

  if (operation == "read" || operation == "read_paths" ||
      operation == "read_events" || operation == "write" ||
      operation == "invoke") {
    return {true, Failure(request, "invalid_request")};
  }

  return {true, Failure(request, "not_supported")};
}

bool HostProtocol::ActivateSubscription(const std::string &subscription_id,
                                        std::uint64_t generation) {
  return healthy() && backend_.ActivateSubscription(subscription_id, generation);
}

bool HostProtocol::healthy() const { return !channel_failed_.load(); }

void HostProtocol::FailChannel() {
  // SDK callbacks signal the lifetime owner; they never tear down their own
  // controller stack. Repeated failures cannot restart the cleanup grace.
  if (!channel_failed_.exchange(true) && channel_failure_) {
    channel_failure_();
  }
}

bool HostProtocol::WriteFrame(const std::string &frame) {
  if (!healthy()) {
    return false;
  }
  if (!output_sink_(frame)) {
    FailChannel();
    return false;
  }
  return true;
}

bool HostProtocol::EmitReport(const SubscriptionReport &report) {
  std::lock_guard<std::mutex> lock(subscription_mutex_);
  if (!healthy() || state_ != State::Open || !report_flow_ ||
      !report_flow_->IsLive(report.subscription_id, report.generation)) {
    return false;
  }
  const auto result = report_flow_->Submit(
      report.subscription_id, report.generation,
      [this, report](std::uint64_t sequence) {
        const std::string encoded =
            SubscriptionFrame(report, session_generation_, sequence).dump();
#ifdef WOTEX_MATTER_FLOW_TESTING
        return flow_testing::EncodeReport(encoded);
#else
        return encoded;
#endif
      });
#ifdef WOTEX_MATTER_FLOW_TESTING
  const auto credit = report_flow_->snapshot();
  flow_testing::ObserveCredit(credit.queued, credit.queued_bytes,
                              64 - credit.frame_credit,
                              1048576 - credit.byte_credit);
#endif
  if (result == ReportCreditManager::SubmitResult::Transmitted ||
      result == ReportCreditManager::SubmitResult::Queued) {
    return true;
  }
  if (result == ReportCreditManager::SubmitResult::StreamOverflow) {
    const InteractionError error{"queue_overflow"};
    const std::string failure =
        Json{{"version", kProtocolVersion},
             {"event", "subscription_error"},
             {"session_generation", session_generation_},
             {"subscription_id", report.subscription_id},
             {"generation", report.generation},
             {"error", ErrorJson(error)}}
            .dump();
    if (!WriteFrame(failure)) {
      return false;
    }
    const std::uint64_t last = report_flow_->last_transmitted(
        report.subscription_id, report.generation);
    const std::string barrier =
        Json{{"version", kProtocolVersion},
             {"event", "stream_retired"},
             {"session_generation", session_generation_},
             {"subscription_id", report.subscription_id},
             {"generation", report.generation},
             {"last_report_sequence", last}}
            .dump();
    if (!report_flow_->Retire(report.subscription_id, report.generation, barrier)) {
      FailChannel();
    }
    subscriptions_.erase(report.subscription_id);
  } else {
    // The stream is live, so Invalid is a generation-wide accounting or
    // transmission failure. No subsequent callback can reuse its counters.
    FailChannel();
  }
  return false;
}

bool HostProtocol::EmitStatus(const SubscriptionStatus &status) {
  std::lock_guard<std::mutex> lock(subscription_mutex_);
  if (!healthy() || state_ != State::Open || !report_flow_ ||
      status.subscription_id.empty() || status.generation == 0 || status.attempt == 0 || status.attempt > 5) {
    return false;
  }
  auto active = subscriptions_.find(status.subscription_id);
  if (active == subscriptions_.end() || !active->second.resubscribe) {
    return false;
  }

  if (status.status == SubscriptionStatusKind::Resubscribing) {
    const std::uint64_t previous = active->second.generation;
    const bool first = !active->second.recovering;
    if ((first && (previous == std::numeric_limits<std::uint64_t>::max() ||
                   status.generation != previous + 1 || status.attempt != 1)) ||
        (!first && (status.generation != previous ||
                    status.attempt != active->second.recovery_attempt + 1)) ||
        status.continuity != SubscriptionContinuity::Lost) {
      return false;
    }
    const std::string frame =
        Json{{"version", kProtocolVersion},
             {"event", "subscription_status"},
             {"session_generation", session_generation_},
             {"subscription_id", status.subscription_id},
             {"generation", status.generation},
             {"status", "resubscribing"},
             {"continuity", "lost"},
             {"attempt", status.attempt}}
            .dump();
    if (!WriteFrame(frame)) {
      return false;
    }
    if (first) {
      const std::uint64_t last = report_flow_->last_transmitted(
          status.subscription_id, previous);
      const std::string barrier =
          Json{{"version", kProtocolVersion},
               {"event", "stream_retired"},
               {"session_generation", session_generation_},
               {"subscription_id", status.subscription_id},
               {"generation", previous},
               {"last_report_sequence", last}}
              .dump();
      if (!report_flow_->BeginRecovery(status.subscription_id, previous,
                                       status.generation,
                                       active->second.queue_limit, barrier)) {
        FailChannel();
        return false;
      }
      active->second.generation = status.generation;
      active->second.recovering = true;
    }
    active->second.recovery_attempt = status.attempt;
    return true;
  }

  if (status.status != SubscriptionStatusKind::Resubscribed ||
      !active->second.recovering ||
      active->second.generation != status.generation ||
      active->second.recovery_attempt != status.attempt ||
      status.continuity != SubscriptionContinuity::Unknown ||
      status.max_interval_s == 0 ||
      status.min_interval_s > status.max_interval_s) {
    return false;
  }
  const std::string frame =
      Json{{"version", kProtocolVersion},
           {"event", "subscription_status"},
           {"session_generation", session_generation_},
           {"subscription_id", status.subscription_id},
           {"generation", status.generation},
           {"status", "resubscribed"},
           {"continuity", "unknown"},
           {"attempt", status.attempt},
           {"min_interval_s", status.min_interval_s},
           {"max_interval_s", status.max_interval_s},
           {"sdk_subscription_id", status.sdk_subscription_id}}
          .dump();
  if (!WriteFrame(frame)) {
    return false;
  }
  active->second.recovering = false;
  active->second.recovery_attempt = 0;
  return true;
}

void HostProtocol::EmitFailure(const std::string &subscription_id,
                               std::uint64_t generation,
                               const InteractionError &error) {
  std::lock_guard<std::mutex> lock(subscription_mutex_);
  if (!healthy() || state_ != State::Open || !report_flow_ ||
      !report_flow_->IsLive(subscription_id, generation)) {
    return;
  }
  const std::string failure =
      Json{{"version", kProtocolVersion},
           {"event", "subscription_error"},
           {"session_generation", session_generation_},
           {"subscription_id", subscription_id},
           {"generation", generation},
           {"error", ErrorJson(error)}}
          .dump();
  if (!WriteFrame(failure)) {
    return;
  }
  const std::uint64_t last =
      report_flow_->last_transmitted(subscription_id, generation);
  const std::string barrier =
      Json{{"version", kProtocolVersion},
           {"event", "stream_retired"},
           {"session_generation", session_generation_},
           {"subscription_id", subscription_id},
           {"generation", generation},
           {"last_report_sequence", last}}
          .dump();
  if (!report_flow_->Retire(subscription_id, generation, barrier)) {
    FailChannel();
  }
  subscriptions_.erase(subscription_id);
}

void HostProtocol::RequestClose() {
  close_requested_ = true;
  std::lock_guard<std::mutex> lock(subscription_mutex_);
  if (state_ != State::Closed) {
    state_ = State::Closing;
  }
}

void HostProtocol::Close() {
  if (processing_depth_ > 1) {
    RequestClose();
    return;
  }
  {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    if (state_ == State::Closed) {
      return;
    }
    state_ = State::Closed;
  }
  if (backend_.IsOpen()) {
    backend_.Close();
  }
  backend_.SetSubscriptionSinks({}, {}, {});
  {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    report_flow_.reset();
    subscriptions_.clear();
  }
}

int RunHost(ControllerBackend &backend, std::istream &input,
            std::ostream &output, std::function<void()> channel_failure,
            int input_fd) {
  BoundedOutput writer(output, channel_failure);
  HostProtocol protocol(backend, std::move(channel_failure));
  protocol.SetOutputSink([&writer](const std::string &frame) {
    return frame.find("\"event\":\"subscription_report\"") !=
            std::string::npos
        ? writer.EnqueueReport(frame)
        : writer.EnqueueControl(frame);
  });
  if (!writer.EnqueueControl(HostProtocol::ReadyFrame())) {
    return 1;
  }

  std::unique_ptr<BoundedInput> descriptor;
  if (input_fd >= 0) {
    descriptor = std::make_unique<BoundedInput>(input_fd);
  }
  bool running = true;
  bool invalid_input = false;
  bool dispatch_failed = false;
  const auto dispatch = [&](const std::string &line) {
    ProcessResult result = protocol.ProcessLine(line);
    if (!running) {
      return;
    }
    if (!protocol.healthy() || !writer.healthy()) {
      dispatch_failed = true;
      running = false;
      return;
    }
    if (result.frame && !writer.EnqueueReply(*result.frame)) {
      dispatch_failed = true;
      running = false;
      return;
    }
    if (result.activate_subscription &&
        !protocol.ActivateSubscription(result.activate_subscription->first,
                                        result.activate_subscription->second)) {
      dispatch_failed = true;
      running = false;
      return;
    }
    running = result.keep_running;
  };

  // Clear the callback before its parser and protocol captures leave scope,
  // including exceptional exits. SDK shutdown itself never invokes this pump.
  struct PumpOwner {
    ControllerBackend &backend;
    ~PumpOwner() { backend.SetControlPump({}); }
  } pump_owner{backend};
  if (descriptor) {
    backend.SetControlPump([&] {
      // A finite batch lets the pending operation recheck its original deadline
      // even if input remains readable throughout the wait.
      for (unsigned count = 0; running && count < 16; ++count) {
        std::string line;
        const auto result = descriptor->Next(line, 0);
        if (result == BoundedInput::Result::Waiting) {
          break;
        }
        if (result != BoundedInput::Result::Line) {
          invalid_input = result == BoundedInput::Result::Invalid;
          running = false;
          break;
        }
        dispatch(line);
      }
      if (!running || !writer.healthy() || !protocol.healthy()) {
        protocol.RequestClose();
        return false;
      }
      return true;
    });
  }

  while (running && writer.healthy() && protocol.healthy()) {
    std::string line;
    if (descriptor) {
      const auto result = descriptor->Next(line, -1);
      if (result == BoundedInput::Result::Waiting) {
        continue;
      }
      if (result != BoundedInput::Result::Line) {
        invalid_input = result == BoundedInput::Result::Invalid;
        break;
      }
    } else if (!ReadLineBounded(input, line) || (!input && line.empty())) {
      break;
    }
    dispatch(line);
  }
  protocol.Close();
  writer.Stop();
  return !invalid_input && !dispatch_failed && writer.healthy() && protocol.healthy() ? 0 : 1;
}

} // namespace wotex::matter
