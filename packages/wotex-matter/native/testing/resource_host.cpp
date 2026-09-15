#include "wotex_matter/controller.hpp"
#include "wotex_matter/input_lifetime.hpp"
#include "wotex_matter/resource_testing.hpp"

#ifndef WOTEX_MATTER_RESOURCE_TESTING
#error "Resource observations belong only to the selected test executable"
#endif

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <charconv>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

namespace wotex::matter::resource_testing {
namespace {

using Json = nlohmann::json;

std::optional<Json> Configuration() {
  const char *path = std::getenv("WOTEX_MATTER_RESOURCE_CONFIG");
  if (path == nullptr) {
    return std::nullopt;
  }
  const auto bytes = ReadBounded(path, 8192);
  if (!bytes || !HostProtocol::ParseDocumentAccepted(*bytes)) {
    return std::nullopt;
  }
  Json value = Json::parse(*bytes, nullptr, false);
  bool process_directory = false;
  if (value.is_object() && value.contains("process_directory")) {
    if (value["process_directory"] != true) {
      return std::nullopt;
    }
    process_directory = true;
    value.erase("process_directory");
  }
  if (!value.is_object() || (value.size() != 1 && value.size() != 3) ||
      !value.contains("directory") || !value["directory"].is_string()) {
    return std::nullopt;
  }
  const std::string directory = value["directory"].get<std::string>();
  struct stat status{};
  if (directory.empty() || directory[0] != '/' || directory.size() > 4096 ||
      directory.find('\0') != std::string::npos ||
      lstat(directory.c_str(), &status) != 0 || !S_ISDIR(status.st_mode) ||
      (status.st_mode & 0777) != 0700) {
    return std::nullopt;
  }
  if (value.size() == 3) {
    if (!value.contains("startup_stage") || !value["startup_stage"].is_string() ||
        !value.contains("startup_action") || !value["startup_action"].is_string()) {
      return std::nullopt;
    }
    const auto stage = value["startup_stage"].get<std::string>();
    const auto action = value["startup_action"].get<std::string>();
    constexpr std::array<const char *, 11> stages{
        "memory", "storage", "storage_directory", "sdk_storage", "authority",
        "attestation", "groups", "factory", "system_state", "event_loop", "commissioner"};
    if (std::find(stages.begin(), stages.end(), stage) == stages.end() ||
        (action != "fail" && action != "throw" && action != "wait")) {
      return std::nullopt;
    }
  }
  if (process_directory) {
    value["process_directory"] = true;
  }
  return value;
}

class ObservedBackend final : public ControllerBackend {
 public:
  explicit ObservedBackend(std::string directory) : directory_(std::move(directory)) {
    observer_ = std::thread([this] { Observe(); });
  }

  ~ObservedBackend() override {
    StopObserving();
  }

  void StopObserving() {
    stopping_ = true;
    if (observer_.joinable()) {
      observer_.join();
    }
  }

  BackendResult Open(const NativeOpenOptions &options) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    const auto result = backend_.Open(options);
    if (!result.ok) {
      // A BEAM caller may kill a failed startup as soon as it receives the
      // error. Record the completed SDK cleanup before publishing that reply.
      const Json observation{{"code", result.error_code},
                             {"native", Json::parse(backend_.ResourceSnapshotForTesting())}};
      if (!WriteAtomicExclusive(directory_ + "/startup-failure.json", observation.dump())) {
        failed_ = true;
      }
    }
    return result;
  }

  InteractionResponse Interact(const InteractionRequest &request) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.Interact(request);
  }

  CommissioningResponse Commission(const CommissioningRequest &request) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.Commission(request);
  }

  CommissioningWindowResponse OpenWindow(const CommissioningWindowRequest &request) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.OpenWindow(request);
  }

  SubscriptionResponse Subscribe(const SubscriptionRequest &request) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.Subscribe(request);
  }

  bool ActivateSubscription(const std::string &identity, std::uint64_t generation) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.ActivateSubscription(identity, generation);
  }

  BackendResult CancelSubscription(const std::string &identity, std::uint64_t generation,
                                   std::uint32_t timeout) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.CancelSubscription(identity, generation, timeout);
  }

  void SetSubscriptionSinks(ReportSink report, StatusSink status, FailureSink failure) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    backend_.SetSubscriptionSinks(std::move(report), std::move(status), std::move(failure));
  }

  void SetControlPump(std::function<bool()> pump) override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    backend_.SetControlPump(std::move(pump));
  }

  void Close() override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    backend_.Close();
  }

  bool IsOpen() const override {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return backend_.IsOpen();
  }

  bool ObservationFailed() const { return failed_; }

 private:
  void Observe() {
    const std::string request = directory_ + "/snapshot-request";
    std::uint64_t previous = 0;
    std::size_t count = 0;
    ino_t last_inode = 0;
    try {
      while (!stopping_) {
        struct stat status{};
        // An unchanged request needs no open descriptor. After publishing a
        // snapshot, the observer therefore leaves the process FD census idle.
        if (lstat(request.c_str(), &status) == 0 && status.st_ino != last_inode) {
          last_inode = status.st_ino;
          const auto bytes = ReadBounded(request, 64);
          if (!bytes || ++count > 10000) {
            failed_ = true;
            return;
          }
          std::uint64_t serial = 0;
          const auto parsed = std::from_chars(bytes->data(), bytes->data() + bytes->size(), serial);
          if (parsed.ec != std::errc{} || parsed.ptr != bytes->data() + bytes->size() ||
              serial <= previous || std::to_string(serial) != *bytes) {
            failed_ = true;
            return;
          }
          previous = serial;
          Json observation;
          {
            // The same thread may dispatch cancellation while an SDK call is
            // waiting. Recursive ownership preserves that production control path.
            std::lock_guard<std::recursive_mutex> lock(mutex_);
            observation = {{"serial", serial}, {"open", backend_.IsOpen()},
                           {"native", Json::parse(backend_.ResourceSnapshotForTesting())}};
          }
          if (!WriteAtomicExclusive(directory_ + "/snapshot-" + *bytes + ".json",
                                    observation.dump())) {
            failed_ = true;
            return;
          }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
      }
    } catch (const std::exception &) {
      failed_ = true;
    }
  }

  SdkControllerBackend backend_;
  const std::string directory_;
  mutable std::recursive_mutex mutex_;
  std::atomic<bool> stopping_{false};
  std::atomic<bool> failed_{false};
  std::thread observer_;
};

} // namespace
} // namespace wotex::matter::resource_testing

int main() {
  using namespace wotex::matter;
  using namespace wotex::matter::resource_testing;
  std::signal(SIGPIPE, SIG_IGN);
  try {
    const auto configuration = Configuration();
    if (!configuration) {
      return 2;
    }
    std::string directory = (*configuration)["directory"].get<std::string>();
    if (configuration->value("process_directory", false)) {
      directory += "/process-" + std::to_string(getpid());
      if (mkdir(directory.c_str(), 0700) != 0) {
        return 2;
      }
    }
    ConfigureStartup(directory, configuration->value("startup_stage", std::string{}),
                      configuration->value("startup_action", std::string{}));
    const auto before = nlohmann::json::parse(SnapshotJson());
    InputLifetime lifetime(STDIN_FILENO);
    int result = 1;
    bool failed = false;
    {
      ObservedBackend backend(directory);
      try {
        result = RunHost(backend, std::cin, std::cout, [&lifetime] { lifetime.Fail(); }, STDIN_FILENO);
      } catch (const std::exception &) {
        result = 1;
      }
      backend.StopObserving();
      failed = backend.ObservationFailed();
    }
    const nlohmann::json observation{{"exit_status", result}, {"observer_failed", failed},
                                     {"before", before},
                                     {"after", nlohmann::json::parse(SnapshotJson())}};
    if (!WriteAtomicExclusive(directory + "/native-result.json", observation.dump())) {
      return 3;
    }
    return failed ? 3 : result;
  } catch (const std::exception &) {
    std::cerr << "resource fixture failed\n";
    return 4;
  }
}
