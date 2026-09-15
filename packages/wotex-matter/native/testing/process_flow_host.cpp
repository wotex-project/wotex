#include "wotex_matter/controller.hpp"
#include "wotex_matter/flow_testing.hpp"
#include "wotex_matter/input_lifetime.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <mutex>
#include <optional>
#include <thread>
#include <unistd.h>

namespace wotex::matter::flow_testing {
namespace {

using Json = nlohmann::json;

// One explicitly selected test executable owns this probe. Production targets
// neither link these symbols nor read this test configuration.
struct Probe {
  std::mutex mutex;
  std::string gate_path;
  std::string done_path;
  std::string result_path;
  std::size_t callback_count{0};
  std::size_t value_bytes{0};
  std::size_t callbacks_acquired{0};
  std::size_t callbacks_admitted{0};
  std::size_t callbacks_refused{0};
  std::size_t callbacks_destroyed{0};
  std::size_t iterations{0};
  std::uint64_t source_elapsed_us{0};
  Json counts = Json::object();
  Json maximum = Json::object();

  void Increment(const char *name) {
    std::lock_guard<std::mutex> lock(mutex);
    counts[name] = counts.value(name, std::size_t{0}) + 1;
  }

  void Maximum(const char *name, std::size_t value) {
    maximum[name] = std::max(maximum.value(name, std::size_t{0}), value);
  }
};

Probe probe;

bool WriteExclusive(const std::string &path, const std::string &contents) {
  const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
  if (fd < 0) {
    return false;
  }
  std::size_t offset = 0;
  while (offset < contents.size()) {
    const auto written = write(fd, contents.data() + offset, contents.size() - offset);
    if (written <= 0) {
      close(fd);
      return false;
    }
    offset += static_cast<std::size_t>(written);
  }
  const bool synced = fsync(fd) == 0;
  return close(fd) == 0 && synced;
}

bool Configure() {
  const char *path = std::getenv("WOTEX_MATTER_FLOW_CONFIG");
  if (!path) {
    return false;
  }
  std::ifstream file(path);
  std::string contents(8193, '\0');
  file.read(contents.data(), contents.size());
  contents.resize(static_cast<std::size_t>(file.gcount()));
  if (contents.size() > 8192) {
    return false;
  }
  const Json configuration = Json::parse(contents, nullptr, false);
  if (!configuration.is_object() || configuration.size() != 4 ||
      !configuration.contains("input")) {
    return false;
  }
  const auto &input = configuration["input"];
  if (!input.is_object() || input.size() != 7 ||
      input.value("callback_count", 0) != 10000 ||
      input.value("callbacks_per_iteration", 0) != 1 ||
      input.value("value_bytes", 0) != 128 ||
      input.value("queue_limit", 0) != 64 ||
      input.value("resume_at_ms", 0) != 50 ||
      input.value("observe_until_ms", 0) != 1050) {
    return false;
  }
  const auto suspended = input.value("suspend", std::string{});
  if (suspended != "connection" && suspended != "stream_owner" &&
      suspended != "receiver") {
    return false;
  }
  for (const char *key : {"gate_path", "done_path", "result_path"}) {
    if (!configuration.contains(key) || !configuration[key].is_string() ||
        configuration[key].get<std::string>().empty() ||
        configuration[key].get<std::string>()[0] != '/') {
      return false;
    }
  }
  probe.gate_path = configuration["gate_path"].get<std::string>();
  probe.done_path = configuration["done_path"].get<std::string>();
  probe.result_path = configuration["result_path"].get<std::string>();
  probe.callback_count = input["callback_count"].get<std::size_t>();
  probe.value_bytes = input["value_bytes"].get<std::size_t>();
  return true;
}

class CallbackSource final : public ControllerBackend {
 public:
  ~CallbackSource() override { Close(); }

  BackendResult Open(const NativeOpenOptions &options) override {
    return backend_.Open(options);
  }
  InteractionResponse Interact(const InteractionRequest &request) override {
    return backend_.Interact(request);
  }
  CommissioningResponse Commission(const CommissioningRequest &request) override {
    return backend_.Commission(request);
  }
  CommissioningWindowResponse OpenWindow(const CommissioningWindowRequest &request) override {
    return backend_.OpenWindow(request);
  }
  bool IsOpen() const override { return backend_.IsOpen(); }

  void SetSubscriptionSinks(ReportSink report, StatusSink status, FailureSink failure) override {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      report_sink_ = std::move(report);
    }
    backend_.SetSubscriptionSinks(
        [this](const SubscriptionReport &value) {
          ReportSink sink;
          {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!initial_) {
              initial_ = value;
            }
            sink = report_sink_;
          }
          probe.Increment("sdk_reports");
          return sink && sink(value);
        },
        std::move(status), std::move(failure));
  }

  SubscriptionResponse Subscribe(const SubscriptionRequest &request) override {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      request_ = request;
    }
    const auto result = backend_.Subscribe(request);
    if (result.ok) {
      probe.Increment("sdk_subscriptions_acquired");
    }
    return result;
  }

  bool ActivateSubscription(const std::string &identity, std::uint64_t generation) override {
    if (!backend_.ActivateSubscription(identity, generation) || producer_.joinable()) {
      return false;
    }
    producer_ = std::thread([this] { Produce(); });
    return true;
  }

  BackendResult CancelSubscription(const std::string &identity, std::uint64_t generation,
                                   std::uint32_t timeout) override {
    probe.Increment("sdk_cancellation_attempts");
    const auto result = backend_.CancelSubscription(identity, generation, timeout);
    if (result.ok) {
      probe.Increment("sdk_cancellations_completed");
    }
    return result;
  }

  void Close() override {
    stopping_ = true;
    if (producer_.joinable()) {
      producer_.join();
    }
    if (backend_.IsOpen()) {
      backend_.Close();
      probe.Increment("sdk_controllers_closed");
    }
  }

 private:
  void Produce() {
    probe.Increment("sources_acquired");
    std::optional<SubscriptionReport> initial;
    SubscriptionRequest request;
    ReportSink sink;
    while (!stopping_) {
      if (access(probe.gate_path.c_str(), F_OK) == 0) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (initial_ && report_sink_) {
          initial = initial_;
          request = request_;
          sink = report_sink_;
          break;
        }
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    if (initial) {
      const auto started = std::chrono::steady_clock::now();
      // The native producer owns one event-loop cursor and one callback value.
      // It never allocates a callback-count-sized queue. Each iteration attempts
      // one distinct report, including callbacks after the stream is retired.
      for (std::size_t iteration = 0; iteration < probe.callback_count; ++iteration) {
        {
          SubscriptionReport report = *initial;
          report.report_id += iteration + 1;
          report.initial = false;
          ++probe.callbacks_acquired;
          if (!valid_subscription_report(request, report)) {
            probe.Increment("invalid_callback_values");
          }
          if (sink(report)) {
            ++probe.callbacks_admitted;
          } else {
            ++probe.callbacks_refused;
          }
        }
        ++probe.callbacks_destroyed;
        ++probe.iterations;
        std::this_thread::yield();
      }
      bool native_terminal = false;
      {
        std::lock_guard<std::mutex> lock(probe.mutex);
        native_terminal = probe.counts.value("native_terminals", 0) > 0;
      }
      if (native_terminal) {
        (void) CancelSubscription(initial->subscription_id, initial->generation, 500);
      }
      probe.source_elapsed_us = static_cast<std::uint64_t>(
          std::chrono::duration_cast<std::chrono::microseconds>(
              std::chrono::steady_clock::now() - started).count());
      if (!WriteExclusive(probe.done_path, "complete\n")) {
        probe.Increment("source_completion_write_failures");
      }
    }
    probe.Increment("sources_destroyed");
  }

  SdkControllerBackend backend_;
  std::mutex mutex_;
  ReportSink report_sink_;
  SubscriptionRequest request_;
  std::optional<SubscriptionReport> initial_;
  std::atomic<bool> stopping_{false};
  std::thread producer_;
};

} // namespace

std::string EncodeReport(const std::string &frame) {
  constexpr char member[] = "\"value\":{\"tag\":\"anonymous\",\"type\":\"boolean\",\"value\":";
  const auto offset = frame.rfind(member);
  if (offset == std::string::npos) {
    probe.Increment("invalid_encoded_values");
    return {};
  }
  const auto boolean_start = offset + sizeof(member) - 1;
  const auto end = frame.find('}', boolean_start);
  if (end == std::string::npos) {
    probe.Increment("invalid_encoded_values");
    return {};
  }
  const auto boolean = frame.substr(boolean_start, end - boolean_start);
  const std::size_t value_bytes = end + 1 - (offset + 8);
  if ((boolean != "true" && boolean != "false") || value_bytes > probe.value_bytes) {
    probe.Increment("invalid_encoded_values");
    return {};
  }
  std::string encoded = frame;
  // JSON whitespace belongs to the encoded value representation. It changes
  // neither the real SDK-derived typed value nor the production decoder.
  encoded.insert(end, probe.value_bytes - value_bytes, ' ');
  probe.Increment("values_encoded");
  return encoded;
}

void ObserveCredit(std::size_t queued, std::size_t queued_bytes,
                   std::size_t outstanding, std::size_t outstanding_bytes) {
  std::lock_guard<std::mutex> lock(probe.mutex);
  probe.Maximum("queued_reports", queued);
  probe.Maximum("queued_report_bytes", queued_bytes);
  probe.Maximum("outstanding_reports", outstanding);
  probe.Maximum("outstanding_report_bytes", outstanding_bytes);
}

void ObserveOutput(const std::string &frame, std::size_t report_frames,
                   std::size_t report_bytes, std::size_t control_frames,
                   std::size_t control_bytes, std::size_t reply_frames,
                   std::size_t reply_bytes) {
  std::lock_guard<std::mutex> lock(probe.mutex);
  probe.Maximum("output_report_frames", report_frames);
  probe.Maximum("output_report_bytes", report_bytes);
  probe.Maximum("output_control_frames", control_frames);
  probe.Maximum("output_control_bytes", control_bytes);
  probe.Maximum("output_reply_frames", reply_frames);
  probe.Maximum("output_reply_bytes", reply_bytes);
  if (frame.find("\"event\":\"subscription_error\"") != std::string::npos) {
    probe.counts["native_terminals"] = probe.counts.value("native_terminals", 0) + 1;
  }
  if (frame.find("\"event\":\"stream_retired\"") != std::string::npos) {
    probe.counts["retirement_barriers"] = probe.counts.value("retirement_barriers", 0) + 1;
  }
  if (frame.find("\"event\":\"subscription_report\"") != std::string::npos) {
    probe.counts["reports_transmitted"] = probe.counts.value("reports_transmitted", 0) + 1;
    if (probe.counts.value("retirement_barriers", 0) > 0 ||
        probe.counts.value("native_terminals", 0) > 0) {
      probe.counts["reports_after_terminal"] = probe.counts.value("reports_after_terminal", 0) + 1;
    }
  }
}

} // namespace wotex::matter::flow_testing

int main() {
  using namespace wotex::matter;
  using namespace wotex::matter::flow_testing;
  std::signal(SIGPIPE, SIG_IGN);
  try {
    if (!Configure()) {
      return 2;
    }
    InputLifetime lifetime(STDIN_FILENO);
    int result = 1;
    {
      CallbackSource backend;
      result = RunHost(backend, std::cin, std::cout, [&lifetime] { lifetime.Fail(); });
    }
    // Joining the producer precedes these reads of its actual loop counters.
    probe.counts["callbacks_acquired"] = probe.callbacks_acquired;
    probe.counts["callbacks_admitted"] = probe.callbacks_admitted;
    probe.counts["callbacks_refused"] = probe.callbacks_refused;
    probe.counts["callbacks_destroyed"] = probe.callbacks_destroyed;
    probe.counts["iterations"] = probe.iterations;
    probe.counts["source_elapsed_us"] = probe.source_elapsed_us;
    const Json observation{{"exit_status", result}, {"counts", probe.counts},
                           {"maximum", probe.maximum}};
    return WriteExclusive(probe.result_path, observation.dump() + "\n") ? result : 3;
  } catch (const std::exception &) {
    std::cerr << "process-flow fixture failed\n";
    return 4;
  }
}
