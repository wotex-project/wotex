#include "sdk.hpp"
#include "flow.hpp"
#include "output.hpp"
#include "streams.hpp"
#include <openthread/platform/logging.h>
#include <sys/poll.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <cerrno>
#include <algorithm>
#include <chrono>
#include <fstream>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#ifdef WOTEX_NATIVE_SANITIZERS
#include <sanitizer/lsan_interface.h>
// A sanitizer host checks leaks explicitly after SDK teardown and before its close
// reply; skipping the duplicate at-exit check keeps a graceful close inside the
// owner's cleanup grace. Explicit environment options still take precedence.
extern "C" const char *__asan_default_options() { return "leak_check_at_exit=0"; }
#endif

extern "C" void otPlatReset(otInstance *) {
  // SDK reset ends this generation. The guardian reaps owned descendants.
  ::_exit(3);
}
// SDK diagnostics cannot disclose radio URLs or Dataset material through syslog.
extern "C" void otPlatLog(otLogLevel, otLogRegion, const char *, ...) {}
extern "C" void otPlatLogOutput(otInstance *, otLogLevel, const char *) {}

using namespace wotex::thread;
using Clock = std::chrono::steady_clock;
static volatile sig_atomic_t stopping = 0;
static void stop(int) { stopping = 1; }

static void nonblocking(int fd) {
  if (::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK) < 0 ||
      ::fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) throw SdkError("io_failed");
}

#ifdef WOTEX_THREAD_FLOW_TESTING
// Test-only State callback source for process-flow evidence. It is compiled only into
// `wotex-thread-flow-host`; the production host has no such input. Its configuration is
// `<executable>.flow.json` beside the executable, because the owner clears the environment.
class FlowSource final {
 public:
  FlowSource() {
    char path[4096];
    const ssize_t length = ::readlink("/proc/self/exe", path, sizeof path - 1);
    if (length <= 0) throw SdkError("flow_source_unavailable");
    std::ifstream file(std::string(path, static_cast<std::size_t>(length)) + ".flow.json", std::ios::binary);
    std::string bytes;
    char byte = 0;
    while (file.get(byte) && bytes.size() < 4096) bytes.push_back(byte);
    if (!file.eof() && bytes.size() >= 4096) throw SdkError("flow_source_unavailable");
    const Json config = parse_line(bytes);
    if (!exact_keys(config, {"callback_count", "value_bytes", "callbacks_per_iteration", "gate_path", "result_path"}) ||
        !config.at("callback_count").is_number_unsigned() || config.at("callback_count").get<std::uint64_t>() == 0 ||
        config.at("callback_count").get<std::uint64_t>() > 1000000 || !config.at("value_bytes").is_number_unsigned() ||
        config.at("value_bytes").get<std::uint64_t>() > 4096 || !config.at("callbacks_per_iteration").is_number_unsigned() ||
        config.at("callbacks_per_iteration").get<std::uint64_t>() == 0 ||
        config.at("callbacks_per_iteration").get<std::uint64_t>() > 1024 || !bounded_string(config.at("gate_path"), 4096) ||
        !bounded_string(config.at("result_path"), 4096)) throw SdkError("flow_source_unavailable");
    count_ = config.at("callback_count").get<std::uint64_t>();
    value_bytes_ = config.at("value_bytes").get<std::size_t>();
    per_iteration_ = config.at("callbacks_per_iteration").get<std::uint64_t>();
    gate_ = config.at("gate_path").get<std::string>();
    result_ = config.at("result_path").get<std::string>();
  }
  // Pads a State value with JSON whitespace to the configured encoded size.
  std::string encode(const Json &value) const {
    std::string encoded = value.dump();
    if (encoded.size() > value_bytes_) throw SdkError("flow_source_value_limit");
    encoded.insert(encoded.size() - 1, value_bytes_ - encoded.size(), ' ');
    return encoded;
  }
  bool active() const { return started_ && callbacks_ < count_; }
  bool waiting() const { return !started_; }
  // Starts after the harness gate once a stream exists, then records one iteration.
  void step(StateStreams &streams) {
    if (!started_) {
      struct stat info {};
      if (streams.size() == 0 || ::stat(gate_.c_str(), &info) != 0) return;
      started_ = true;
      started_at_ = std::chrono::steady_clock::now();
    }
    if (callbacks_ >= count_) return;
    for (std::uint64_t index = 0; index < per_iteration_ && callbacks_ < count_; ++index) {
      streams.changed(1);
      ++callbacks_;
    }
    ++iterations_;
  }
  bool complete() const { return started_ && callbacks_ == count_ && !written_; }
  void write(const ReportFlow &flow, const StateStreams &streams, const Output &output) {
    written_ = true;
    const auto maximum = flow.maximum();
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started_at_);
    const Json result = {
        {"callbacks", callbacks_}, {"iterations", iterations_}, {"elapsed_us", elapsed.count()},
        {"reports_assigned", flow.snapshot().last_sequence}, {"stream_errors", streams.stream_errors()},
        {"retirements", streams.retirements()}, {"live_streams", streams.size()},
        {"maximum", {{"queued_reports", maximum.queued}, {"queued_report_bytes", maximum.queued_bytes},
                     {"outstanding_reports", maximum.outstanding}, {"outstanding_report_bytes", maximum.outstanding_bytes},
                     {"output_report_frames", output.maximum(Lane::report).frames},
                     {"output_report_bytes", output.maximum(Lane::report).bytes},
                     {"output_control_frames", output.maximum(Lane::control).frames},
                     {"output_control_bytes", output.maximum(Lane::control).bytes},
                     {"output_reply_frames", output.maximum(Lane::reply).frames},
                     {"output_reply_bytes", output.maximum(Lane::reply).bytes}}}};
    const std::string bytes = result.dump() + "\n";
    FileDescriptor file(::open(result_.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600));
    if (file.get() < 0 || ::write(file.get(), bytes.data(), bytes.size()) != static_cast<ssize_t>(bytes.size())) {
      throw SdkError("flow_source_result");
    }
  }

 private:
  std::uint64_t count_ = 0, per_iteration_ = 0, callbacks_ = 0, iterations_ = 0;
  std::size_t value_bytes_ = 0;
  std::string gate_, result_;
  bool started_ = false, written_ = false;
  std::chrono::steady_clock::time_point started_at_{};
};
#endif

class Worker final {
 public:
  Worker() {
    output_fd_ = ::dup(STDOUT_FILENO);
    if (output_fd_ < 0) throw SdkError("io_failed");
    nonblocking(output_fd_); nonblocking(STDIN_FILENO);
    FileDescriptor sink(::open("/dev/null", O_WRONLY | O_CLOEXEC));
    if (sink.get() < 0 || ::dup2(sink.get(), STDOUT_FILENO) < 0 ||
        ::dup2(sink.get(), STDERR_FILENO) < 0) throw SdkError("io_failed");
#ifdef WOTEX_THREAD_FLOW_TESTING
    source_.emplace();
#endif
    emit(Lane::control, ready());
  }
  ~Worker() { if (output_fd_ >= 0) (void)::close(output_fd_); }
  int run() {
    while (!closing_ || !output_.empty()) {
      otSysMainloopContext loop {};
      loop.mMaxFd = std::max(STDIN_FILENO, output_fd_);
      loop.mTimeout = {0, 50000};
      if (!closing_) FD_SET(STDIN_FILENO, &loop.mReadFdSet);
      if (!output_.empty()) FD_SET(output_fd_, &loop.mWriteFdSet);
      if (sdk_) sdk_->update(loop);
#ifdef WOTEX_THREAD_FLOW_TESTING
      // Poll the harness gate within about 1 ms, then produce without waiting.
      if (source_->active()) loop.mTimeout = {0, 0};
      else if (source_->waiting()) loop.mTimeout = {0, 1000};
#endif
      const int result = ::select(loop.mMaxFd + 1, &loop.mReadFdSet, &loop.mWriteFdSet,
                                  &loop.mErrorFdSet, &loop.mTimeout);
      if (result < 0 && errno == EINTR) continue;
      if (result < 0) return 2;
      if (sdk_) sdk_->process(loop);
#ifdef WOTEX_THREAD_FLOW_TESTING
      if (streams_) source_->step(*streams_);
#endif
      publish_state();
#ifdef WOTEX_THREAD_FLOW_TESTING
      if (streams_ && source_->complete()) source_->write(*flow_, *streams_, output_);
#endif
      finish_formation();
      finish_management();
      finish_commissioner();
      finish_joiner();
      if (FD_ISSET(output_fd_, &loop.mWriteFdSet) && output_.flush(output_fd_) == Output::Flush::failed) return 2;
      if (!closing_ && FD_ISSET(STDIN_FILENO, &loop.mReadFdSet)) input();
      if (flow_ && flow_->failed()) throw ChannelError();
    }
    return 0;
  }
 private:
  // A frame that exceeds its lane reservation ends this generation; dispatch
  // cannot convert that channel failure into an operation error.
  void emit(Lane lane, const Json &value) {
    if (!output_.push(lane, value.dump())) throw ChannelError();
  }
  void reply(const Json &value) { emit(Lane::reply, value); }
  void input() {
    char bytes[4096]; const ssize_t count = ::read(STDIN_FILENO, bytes, sizeof bytes);
    if (count == 0) {
      if (!incoming_.empty()) throw ProtocolError();
      forming_.reset();
      petitioning_.reset();
      joining_.reset();
      sdk_.reset();
      closing_ = true;
      return;
    }
    if (count < 0) {
      if (errno == EAGAIN || errno == EINTR) return;
      throw SdkError("io_failed");
    }
    for (ssize_t i = 0; i < count; ++i) {
      if (incoming_.size() == kMaximumLine) throw ProtocolError();
      incoming_.push_back(bytes[i]);
      if (bytes[i] == '\n') {
        const Json frame = parse_line(incoming_); incoming_.clear();
        if (is_control_frame(frame)) {
          control(flow_control(frame));
        } else {
          // Flow initialization precedes every operation, including open.
          if (!flow_) throw ProtocolError();
          dispatch(request(frame));
        }
        if (closing_ && i != count - 1) throw ProtocolError();
      }
    }
  }
  void control(const FlowControl &frame) {
    if (frame.kind == FlowControl::Kind::flow_open) {
      if (flow_) throw ProtocolError();
      flow_.emplace(
          frame.session_generation,
          [this](const std::string &report) { return output_.push(Lane::report, report); },
          [this](const std::string &barrier) { return output_.push(Lane::control, barrier); });
#ifdef WOTEX_THREAD_FLOW_TESTING
      streams_.emplace(
          *flow_, [this](const std::string &frame) { return output_.push(Lane::control, frame); },
          [this](const Json &value) { return source_->encode(value); });
#else
      streams_.emplace(*flow_, [this](const std::string &frame) { return output_.push(Lane::control, frame); });
#endif
    } else if (!flow_ || !flow_->acknowledge(frame.session_generation, frame.report_sequence,
                                             frame.acknowledged_bytes)) {
      throw ProtocolError();
    }
  }
  // One coalesced snapshot per event-loop iteration carries the OR of its SDK flags.
  void publish_state() {
    if (!sdk_ || !streams_) return;
    streams_->changed(sdk_->take_changed_flags());
    streams_->flush([this] { return sdk_->snapshot(); });
    if (streams_->failed()) throw ChannelError();
  }
  void dispatch(const Request &command) {
    try {
      if (command.operation == "open") {
        if (sdk_) throw SdkError("already_open");
        sdk_ = std::make_unique<Sdk>(command.parameters);
        reply(success(command, sdk_->snapshot()));
      } else if (command.operation == "close") {
        if (!command.parameters.empty()) throw ProtocolError();
        forming_.reset();
        petitioning_.reset();
        joining_.reset();
        sdk_.reset();
#ifdef WOTEX_NATIVE_SANITIZERS
        // Check explicit, fully torn-down sessions before acknowledging close.
        __lsan_do_leak_check();
#endif
        emit(Lane::control, success(command, nullptr)); closing_ = true;
      } else if (command.operation == "inspect" || command.operation == "state" ||
                 command.operation == "version" || command.operation == "network_name" || command.operation == "rloc16") {
        if (!command.parameters.empty()) throw ProtocolError();
        if (!sdk_) throw SdkError("not_open");
        reply(success(command, sdk_->inspect(command.operation)));
      } else if (command.operation == "form_network") {
        if (!sdk_) throw SdkError("not_open");
        if (forming_ || (sdk_ && sdk_->management_busy())) throw SdkError("busy");
        const auto deadline = Clock::now() + std::chrono::milliseconds(command.timeout_ms);
        sdk_->form_network(command.parameters);
        forming_ = Formation{Request{command.id, command.operation, Json::object(), command.timeout_ms}, deadline};
      } else if (command.operation == "management_active_set" || command.operation == "management_pending_set") {
        if (!sdk_) throw SdkError("not_open");
        if (forming_ || sdk_->management_busy()) throw SdkError("busy");
        sdk_->management_set(command);
      } else if (command.operation == "commissioner_start") {
        if (!command.parameters.empty()) throw ProtocolError();
        if (!sdk_) throw SdkError("not_open");
        if (forming_ || sdk_->management_busy() || petitioning_) throw SdkError("busy");
        const auto deadline = Clock::now() + std::chrono::milliseconds(command.timeout_ms);
        sdk_->commissioning().start();
        petitioning_ = Formation{command, deadline};
      } else if (command.operation == "commissioner_stop") {
        if (!command.parameters.empty()) throw ProtocolError();
        if (!sdk_) throw SdkError("not_open");
        sdk_->commissioning().stop();
        if (petitioning_) { reject(petitioning_->command, "cancelled"); petitioning_.reset(); }
        reply(success(command, {{"state", "disabled"}}));
      } else if (command.operation == "add_joiner" || command.operation == "remove_joiner") {
        if (!sdk_) throw SdkError("not_open");
        if (command.operation == "add_joiner") {
          sdk_->commissioning().add(command.parameters);
          reply(success(command, {{"identity", command.parameters.at("identity")},
                                   {"lifetime_s", command.parameters.at("lifetime")}}));
        } else {
          sdk_->commissioning().remove(command.parameters);
          reply(success(command, nullptr));
        }
      } else if (command.operation == "joiner_start") {
        if (!sdk_) throw SdkError("not_open");
        if (joining_) throw SdkError("busy");
        const auto deadline = Clock::now() + std::chrono::milliseconds(command.timeout_ms);
        sdk_->joiner().start(command.parameters);
        joining_ = Formation{
            Request{command.id, command.operation, Json::object(), command.timeout_ms}, deadline};
      } else if (command.operation == "joiner_stop") {
        if (!command.parameters.empty()) throw ProtocolError();
        if (!sdk_) throw SdkError("not_open");
        sdk_->joiner().stop();
        if (joining_) {
          reject(joining_->command, "cancelled");
          joining_.reset();
        }
        reply(success(command, nullptr));
      } else if (command.operation == "set_enabled") {
        if (forming_ || (sdk_ && sdk_->management_busy())) throw SdkError("busy");
        if (!sdk_) throw SdkError("not_open");
        reply(success(command, sdk_->set_enabled(command.parameters)));
        // NOLINTBEGIN(bugprone-unchecked-optional-access): commands dispatch only after
        // flow_open, which emplaces streams_ together with flow_.
      } else if (command.operation == "subscribe_state") {
        const Json &limit = command.parameters.contains("queue_limit") ? command.parameters.at("queue_limit") : Json();
        if (!exact_keys(command.parameters, {"queue_limit"}) || !limit.is_number_unsigned() ||
            limit.get<std::uint64_t>() < 1 || limit.get<std::uint64_t>() > kMaximumQueueLimit) throw ProtocolError();
        if (!sdk_) throw SdkError("not_open");
        const std::uint64_t generation = streams_->open(command.id, limit.get<std::size_t>());
        if (generation == 0) throw SdkError("busy");
        // The owner registers the stream from this reply before its initial report arrives.
        reply(success(command, {{"subscription_id", command.id}, {"generation", generation}}));
        streams_->initial(command.id, generation, sdk_->snapshot());
        if (streams_->failed()) throw ChannelError();
      } else if (command.operation == "unsubscribe") {
        const Json &parameters = command.parameters;
        if (!exact_keys(parameters, {"subscription_id", "generation"}) ||
            !bounded_string(parameters.at("subscription_id"), 128) ||
            !parameters.at("generation").is_number_unsigned() ||
            parameters.at("generation").get<std::uint64_t>() == 0) throw ProtocolError();
        if (!streams_->remove(parameters.at("subscription_id").get<std::string>(),
                              parameters.at("generation").get<std::uint64_t>())) {
          if (streams_->failed()) throw ChannelError();
          throw SdkError("subscription_not_found");
        }
        reply(success(command, nullptr));
        // NOLINTEND(bugprone-unchecked-optional-access)
      } else if (command.operation == "validate_dataset" || command.operation == "get_dataset") {
        if (!sdk_) throw SdkError("not_open");
        reply(success(command, sdk_->dataset(command.operation, command.parameters)));
      } else {
        throw SdkError("not_supported");
      }
    } catch (otError error) {
      reject(command, "remote_error", static_cast<unsigned>(error));
    } catch (const CommissioningError &error) {
      reject(command, error.what());
    } catch (const JoinerError &error) {
      reject(command, error.what());
    } catch (const DatasetError &) {
      reject(command, "invalid_dataset");
    } catch (const ProtocolError &) {
      reject(command, "invalid_request");
    } catch (const StorageError &) {
      reject(command, "storage_unavailable");
    } catch (const SdkError &error) {
      reject(command, error.what());
    }
  }
  void reject(const Request &command, std::string_view code, std::optional<unsigned> status = {}) {
    Json response = failure(command, code);
    if (status) response["error"]["status"] = *status;
    if (command.operation == "form_network" && sdk_) response["error"]["state"] = sdk_->snapshot();
    emit(Lane::control, response);
  }
  void finish_formation() {
    if (!forming_) return;
    if (Clock::now() >= forming_->deadline) {
      reject(forming_->command, "formation_timeout");
      forming_.reset();
    } else {
      Json state = sdk_->snapshot();
      if (state.at("role") == "leader") {
        reply(success(forming_->command, state));
        forming_.reset();
      }
    }
  }
  void finish_management() {
    if (!sdk_) return;
    const auto result = sdk_->management_result();
    if (!result) return;
    if (result->outcome == ManagementOwner::Outcome::timed_out) {
      reject(result->command, "management_timeout");
    } else if (result->outcome == ManagementOwner::Outcome::accepted) {
      reply(success(result->command, {{"accepted", true}, {"effective", "not_verified"}}));
    } else {
      reject(result->command, "remote_error", result->status);
    }
  }
  void finish_commissioner() {
    if (!petitioning_) return;
    if (Clock::now() >= petitioning_->deadline) {
      sdk_->commissioning().stop();
      reject(petitioning_->command, "commissioner_timeout");
      petitioning_.reset();
    } else {
      const auto state = sdk_->commissioning().observed_state();
      if (state == OT_COMMISSIONER_STATE_ACTIVE) {
        reply(success(petitioning_->command, {{"state", "active"}}));
        petitioning_.reset();
      } else if (state == OT_COMMISSIONER_STATE_DISABLED) {
        sdk_->commissioning().stop();
        reject(petitioning_->command, "commissioner_rejected");
        petitioning_.reset();
      }
    }
  }
  void finish_joiner() {
    if (!joining_) return;
    if (Clock::now() >= joining_->deadline) {
      sdk_->joiner().stop();
      reject(joining_->command, "joiner_timeout");
      joining_.reset();
      return;
    }
    const auto result = sdk_->joiner().take_result();
    if (!result) return;
    if (*result == OT_ERROR_NONE) {
      reply(success(joining_->command, {{"joined", true}}));
    } else {
      reject(joining_->command, "remote_error", static_cast<unsigned>(*result));
    }
    joining_.reset();
  }
  struct Formation { Request command; Clock::time_point deadline; };
  std::optional<Formation> forming_, petitioning_, joining_;
  int output_fd_ = -1;
  Output output_;
  std::optional<ReportFlow> flow_;
  std::optional<StateStreams> streams_;
#ifdef WOTEX_THREAD_FLOW_TESTING
  std::optional<FlowSource> source_;
#endif
  std::unique_ptr<Sdk> sdk_;
  std::string incoming_;
  bool closing_ = false;
};

// The guardian remains responsive while SDK startup or teardown is blocked.
// A Linux subreaper owns orphaned forkpty descendants when the SDK worker exits.
static int reap_descendants(pid_t worker) {
  int worker_status = 0;
  bool worker_reaped = false;
  const auto grace = Clock::now() + std::chrono::milliseconds(25);
  do {
    int status = 0;
    const pid_t result = ::waitpid(worker, &status, WNOHANG);
    if (result == worker) {
      worker_status = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
      worker_reaped = true; break;
    }
    if (result < 0 && errno == ECHILD) { worker_reaped = true; break; }
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  } while (Clock::now() < grace);
  if (!worker_reaped) (void)::kill(-worker, SIGKILL);
  const auto deadline = Clock::now() + std::chrono::milliseconds(850);
  do {
    std::ifstream children("/proc/self/task/" + std::to_string(::getpid()) + "/children");
    pid_t child = 0; std::size_t count = 0;
    while (children >> child && count++ < 64) if (child > 0) (void)::kill(child, SIGKILL);
    int status = 0;
    pid_t reaped = 0;
    while ((reaped = ::waitpid(-1, &status, WNOHANG)) > 0) {
      if (reaped == worker) worker_status = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
    if (reaped == -1 && errno == ECHILD) return worker_status;
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  } while (Clock::now() < deadline);
  return 2;
}

static int guardian(pid_t child, int input, int output) {
  struct sigaction action {};
  action.sa_handler = stop;
  sigemptyset(&action.sa_mask);
  if (::sigaction(SIGTERM, &action, nullptr) != 0 || ::sigaction(SIGINT, &action, nullptr) != 0) {
    throw SdkError("io_failed");
  }
  nonblocking(STDIN_FILENO); nonblocking(STDOUT_FILENO); nonblocking(input); nonblocking(output);
  std::string to_worker, to_owner, owner_fragment;
  bool owner_eof = false, child_eof = false;
  auto deadline = Clock::time_point::max();
  int outcome = 0;
  while (!child_eof || !to_owner.empty()) {
    if (stopping && !owner_eof) {
      owner_eof = true;
      deadline = Clock::now() + std::chrono::milliseconds(50);
    }
    if (Clock::now() >= deadline) { outcome = 2; break; }
    pollfd descriptors[4] = {
      {owner_eof ? -1 : STDIN_FILENO, static_cast<short>(!owner_eof && to_worker.size() < kMaximumLine ? POLLIN : 0), 0},
      {child_eof ? -1 : output, static_cast<short>(!child_eof && to_owner.size() < kMaximumLine ? POLLIN : 0), 0},
      {input, static_cast<short>(!to_worker.empty() ? POLLOUT : 0), 0},
      {STDOUT_FILENO, static_cast<short>(!to_owner.empty() ? POLLOUT : 0), 0}
    };
    int result = ::poll(descriptors, 4, 25);
    if (result < 0 && errno == EINTR) continue;
    if (result < 0) { outcome = 2; break; }
    for (std::size_t index = 0; index < 2; ++index) {
      if (!(descriptors[index].revents & (POLLIN | POLLHUP | POLLERR))) continue;
      if (descriptors[index].revents & (POLLHUP | POLLERR)) {
        if (deadline == Clock::time_point::max()) deadline = Clock::now() + std::chrono::milliseconds(50);
      }
      char bytes[4096];
      std::string &buffer = index == 0 ? to_worker : to_owner;
      const std::size_t capacity = kMaximumLine - buffer.size();
      if (capacity == 0) {
        if (index == 0 && (descriptors[index].revents & (POLLHUP | POLLERR))) {
          owner_eof = true; outcome = 2;
        }
        continue;
      }
      const ssize_t count = ::read(descriptors[index].fd, bytes, std::min(sizeof bytes, capacity));
      if (count > 0) {
        if (index == 0) {
          for (ssize_t i = 0; i < count; ++i) {
            if (owner_fragment.size() == kMaximumLine) throw ProtocolError();
            owner_fragment.push_back(bytes[i]);
            if (bytes[i] == '\n') {
              validate_inbound(parse_line(owner_fragment)); owner_fragment.clear();
            }
          }
        }
        buffer.append(bytes, static_cast<std::size_t>(count));
      }
      else if (count == 0 || (errno != EINTR && errno != EAGAIN)) {
        if (index == 0) {
          owner_eof = true; deadline = Clock::now() + std::chrono::milliseconds(50);
          if (!owner_fragment.empty()) outcome = 2;
        }
        else { child_eof = true; deadline = Clock::now() + std::chrono::milliseconds(50); }
      }
    }
    for (std::size_t index = 2; index < 4; ++index) {
      if (!(descriptors[index].revents & (POLLOUT | POLLHUP | POLLERR))) continue;
      std::string &buffer = index == 2 ? to_worker : to_owner;
      if (buffer.empty()) continue;
      const ssize_t count = ::write(descriptors[index].fd, buffer.data(), buffer.size());
      if (count > 0) buffer.erase(0, static_cast<std::size_t>(count));
      else if (count < 0 && errno != EINTR && errno != EAGAIN) { outcome = 2; child_eof = true; to_owner.clear(); }
    }
    if (owner_eof && input >= 0) { (void)::close(input); input = -1; to_worker.clear(); }
  }
  if (input >= 0) (void)::close(input);
  (void)::close(output);
  const int child_status = reap_descendants(child);
  return outcome == 0 ? child_status : outcome;
}

int main() {
  (void)::signal(SIGPIPE, SIG_IGN);
  if (::prctl(PR_SET_CHILD_SUBREAPER, 1) != 0) return 2;
  int input[2], output[2];
  if (::pipe2(input, O_CLOEXEC) != 0) return 2;
  if (::pipe2(output, O_CLOEXEC) != 0) { (void)::close(input[0]); (void)::close(input[1]); return 2; }
  const pid_t guardian_pid = ::getpid();
  const pid_t worker = ::fork();
  if (worker < 0) return 2;
  if (worker == 0) {
    (void)::setpgid(0, 0);
    if (::prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || ::getppid() != guardian_pid) ::_exit(2);
    (void)::close(input[1]); (void)::close(output[0]);
    if (::dup2(input[0], STDIN_FILENO) < 0 || ::dup2(output[1], STDOUT_FILENO) < 0) ::_exit(2);
    (void)::close(input[0]); (void)::close(output[1]);
    int outcome = 2;
    // NOLINTNEXTLINE(bugprone-empty-catch): an exception leaves outcome 2, the failure status.
    try { Worker host; outcome = host.run(); } catch (const std::exception &) {}
    ::_exit(outcome);
  }
  (void)::setpgid(worker, worker);
  (void)::close(input[0]); (void)::close(output[1]);
  try { return guardian(worker, input[1], output[0]); }
  catch (const std::exception &) { reap_descendants(worker); return 2; }
}
