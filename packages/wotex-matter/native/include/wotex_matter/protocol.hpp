#ifndef WOTEX_MATTER_PROTOCOL_HPP
#define WOTEX_MATTER_PROTOCOL_HPP

#include "wotex_matter/commissioning.hpp"
#include "wotex_matter/interaction.hpp"
#include "wotex_matter/subscription.hpp"

#include <cstdint>
#include <functional>
#include <istream>
#include <memory>
#include <mutex>
#include <optional>
#include <ostream>
#include <string>
#include <unordered_map>
#include <utility>

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
  using ReportSink = std::function<bool(const SubscriptionReport &)>;
  using StatusSink = std::function<bool(const SubscriptionStatus &)>;
  using FailureSink =
      std::function<void(const std::string &, std::uint64_t,
                         const InteractionError &)>;

  virtual ~ControllerBackend() = default;
  virtual BackendResult Open(const NativeOpenOptions &options) = 0;
  virtual InteractionResponse Interact(const InteractionRequest &request) = 0;
  virtual CommissioningResponse Commission(const CommissioningRequest &) {
    return {false, CommissioningError{"not_supported", std::nullopt,
                                      InteractionEffect::None},
            0, 0, false};
  }
  virtual CommissioningWindowResponse OpenWindow(
      const CommissioningWindowRequest &) {
    return {false, CommissioningError{"not_supported", std::nullopt,
                                      InteractionEffect::None},
            0, 0, 0, 0, {}, {}};
  }
  virtual void SetSubscriptionSinks(ReportSink, StatusSink, FailureSink) {}
  virtual SubscriptionResponse Subscribe(const SubscriptionRequest &) {
    SubscriptionResponse result;
    result.error_code = "not_supported";
    return result;
  }
  virtual bool ActivateSubscription(const std::string &, std::uint64_t) {
    return false;
  }
  virtual BackendResult CancelSubscription(const std::string &, std::uint64_t,
                                            std::uint32_t) {
    return {false, "not_supported"};
  }
  virtual void Close() = 0;
  virtual bool IsOpen() const = 0;
};

struct ProcessResult {
  bool keep_running{false};
  std::optional<std::string> frame;
  std::optional<std::pair<std::string, std::uint64_t>> activate_subscription;

  ProcessResult() = default;
  ProcessResult(
      bool keep, std::optional<std::string> output,
      std::optional<std::pair<std::string, std::uint64_t>> activation =
          std::nullopt)
      : keep_running(keep), frame(std::move(output)),
        activate_subscription(std::move(activation)) {}
};

class HostProtocol final {
 public:
  explicit HostProtocol(ControllerBackend &backend);
  ~HostProtocol();

  HostProtocol(const HostProtocol &) = delete;
  HostProtocol &operator=(const HostProtocol &) = delete;

  static std::string ReadyFrame();
  static bool ParseDocumentAccepted(const std::string &line);
  static bool ParseRequestAccepted(const std::string &line);

  void SetOutputSink(std::function<bool(const std::string &)> sink);
  ProcessResult ProcessLine(const std::string &line);
  bool ActivateSubscription(const std::string &subscription_id,
                            std::uint64_t generation);
  void Close();

 private:
  enum class State { AwaitFlow, AwaitOpen, Open, Closed };

  ControllerBackend &backend_;
  std::function<bool(const std::string &)> output_sink_;
  std::unique_ptr<ReportCreditManager> report_flow_;
  std::mutex subscription_mutex_;
  State state_{State::AwaitFlow};
  std::string session_generation_;
  std::uint64_t greatest_request_id_{0};
  std::uint64_t fabric_id_{0};

  struct ActiveSubscription {
    std::uint64_t generation{0};
    std::size_t queue_limit{0};
    bool resubscribe{false};
    bool recovering{false};
    std::uint8_t recovery_attempt{0};
  };
  std::unordered_map<std::string, ActiveSubscription> subscriptions_;

  bool EmitReport(const SubscriptionReport &report);
  bool EmitStatus(const SubscriptionStatus &status);
  void EmitFailure(const std::string &subscription_id, std::uint64_t generation,
                   const InteractionError &error);
};

int RunHost(ControllerBackend &backend, std::istream &input,
            std::ostream &output, std::function<void()> channel_failure = {});

} // namespace wotex::matter

#endif
