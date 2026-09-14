#ifndef WOTEX_MATTER_PROTOCOL_HPP
#define WOTEX_MATTER_PROTOCOL_HPP

#include <cstdint>
#include <istream>
#include <optional>
#include <ostream>
#include <string>

namespace wotex::matter {

inline constexpr std::uint32_t kProtocolVersion = 1;
inline constexpr char kBackend[] = "matter-native";
inline constexpr char kSdkRevision[] =
    "250a9e6c50ee2068107f3c4808b680f5f2925415";
inline constexpr std::size_t kMaximumFrameBytes = 131072;

struct NativeOpenOptions {
  std::string lifecycle;
  std::string storage_path;
  std::string storage_mode;
  std::string authority;
  std::string paa_trust_store;
  std::uint64_t fabric_id{0};
  std::uint64_t controller_node_id{0};
  std::uint16_t vendor_id{0};
  std::uint32_t timeout_ms{0};
};

struct BackendResult {
  bool ok{false};
  std::string error_code;
};

class ControllerBackend {
 public:
  virtual ~ControllerBackend() = default;
  virtual BackendResult Open(const NativeOpenOptions &options) = 0;
  virtual void Close() = 0;
  virtual bool IsOpen() const = 0;
};

struct ProcessResult {
  bool keep_running{false};
  std::optional<std::string> frame;
};

class HostProtocol final {
 public:
  explicit HostProtocol(ControllerBackend &backend);
  ~HostProtocol();

  HostProtocol(const HostProtocol &) = delete;
  HostProtocol &operator=(const HostProtocol &) = delete;

  static std::string ReadyFrame();
  static bool ParseRequestAccepted(const std::string &line);

  ProcessResult ProcessLine(const std::string &line);
  void Close();

 private:
  enum class State { AwaitFlow, AwaitOpen, Open, Closed };

  ControllerBackend &backend_;
  State state_{State::AwaitFlow};
  std::string session_generation_;
  std::uint64_t greatest_request_id_{0};
  std::uint64_t fabric_id_{0};
};

int RunHost(ControllerBackend &backend, std::istream &input,
            std::ostream &output);

} // namespace wotex::matter

#endif
