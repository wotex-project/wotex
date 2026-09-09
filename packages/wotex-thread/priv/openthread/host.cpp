#include "sdk.hpp"
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
#include <string>
#include <thread>
#ifdef WOTEX_NATIVE_SANITIZERS
#include <sanitizer/lsan_interface.h>
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

class Worker final {
 public:
  Worker() {
    output_ = ::dup(STDOUT_FILENO);
    if (output_ < 0) throw SdkError("io_failed");
    nonblocking(output_); nonblocking(STDIN_FILENO);
    FileDescriptor sink(::open("/dev/null", O_WRONLY | O_CLOEXEC));
    if (sink.get() < 0 || ::dup2(sink.get(), STDOUT_FILENO) < 0 ||
        ::dup2(sink.get(), STDERR_FILENO) < 0) throw SdkError("io_failed");
    append(ready());
  }
  ~Worker() { if (output_ >= 0) (void)::close(output_); }
  int run() {
    while (!closing_ || !outgoing_.empty()) {
      otSysMainloopContext loop {};
      loop.mMaxFd = std::max(STDIN_FILENO, output_);
      loop.mTimeout = {0, 50000};
      if (!closing_) FD_SET(STDIN_FILENO, &loop.mReadFdSet);
      if (!outgoing_.empty()) FD_SET(output_, &loop.mWriteFdSet);
      if (sdk_) sdk_->update(loop);
      const int result = ::select(loop.mMaxFd + 1, &loop.mReadFdSet, &loop.mWriteFdSet,
                                  &loop.mErrorFdSet, &loop.mTimeout);
      if (result < 0 && errno == EINTR) continue;
      if (result < 0) return 2;
      if (sdk_) sdk_->process(loop);
      if (FD_ISSET(output_, &loop.mWriteFdSet)) flush();
      if (!closing_ && FD_ISSET(STDIN_FILENO, &loop.mReadFdSet)) input();
    }
    return 0;
  }
 private:
  void append(const Json &value) {
    std::string frame = value.dump() + "\n";
    if (frame.size() > kMaximumLine || outgoing_.size() + frame.size() > kMaximumLine) throw ProtocolError();
    outgoing_ += frame;
  }
  void flush() {
    const ssize_t written = ::write(output_, outgoing_.data(), outgoing_.size());
    if (written > 0) outgoing_.erase(0, static_cast<std::size_t>(written));
    else if (written < 0 && errno != EAGAIN && errno != EINTR) throw SdkError("io_failed");
  }
  void input() {
    char bytes[4096]; const ssize_t count = ::read(STDIN_FILENO, bytes, sizeof bytes);
    if (count == 0) {
      if (!incoming_.empty()) throw ProtocolError();
      sdk_.reset(); closing_ = true; return;
    }
    if (count < 0) {
      if (errno == EAGAIN || errno == EINTR) return;
      throw SdkError("io_failed");
    }
    for (ssize_t i = 0; i < count; ++i) {
      if (incoming_.size() == kMaximumLine) throw ProtocolError();
      incoming_.push_back(bytes[i]);
      if (bytes[i] == '\n') {
        Request command = request(parse_line(incoming_)); incoming_.clear();
        dispatch(command);
        if (closing_ && i != count - 1) throw ProtocolError();
      }
    }
  }
  void dispatch(const Request &command) {
    try {
      if (command.operation == "open") {
        if (sdk_) throw SdkError("already_open");
        sdk_ = std::make_unique<Sdk>(command.parameters);
        append(success(command, sdk_->snapshot()));
      } else if (command.operation == "close") {
        if (!command.parameters.empty()) throw ProtocolError();
        sdk_.reset();
#ifdef WOTEX_NATIVE_SANITIZERS
        // Check explicit, fully torn-down sessions before acknowledging close.
        __lsan_do_leak_check();
#endif
        append(success(command, nullptr)); closing_ = true;
      } else if (command.operation == "inspect" || command.operation == "state" ||
                 command.operation == "version" || command.operation == "network_name" || command.operation == "rloc16") {
        if (!command.parameters.empty()) throw ProtocolError();
        if (!sdk_) throw SdkError("not_open");
        append(success(command, sdk_->inspect(command.operation)));
      } else if (command.operation == "validate_dataset" || command.operation == "get_dataset") {
        if (!sdk_) throw SdkError("not_open");
        append(success(command, sdk_->dataset(command.operation, command.parameters)));
      } else {
        throw SdkError("not_supported");
      }
    } catch (const DatasetError &) { append(failure(command, "invalid_dataset")); }
      catch (const ProtocolError &) { append(failure(command, "invalid_request")); }
      catch (const StorageError &) { append(failure(command, "storage_unavailable")); }
      catch (const SdkError &error) { append(failure(command, error.what())); }
  }
  int output_ = -1;
  std::unique_ptr<Sdk> sdk_;
  std::string incoming_, outgoing_;
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
              (void)request(parse_line(owner_fragment)); owner_fragment.clear();
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
    try { Worker host; outcome = host.run(); } catch (const std::exception &) {}
    ::_exit(outcome);
  }
  (void)::setpgid(worker, worker);
  (void)::close(input[0]); (void)::close(output[1]);
  try { return guardian(worker, input[1], output[0]); }
  catch (const std::exception &) { reap_descendants(worker); return 2; }
}
