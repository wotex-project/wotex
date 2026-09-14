#include "wotex_matter/protocol.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <limits>
#include <set>
#include <string_view>
#include <vector>

namespace wotex::matter {
namespace {

using Json = nlohmann::json;

constexpr std::size_t kMaximumDepth = 8;
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
      CanonicalRequestId(request["id"], request_id) &&
      request["operation"].is_string() && request["parameters"].is_object() &&
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
      (value >= 0x00010000U && value <= 0xFFF47FFFU &&
       value % 65536U <= 0x7FFFU);
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
      !PathComponent(value["cluster"], 0xFFF47FFFU, cluster) ||
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
  if ((type == "u8" || type == "u16" || type == "u32") &&
      body.is_number_unsigned()) {
    const auto integer = body.get<std::uint64_t>();
    const std::uint64_t maximum = type == "u8" ? 0xFFU :
        (type == "u16" ? 0xFFFFU : 0xFFFFFFFFULL);
    if (integer > maximum) {
      return false;
    }
    result.type = type == "u8" ? ElementType::U8
        : (type == "u16" ? ElementType::U16 : ElementType::U32);
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

} // namespace

HostProtocol::HostProtocol(ControllerBackend &backend) : backend_(backend) {}

HostProtocol::~HostProtocol() { Close(); }

std::string HostProtocol::ReadyFrame() {
  return Json{{"version", kProtocolVersion},
              {"event", "ready"},
              {"backend", kBackend},
              {"revision", kSdkRevision}}
      .dump();
}

bool HostProtocol::ParseRequestAccepted(const std::string &line) {
  Json request;
  std::uint64_t request_id = 0;
  return ParseBounded(line, request) && ValidRequestEnvelope(request, request_id);
}

ProcessResult HostProtocol::ProcessLine(const std::string &line) {
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
    state_ = State::AwaitOpen;
    return {true, std::nullopt};
  }

  std::uint64_t request_id = 0;
  if (!ValidRequestEnvelope(request, request_id) ||
      request_id <= greatest_request_id_) {
    Close();
    return {};
  }
  greatest_request_id_ = request_id;
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
    if (encoded.size() > kMaximumInteractionResultBytes) {
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

void HostProtocol::Close() {
  if (state_ == State::Closed) {
    return;
  }
  if (backend_.IsOpen()) {
    backend_.Close();
  }
  state_ = State::Closed;
}

int RunHost(ControllerBackend &backend, std::istream &input,
            std::ostream &output) {
  HostProtocol protocol(backend);
  output << HostProtocol::ReadyFrame() << '\n';
  output.flush();

  std::string line;
  while (ReadLineBounded(input, line)) {
    if (!input && line.empty()) {
      break;
    }
    ProcessResult result = protocol.ProcessLine(line);
    if (result.frame.has_value()) {
      output << *result.frame << '\n';
      output.flush();
      if (!output) {
        protocol.Close();
        return 1;
      }
    }
    if (!result.keep_running) {
      break;
    }
  }
  protocol.Close();
  return 0;
}

} // namespace wotex::matter
