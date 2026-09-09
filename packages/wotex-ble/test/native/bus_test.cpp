// SPDX-License-Identifier: Apache-2.0
#include "bus.hpp"
#include "service.hpp"
#include <csignal>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <sys/wait.h>
#include <unistd.h>

using namespace wotex::ble;
static void check(bool value) { if (!value) throw std::runtime_error("bus assertion failed"); }
struct Child {
  pid_t pid = -1;
  ~Child() {
    if (pid <= 0) return;
    kill(pid, SIGTERM);
    const auto deadline = Clock::now() + std::chrono::milliseconds(500);
    while (Clock::now() < deadline) {
      if (waitpid(pid, nullptr, WNOHANG) == pid) return;
      ::poll(nullptr, 0, 1);
    }
    kill(pid, SIGKILL);
    while (waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
  }
};
struct Fd {
  int value = -1;
  ~Fd() { if (value >= 0) ::close(value); }
};
class Daemon {
  Child child_;
public:
  std::string address;
  Daemon(const std::string &executable, const std::string &config) {
    int descriptors[2]; check(pipe(descriptors) == 0);
    Fd input{descriptors[0]}, output{descriptors[1]};
    child_.pid = fork(); check(child_.pid >= 0);
    if (child_.pid == 0) {
      dup2(output.value, 1);
      ::close(input.value); ::close(output.value);
      const int sink = open("/dev/null", O_RDWR);
      if (sink < 0) _exit(126);
      dup2(sink, 0); dup2(sink, 2); ::close(sink);
      const auto argument = "--config-file=" + config;
      execl(executable.c_str(), executable.c_str(), "--nofork", "--nopidfile",
            argument.c_str(), "--print-address=1", static_cast<char *>(nullptr));
      _exit(126);
    }
    ::close(output.value); output.value = -1;
    const auto deadline = Clock::now() + std::chrono::seconds(3);
    while (Clock::now() < deadline && address.size() < 4096) {
      pollfd descriptor{input.value, POLLIN, 0};
      if (::poll(&descriptor, 1, 10) < 0) throw std::runtime_error("daemon poll failed");
      if (!(descriptor.revents & (POLLIN | POLLHUP))) continue;
      char byte;
      check(read(input.value, &byte, 1) == 1);
      if (byte == '\n') return;
      address += byte;
    }
    throw std::runtime_error("daemon startup deadline");
  }
};
static void until(Bus &bus, const std::function<bool()> &done) {
  const auto deadline = Clock::now() + std::chrono::seconds(3);
  while (!done() && Clock::now() < deadline && !bus.failure()) {
    std::vector<pollfd> none;
    bus.poll(none, 10);
  }
  check(done());
}
static void hello(Bus &bus) {
  bool complete = false;
  check(bus.hello(Clock::now() + std::chrono::seconds(2), [&](BusReply reply) {
    check(!reply.error); complete = true;
  }));
  until(bus, [&] { return complete; });
  check(!bus.unique_name().empty());
}
static Message method(const char *name) {
  return Message(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS,
                                             DBUS_INTERFACE_DBUS, name));
}
static std::string id(Bus &bus) {
  bool complete = false;
  std::string result;
  auto request = method("GetId");
  check(bus.call(request.get(), "s", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
    check(!reply.error);
    const char *value = nullptr;
    check(dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID));
    result = value; complete = true;
  }));
  until(bus, [&] { return complete; });
  check(result.size() == 32);
  return result;
}
static bool has_owner(Bus &bus, const std::string &name) {
  auto request = method("NameHasOwner"); const char *argument = name.c_str();
  check(dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &argument, DBUS_TYPE_INVALID));
  bool complete = false; dbus_bool_t result = true;
  check(bus.call(request.get(), "b", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
    check(!reply.error);
    check(dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_BOOLEAN, &result, DBUS_TYPE_INVALID));
    complete = true;
  }));
  until(bus, [&] { return complete; });
  return result;
}
static void match_names(Bus &bus) {
  auto request = method("AddMatch");
  const char *rule = "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'";
  check(dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &rule, DBUS_TYPE_INVALID));
  bool done = false;
  check(bus.call(request.get(), "", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
    check(!reply.error); done = true;
  }));
  until(bus, [&] { return done; });
}
static void name_operation(Bus &bus, bool acquire) {
  auto request = method(acquire ? "RequestName" : "ReleaseName");
  const char *name = "org.bluez";
  check(dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID));
  if (acquire) {
    dbus_uint32_t flags = DBUS_NAME_FLAG_DO_NOT_QUEUE;
    check(dbus_message_append_args(request.get(), DBUS_TYPE_UINT32, &flags, DBUS_TYPE_INVALID));
  }
  bool done = false;
  check(bus.call(request.get(), "u", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
    check(!reply.error);
    dbus_uint32_t result = 0;
    check(dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_UINT32, &result, DBUS_TYPE_INVALID));
    check(result == 1); done = true;
  }));
  until(bus, [&] { return done; });
}
static void until_service(BlueZService &service, const std::function<bool()> &done) {
  const auto deadline = Clock::now() + std::chrono::seconds(3);
  while (!done() && Clock::now() < deadline) {
    std::vector<pollfd> none;
    service.poll(none, 10);
  }
  check(done());
}
static void service_identity(const std::string &address) {
  Bus server(address); hello(server); name_operation(server, true);
  BlueZService service(address);
  unsigned ready = 0, lost = 0;
  check(service.start(Clock::now() + std::chrono::seconds(2),
    [&](const char *error) { check(!error); ++ready; },
    [&](const char *error) { check(error && std::string(error) == "disconnected"); ++lost; }));
  until_service(service, [&] { return ready == 1; });
  check(service.owner() == server.unique_name());
  check(service.owner() != service.bus().unique_name());
  const auto client = service.bus().unique_name();
  check(has_owner(server, client));
  name_operation(server, false);
  Bus replacement(address); hello(replacement); name_operation(replacement, true);
  until_service(service, [&] { return lost == 1; });
  check(!service.active() && service.owner().empty());
  check(service.bus().pending_count() == 0 && service.bus().listener_count() == 0);
  check(!has_owner(replacement, client));
  check(ready == 1 && lost == 1 && has_owner(replacement, "org.bluez"));
  check(!service.start(Clock::now() + std::chrono::seconds(1), [](auto) {}, [](auto) {}));
  service.close(); service.close();

  BlueZService cancelled(address);
  check(cancelled.start(Clock::now() + std::chrono::seconds(1), [&](auto) { ++ready; }, [&](auto) { ++lost; }));
  cancelled.close();
  std::vector<pollfd> none; cancelled.poll(none, 0);
  check(ready == 1 && lost == 1 && cancelled.bus().pending_count() == 0);

  BlueZService expired(address);
  bool timeout = false;
  check(expired.start(Clock::now() + std::chrono::milliseconds(20), [&](const char *error) {
    timeout = error && std::string(error) == "timeout";
  }, [](auto) {}));
  ::poll(nullptr, 0, 40);
  until_service(expired, [&] { return timeout; });
  check(!expired.active() && expired.bus().pending_count() == 0);
  check(has_owner(replacement, "org.bluez"));
}
static void signals(const std::string &address) {
  Bus observer(address); hello(observer);
  unsigned created = 0, removed = 0, foreign = 0, once = 0;
  std::string target;
  const auto listener = observer.listen(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS,
    "NameOwnerChanged", "sss", [&](DBusMessage *message) {
      const char *name = nullptr, *before = nullptr, *after = nullptr;
      check(dbus_message_get_args(message, nullptr, DBUS_TYPE_STRING, &name,
        DBUS_TYPE_STRING, &before, DBUS_TYPE_STRING, &after, DBUS_TYPE_INVALID));
      if (target == name) {
        if (*after) ++created; else ++removed;
      }
    });
  observer.listen(observer.unique_name(), DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS,
    "NameOwnerChanged", "sss", [&](auto) { ++foreign; });
  observer.listen(DBUS_SERVICE_DBUS, "/wrong_path", DBUS_INTERFACE_DBUS,
    "NameOwnerChanged", "sss", [&](auto) { ++foreign; });
  std::uint64_t once_identity = 0;
  once_identity = observer.listen(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS,
    "NameOwnerChanged", "sss", [&](auto) { ++once; observer.unlisten(once_identity); });
  match_names(observer);
  Bus peer(address); hello(peer); target = peer.unique_name();
  until(observer, [&] { return created == 1; });
  check(once == 1 && foreign == 0 && removed == 0);
  peer.close();
  until(observer, [&] { return removed == 1; });
  check(once == 1 && foreign == 0);
  observer.unlisten(listener); observer.unlisten(listener);
  observer.close(); check(observer.listener_count() == 0);

  Bus churn(address); hello(churn);
  for (unsigned i = 0; i < 100000; ++i) {
    const auto identity = churn.listen(DBUS_SERVICE_DBUS, "", DBUS_INTERFACE_DBUS,
      "NameOwnerChanged", "sss", [](auto) {});
    churn.unlisten(identity);
  }
  check(churn.listener_count() == 0);
  for (unsigned i = 0; i < 64; ++i)
    churn.listen(DBUS_SERVICE_DBUS, "", DBUS_INTERFACE_DBUS, "NameOwnerChanged", "sss", [](auto) {});
  bool limited = false;
  try { churn.listen(DBUS_SERVICE_DBUS, "", DBUS_INTERFACE_DBUS, "NameOwnerChanged", "sss", [](auto) {}); }
  catch (const std::runtime_error &error) { limited = std::string(error.what()) == "resource_limit"; }
  check(limited); churn.close(); check(churn.listener_count() == 0);

  Bus malformed(address); hello(malformed);
  malformed.listen(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS,
    "NameOwnerChanged", "", [](auto) { throw std::runtime_error("invalid signal callback"); });
  match_names(malformed);
  Bus next(address); hello(next);
  until(malformed, [&] { return malformed.failure() != nullptr; });
  check(std::string(malformed.failure()) == "invalid_response");
  malformed.close(); next.close();

  Bus closing(address); hello(closing);
  bool closed = false;
  closing.listen(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS,
    "NameOwnerChanged", "sss", [&](auto) { closing.close(); closed = true; });
  match_names(closing);
  Bus trigger(address); hello(trigger);
  until(closing, [&] { return closed; });
  check(closing.listener_count() == 0 && closing.pending_count() == 0 && closing.watch_count() == 0);
}
static void invariants(const std::string &address) {
  for (const auto &invalid : {"", "tcp:host=127.0.0.1,port=123", "unix:path=", "unix:path=,guid=00000000000000000000000000000000",
                              "unix:path=/tmp/x;unix:path=/tmp/y", "unix:path=/tmp/x,guid=x", "unix:path=/tmp/x,key=value",
                              "unix:path=/tmp/x%00y", "unix:path=/tmp/x%", "unix:path=/tmp/x%gg"}) {
    bool rejected = false;
    try { Bus malformed(invalid); }
    catch (const std::invalid_argument &error) { rejected = std::string(error.what()) == "invalid_bus_address"; }
    check(rejected);
  }
  Bus first(address), second(address);
  hello(first); hello(second);
  check(first.unique_name() != second.unique_name());
  const auto first_name = first.unique_name();
  check(has_owner(second, first_name));
  const auto identity = id(first); check(id(second) == identity);
  std::vector<unsigned> correlated(32, 0);
  for (unsigned i = 0; i < correlated.size(); ++i) {
    auto operation = method("GetId");
    check(second.call(operation.get(), "s", Clock::now() + std::chrono::seconds(2), [&, i](BusReply reply) {
      check(!reply.error); ++correlated[i];
    }));
  }
  until(second, [&] { return std::all_of(correlated.begin(), correlated.end(), [](unsigned n) { return n == 1; }); });
  check(second.pending_count() == 0);
  check(!first.hello(Clock::now() + std::chrono::seconds(1), [](auto) {}));
  unsigned completions = 0;
  for (unsigned i = 0; i < 64; ++i) {
    auto request = method("GetId");
    check(first.call(request.get(), "s", Clock::now() + std::chrono::seconds(2), [&](auto) { ++completions; }));
  }
  auto request = method("GetId");
  check(first.pending_count() == 64);
  check(!first.call(request.get(), "s", Clock::now() + std::chrono::seconds(2), [](auto) {}));
  first.close(); first.close();
  check(first.pending_count() == 0 && first.watch_count() == 0 && first.timeout_count() == 0);
  check(completions == 0);
  const auto deadline = Clock::now() + std::chrono::seconds(2);
  while (has_owner(second, first_name) && Clock::now() < deadline) {}
  check(!has_owner(second, first_name));
  check(id(second) == identity);
  bool malformed = false;
  check(second.call(request.get(), "", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
    malformed = reply.error && std::string(reply.error) == "invalid_response";
  }));
  until(second, [&] { return malformed; });
  request = method("GetId");
  bool expired = false;
  check(second.call(request.get(), "s", Clock::now() + std::chrono::milliseconds(20), [&](BusReply reply) {
    expired = reply.error && std::string(reply.error) == "timeout";
  }));
  ::poll(nullptr, 0, 40);
  until(second, [&] { return expired; });
  bool reused = false;
  try { second.call(request.get(), "s", Clock::now() + std::chrono::seconds(1), [](auto) {}); }
  catch (const std::invalid_argument &) { reused = true; }
  check(reused);
  request = method("GetId");
  check(!second.call(request.get(), "s", Clock::now(), [](auto) {}));
  int pipe_fds[2]; check(pipe(pipe_fds) == 0); Fd read_end{pipe_fds[0]}, write_end{pipe_fds[1]};
  check(write(write_end.value, "x", 1) == 1);
  std::vector<pollfd> extra{{read_end.value, POLLIN, 0}};
  second.poll(extra, 10); check(extra[0].revents & POLLIN);
  second.close();
  second.poll(extra, 10); check(extra[0].revents == 0);
  check(write(write_end.value, "x", 1) == 1);
  check(second.pending_count() == 0 && second.watch_count() == 0 && second.timeout_count() == 0);
  Bus callback_owner(address); hello(callback_owner);
  request = method("GetId");
  bool closed = false;
  check(callback_owner.call(request.get(), "s", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
    check(!reply.error); callback_owner.close(); closed = true;
  }));
  until(callback_owner, [&] { return closed; });
  check(callback_owner.pending_count() == 0 && callback_owner.watch_count() == 0 && callback_owner.timeout_count() == 0);
}
int main(int argc, char **argv) {
  if (argc != 3) return 2;
  try {
    Daemon daemon(argv[1], argv[2]);
    invariants(daemon.address);
    signals(daemon.address);
    service_identity(daemon.address);
    dbus_shutdown();
    std::cout << "native bus ownership invariants passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
