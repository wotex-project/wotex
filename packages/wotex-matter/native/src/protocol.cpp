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
