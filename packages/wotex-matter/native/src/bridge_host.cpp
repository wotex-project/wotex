#include "wotex_matter/bridge_command_renderer.hpp"
#include "wotex_matter/bridge_sdk_receiver.hpp"

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <time.h>
#include <unistd.h>
#include <utility>

#ifdef WOTEX_MATTER_BRIDGE_TESTING
#error The production bridge entry point must not enable fixture hooks.
#endif

namespace {
using namespace wotex::matter;
std::atomic<bool> cancelled{false};
static_assert(std::atomic<bool>::is_always_lock_free);
void Cancel(int) { cancelled.store(true, std::memory_order_relaxed); }

class Clock final : public BridgeHandoffClock {
 public:
  std::uint64_t NowMs() noexcept override {
    timespec now{};
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 || now.tv_nsec < 0 ||
        now.tv_nsec >= 1000000000 ||
        static_cast<std::uint64_t>(now.tv_sec) >
            (std::numeric_limits<std::uint64_t>::max() - 999) / 1000)
      std::_Exit(static_cast<int>(BridgeProcessExit::Cleanup));
    return static_cast<std::uint64_t>(now.tv_sec) * 1000 +
        static_cast<std::uint64_t>(now.tv_nsec) / 1000000;
  }
};

// The renderer attaches first and retires last. The consumer worker joins
// outside SDK locking; both attachments finish under that lock before endpoints
// and SDK resources retire. Construction performs no SDK or file work.
class Receiver final : public BridgeSdkProcessReceiver {
 public:
  Receiver() : consumer_(renderer_) {}
  CHIP_ERROR Attach(SdkBridgeBootstrap &runtime, BridgeConsumerHandoff &shared,
                    BridgeHandoffOwner &owner, BridgeOutputOwner &output,
                    SdkBridgeObservationOwner &observations) noexcept override {
    if (used_) return CHIP_ERROR_INCORRECT_STATE;
    used_ = true;
    if (!runtime.endpoints()) return CHIP_ERROR_INCORRECT_STATE;
    ReturnErrorOnFailure(renderer_.Attach(*runtime.endpoints()));
    renderer_attached_ = true;
    consumer_attaching_ = true;
    return consumer_.Attach(runtime, shared, owner, output, observations);
  }
  bool ResultReady(const BridgeConsumerHandoff::Ticket &ticket) noexcept override {
    return consumer_.ResultReady(ticket);
  }
  bool Retire() noexcept override { return !consumer_attaching_ || consumer_.Retire(); }
  CHIP_ERROR Finish() noexcept override {
    if (!used_ || finished_) return CHIP_ERROR_INCORRECT_STATE;
    finished_ = true;
    const auto consumer = consumer_attaching_ ? consumer_.Finish() : CHIP_NO_ERROR;
    const auto renderer = renderer_attached_ ? renderer_.Finish() : CHIP_NO_ERROR;
    return consumer != CHIP_NO_ERROR ? consumer : renderer;
  }
  chip::app::DataModel::ActionReturnStatus Read(
      BridgeRequestMetadata request, chip::app::AttributeValueEncoder &encoder) override {
    return consumer_.Read(request, encoder);
  }
  chip::app::DataModel::ActionReturnStatus Write(
      BridgeRequestMetadata request, chip::app::AttributeValueDecoder &decoder) override {
    return consumer_.Write(request, decoder);
  }
  std::optional<chip::app::DataModel::ActionReturnStatus> Invoke(
      BridgeRequestMetadata request, chip::TLV::TLVReader &arguments,
      chip::app::CommandHandler *handler) override {
    return consumer_.Invoke(request, arguments, handler);
  }
  void ListNotification(const chip::app::ConcreteAttributePath &path,
                        chip::app::DataModel::ListWriteOperation operation,
                        chip::FabricIndex fabric) override {
    consumer_.ListNotification(path, operation, fabric);
  }

 private:
  SdkBridgeCommandRenderer renderer_;
  SdkBridgeConsumerReceiver consumer_;
  bool used_{false}, renderer_attached_{false}, consumer_attaching_{false}, finished_{false};
};

bool Signals() {
  struct sigaction action{};
  if (sigemptyset(&action.sa_mask) != 0) return false;
  action.sa_handler = SIG_IGN;
  if (sigaction(SIGPIPE, &action, nullptr) != 0) return false;
  action.sa_handler = Cancel;
  return sigaction(SIGINT, &action, nullptr) == 0 && sigaction(SIGTERM, &action, nullptr) == 0;
}
int Failed(BridgeProcessExit result) {
  if (result != BridgeProcessExit::Closed) std::fputs("bridge process failed\n", stderr);
  return static_cast<int>(result);
}
} // namespace

int main(int argc, char **argv) {
  if (!Signals()) return Failed(BridgeProcessExit::Cleanup);
  if (argc != 3 || std::strcmp(argv[1], "--configuration") != 0 || argv[2][0] != '/' ||
      strnlen(argv[2], 4097) > 4096 || std::strpbrk(argv[2], "\r\n")) {
    std::fputs("invalid bridge invocation\n", stderr);
    return static_cast<int>(BridgeProcessExit::Invalid);
  }
  try {
    Clock clock;
    Receiver receiver;
    SdkBridgeProcessDriver driver(argv[2], receiver);
    return Failed(RunBridgeProcess(STDIN_FILENO, STDOUT_FILENO, 5000, clock, driver, cancelled));
  } catch (...) {
    return Failed(BridgeProcessExit::Cleanup);
  }
}
