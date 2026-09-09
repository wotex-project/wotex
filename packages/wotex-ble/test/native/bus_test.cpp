// SPDX-License-Identifier: Apache-2.0
#include "bus.hpp"
#include "service.hpp"
#include "objects_test.hpp"
#include "discovery_test.hpp"
#include "agent_test.hpp"
#include "pairing_test.hpp"
#include <csignal>
#include <fcntl.h>
#include <dirent.h>
#include <fstream>
#include <iostream>
#include <sys/wait.h>
#include <unistd.h>

using namespace wotex::ble;
static void check_at(bool value, unsigned line) {
  if (!value) throw std::runtime_error("bus assertion failed at line " + std::to_string(line));
}
#define check(value) check_at((value), __LINE__)
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
  void suspend() {
    check(kill(child_.pid, SIGSTOP) == 0);
    int status = 0;
    const auto deadline = Clock::now() + std::chrono::seconds(1);
    while (Clock::now() < deadline) {
      const auto result = waitpid(child_.pid, &status, WUNTRACED | WNOHANG);
      if (result == child_.pid) { check(WIFSTOPPED(status)); return; }
      check(result == 0 || (result == -1 && errno == EINTR));
      ::poll(nullptr, 0, 1);
    }
    check(false);
  }
  void resume() { check(kill(child_.pid, SIGCONT) == 0); }
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
static bool has_owner(Bus &bus, const std::string &name,
                       Deadline deadline = Clock::now() + std::chrono::seconds(1)) {
  auto request = method("NameHasOwner"); const char *argument = name.c_str();
  check(dbus_message_append_args(request.get(), DBUS_TYPE_STRING, &argument, DBUS_TYPE_INVALID));
  bool complete = false; dbus_bool_t result = true;
  check(bus.call(request.get(), "b", deadline, [&](BusReply reply) {
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
    [&](const char *error) { check(error && std::string(error) == "owner_changed"); ++lost; }));
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
  // A different sender's query can reach the daemon before the closed socket's
  // EOF. Observe release within the ownership grace, without assuming ordering
  // between those two connections.
  const auto released_by = Clock::now() + std::chrono::milliseconds(1000);
  while (Clock::now() < released_by && has_owner(replacement, client, released_by)) {}
  check(Clock::now() < released_by);
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
static unsigned descriptor_count() {
  DIR *directory = opendir("/dev/fd"); check(directory != nullptr);
  unsigned count = 0;
  while (const auto *entry = readdir(directory)) {
    if (entry->d_name[0] == '.') continue;
    char *end = nullptr;
    const long descriptor = std::strtol(entry->d_name, &end, 10);
    if (end && !*end && descriptor >= 0 && descriptor <= std::numeric_limits<int>::max() &&
        fcntl(static_cast<int>(descriptor), F_GETFD) >= 0) ++count;
  }
  check(closedir(directory) == 0);
  return count;
}
static void unix_fds(const std::string &address, unsigned amount) {
  // The fault producer uses libdbus directly; production Bus never exports an
  // unbounded/raw send API. The enclosing command guardian bounds this fixture.
  struct RawClose {
    void operator()(DBusConnection *value) const {
      if (value) { dbus_connection_close(value); dbus_connection_unref(value); }
    }
  };
  std::unique_ptr<DBusConnection, RawClose> producer(dbus_connection_open_private(address.c_str(), nullptr));
  check(producer != nullptr);
  dbus_connection_set_exit_on_disconnect(producer.get(), false);
  check(dbus_bus_register(producer.get(), nullptr));
  Bus receiver(address), survivor(address); hello(receiver); hello(survivor);
  unsigned delivered = 0;
  receiver.listen(dbus_bus_get_unique_name(producer.get()), "/org/example", "org.example.Fault",
    "Descriptor", std::string(amount, 'h'), [&](auto) { ++delivered; });
  const auto before = descriptor_count();
  {
    Message signal(dbus_message_new_signal("/org/example", "org.example.Fault", "Descriptor"));
    check(signal != nullptr);
    check(dbus_message_set_destination(signal.get(), receiver.unique_name().c_str()));
    Fd file{open("/dev/null", O_RDONLY)}; check(file.value >= 0);
    for (unsigned i = 0; i < amount; ++i)
      check(dbus_message_append_args(signal.get(), DBUS_TYPE_UNIX_FD, &file.value, DBUS_TYPE_INVALID));
    check(dbus_connection_send(producer.get(), signal.get(), nullptr));
    dbus_connection_flush(producer.get());
  }
  const auto sent = descriptor_count();
  until(receiver, [&] { return receiver.failure() != nullptr; });
  receiver.close();
  const auto after = descriptor_count();
  if (delivered != 0 || after >= before)
    throw std::runtime_error("FD fault: deliveries=" + std::to_string(delivered) +
      " before=" + std::to_string(before) + " sent=" + std::to_string(sent) + " after=" + std::to_string(after));
  check(!id(survivor).empty());
}
static void descriptor_process(const std::string &address) {
  int output_fds[2], owner_fds[2];
  check(pipe(output_fds) == 0); Fd input{output_fds[0]}, output{output_fds[1]};
  check(pipe(owner_fds) == 0); Fd owner_input{owner_fds[0]}, owner_output{owner_fds[1]};
  Child child; child.pid = fork(); check(child.pid >= 0);
  if (child.pid == 0) {
    ::close(input.value); ::close(owner_output.value);
    try {
      Bus receiver(address); hello(receiver);
      const auto name = receiver.unique_name() + "\n";
      if (write(output.value, name.data(), name.size()) != static_cast<ssize_t>(name.size())) _exit(1);
      const auto deadline = Clock::now() + std::chrono::seconds(3);
      while (!receiver.failure() && Clock::now() < deadline) {
        std::vector<pollfd> extra{{owner_input.value, POLLIN, 0}};
        receiver.poll(extra, 10);
        if (extra[0].revents & (POLLIN | POLLHUP | POLLERR)) { receiver.close(); _exit(1); }
      }
      const bool failed = receiver.failure() != nullptr;
      receiver.close();
      // A fatal native channel ends the process, including descriptors that a
      // platform's ancillary-data truncation cannot return to libdbus.
      _exit(failed ? 0 : 1);
    } catch (...) { _exit(1); }
  }
  ::close(output.value); output.value = -1;
  ::close(owner_input.value); owner_input.value = -1;
  std::string destination;
  const auto startup = Clock::now() + std::chrono::seconds(3);
  while (Clock::now() < startup && destination.size() < 255) {
    pollfd descriptor{input.value, POLLIN, 0};
    check(::poll(&descriptor, 1, 10) >= 0);
    if (!(descriptor.revents & (POLLIN | POLLHUP))) continue;
    char byte; check(read(input.value, &byte, 1) == 1);
    if (byte == '\n') break;
    destination += byte;
  }
  check(!destination.empty() && destination[0] == ':' && dbus_validate_bus_name(destination.c_str(), nullptr));
  struct RawClose {
    void operator()(DBusConnection *value) const {
      if (value) { dbus_connection_close(value); dbus_connection_unref(value); }
    }
  };
  std::unique_ptr<DBusConnection, RawClose> producer(dbus_connection_open_private(address.c_str(), nullptr));
  check(producer != nullptr);
  dbus_connection_set_exit_on_disconnect(producer.get(), false);
  check(dbus_bus_register(producer.get(), nullptr));
  Message signal(dbus_message_new_signal("/org/example", "org.example.Fault", "Descriptor"));
  check(signal != nullptr && dbus_message_set_destination(signal.get(), destination.c_str()));
  Fd file{open("/dev/null", O_RDONLY)}; check(file.value >= 0);
  for (unsigned i = 0; i < 2; ++i)
    check(dbus_message_append_args(signal.get(), DBUS_TYPE_UNIX_FD, &file.value, DBUS_TYPE_INVALID));
  const auto deadline = Clock::now() + std::chrono::milliseconds(1000);
  check(dbus_connection_send(producer.get(), signal.get(), nullptr));
  dbus_connection_flush(producer.get());
  while (Clock::now() < deadline) {
    int status = 0;
    const auto result = waitpid(child.pid, &status, WNOHANG);
    if (result == child.pid) {
      child.pid = -1;
      check(WIFEXITED(status) && WEXITSTATUS(status) == 0);
      return;
    }
    check(result == 0 || (result < 0 && errno == EINTR));
    ::poll(nullptr, 0, 1);
  }
  throw std::runtime_error("native descriptor owner exceeded cleanup grace");
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
static void exported_methods(Daemon &daemon) {
  const auto &address = daemon.address;
  // WBL-S02/V06: Agent method ownership is exact at sender, path and interface.
  Bus owner(address), source(address), foreign(address);
  hello(owner); hello(source); hello(foreign);
  const char *path = "/org/wotex/ble/agent_test";
  const char *interface = "org.bluez.Agent1";
  unsigned calls = 0;
  Message deferred;
  auto identity = owner.export_interface(source.unique_name(), path, interface, [&](DBusMessage *request) {
    ++calls;
    check(dbus_message_has_signature(request, ""));
    const std::string member = dbus_message_get_member(request);
    if (member == "Deferred") { deferred.reset(dbus_message_ref(request)); return; }
    Message reply(dbus_message_new_method_return(request));
    if (member == "RequestPasskey") {
      dbus_uint32_t value = 999999;
      check(dbus_message_append_args(reply.get(), DBUS_TYPE_UINT32, &value, DBUS_TYPE_INVALID));
    } else if (member == "RequestPinCode") {
      const char *value = "1234";
      check(dbus_message_append_args(reply.get(), DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID));
    }
    check(owner.respond(std::move(reply)));
  });
  const auto pump = [&](Bus &caller, const std::function<bool()> &done) {
    const auto deadline = Clock::now() + std::chrono::seconds(2);
    while (!done() && Clock::now() < deadline) {
      std::vector<pollfd> none; owner.poll(none, 1); caller.poll(none, 1);
      check(!owner.failure() && !caller.failure());
    }
    check(done());
  };
  for (const auto *member : {"Release", "RequestPasskey", "RequestPinCode"}) {
    const std::string signature = std::string(member) == "RequestPasskey" ? "u" : std::string(member) == "RequestPinCode" ? "s" : "";
    Message request(dbus_message_new_method_call(owner.unique_name().c_str(), path, interface, member));
    bool done = false;
    check(source.call(request.get(), signature, Clock::now() + std::chrono::seconds(2), [&](BusReply reply) {
      check(!reply.error && dbus_message_has_signature(reply.message.get(), signature.c_str()));
      if (signature == "u") {
        dbus_uint32_t value = 0;
        check(dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_UINT32, &value, DBUS_TYPE_INVALID) && value == 999999);
      } else if (signature == "s") {
        const char *value = nullptr;
        check(dbus_message_get_args(reply.message.get(), nullptr, DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID) && std::string(value) == "1234");
      }
      done = true;
    }));
    pump(source, [&] { return done; });
  }
  check(calls == 3 && owner.export_count() == 1);
  {
    Message request(dbus_message_new_method_call(owner.unique_name().c_str(), path, interface, "Release"));
    bool done = false;
    check(foreign.call(request.get(), "", Clock::now() + std::chrono::seconds(2), [&](BusReply reply) {
      check(reply.error && std::string(reply.error) == "remote_error");
      check(dbus_message_has_signature(reply.message.get(), "") &&
            std::string(dbus_message_get_error_name(reply.message.get())) == "org.bluez.Error.Rejected");
      done = true;
    }));
    pump(foreign, [&] { return done; });
    check(calls == 3);
  }
  {
    Message request(dbus_message_new_method_call(owner.unique_name().c_str(), path, interface, "Deferred"));
    bool done = false;
    check(source.call(request.get(), "", Clock::now() + std::chrono::seconds(2), [&](BusReply reply) {
      check(!reply.error); done = true;
    }));
    pump(source, [&] { return bool(deferred); });
    check(!done && calls == 4);
    // WBL-C02: a forged outbound Agent reply cannot enqueue values or diagnostic text.
    for (const auto *value : {"", "12345678901234567", "\n", "\xC3\xA4"}) {
      Message response(dbus_message_new_method_return(deferred.get()));
      check(dbus_message_append_args(response.get(), DBUS_TYPE_STRING, &value, DBUS_TYPE_INVALID));
      bool rejected = false;
      try { owner.respond(std::move(response)); } catch (const std::invalid_argument &) { rejected = true; }
      check(rejected);
    }
    {
      Message response(dbus_message_new_error(deferred.get(), "org.bluez.Error.Rejected", "private challenge"));
      bool rejected = false;
      try { owner.respond(std::move(response)); } catch (const std::invalid_argument &) { rejected = true; }
      check(rejected);
    }
    check(owner.respond(Message(dbus_message_new_method_return(deferred.get()))));
    deferred.reset(); pump(source, [&] { return done; });
  }
  for (const bool wrong_path : {false, true}) {
    Message request(dbus_message_new_method_call(owner.unique_name().c_str(),
      wrong_path ? "/org/wotex/ble/other" : path,
      wrong_path ? interface : "org.bluez.Other", "Release"));
    bool done = false;
    check(source.call(request.get(), "", Clock::now() + std::chrono::seconds(1), [&](BusReply reply) {
      check(reply.error && std::string(reply.error) == "remote_error"); done = true;
    }));
    pump(source, [&] { return done; }); check(calls == 4);
  }
  {
    Message request(dbus_message_new_method_call(owner.unique_name().c_str(), path, interface, "Release"));
    dbus_message_set_no_reply(request.get(), true);
    bool done = false;
    check(source.call(request.get(), "", Clock::now() + std::chrono::milliseconds(25), [&](BusReply reply) {
      check(reply.error && std::string(reply.error) == "timeout"); done = true;
    }));
    pump(source, [&] { return done; }); check(calls == 4);
  }
  for (const std::string &sender : {std::string(), std::string("org.bluez"), std::string(4097, 'x'), std::string(":1.2\0bad", 8)}) {
    bool invalid = false;
    try { owner.export_interface(sender, path, interface, [](auto) {}); }
    catch (const std::invalid_argument &) { invalid = true; }
    check(invalid && owner.export_count() == 1);
  }
  for (const auto *invalid_path : {"", "relative", "/bad-path"}) {
    bool invalid = false;
    try { owner.export_interface(source.unique_name(), invalid_path, interface, [](auto) {}); }
    catch (const std::invalid_argument &) { invalid = true; }
    check(invalid && owner.export_count() == 1);
  }
  bool duplicate = false;
  try { owner.export_interface(source.unique_name(), path, interface, [](auto) {}); }
  catch (const std::invalid_argument &) { duplicate = true; }
  check(duplicate && owner.export_count() == 1);
  owner.unexport(identity); owner.unexport(identity);
  // WBL-C03: repeated lifetimes consume bounded active records, not tombstones.
  for (unsigned count = 0; count < 100000; ++count) {
    auto next = owner.export_interface(source.unique_name(), path, interface, [](auto) {});
    check(next > identity); identity = next;
    owner.unexport(identity); check(owner.export_count() == 0);
  }
  for (unsigned count = 0; count < 64; ++count)
    owner.export_interface(source.unique_name(), std::string(path) + std::to_string(count), interface, [](auto) {});
  bool full = false;
  try { owner.export_interface(source.unique_name(), path, interface, [](auto) {}); }
  catch (const std::runtime_error &) { full = true; }
  check(full && owner.export_count() == 64);
  owner.close();
  check(owner.export_count() == 0 && owner.watch_count() == 0 && owner.timeout_count() == 0 && owner.listener_count() == 0);

  Bus closing(address); hello(closing);
  closing.export_interface(source.unique_name(), path, interface, [&](DBusMessage *request) {
    // Removing the current callback while it executes does not invalidate it.
    check(closing.respond(Message(dbus_message_new_method_return(request)))); closing.close();
  });
  Message request(dbus_message_new_method_call(closing.unique_name().c_str(), path, interface, "Release"));
  check(source.call(request.get(), "", Clock::now() + std::chrono::milliseconds(100), [](auto) {}));
  const auto close_deadline = Clock::now() + std::chrono::seconds(2);
  while (!closing.unique_name().empty() && Clock::now() < close_deadline) {
    std::vector<pollfd> none; closing.poll(none, 1); source.poll(none, 1);
  }
  check(closing.unique_name().empty() && closing.export_count() == 0 && !closing.failure());

  // A stopped independent daemon applies real kernel backpressure. The callback
  // producer cannot grow the response queue after its two reserved entries.
  Bus blocked(address); hello(blocked);
  Message request_template(dbus_message_new_method_call(blocked.unique_name().c_str(), path, interface, "Release"));
  check(dbus_message_set_sender(request_template.get(), source.unique_name().c_str()));
  dbus_message_set_serial(request_template.get(), 1);
  struct Resume { Daemon &daemon; ~Resume() { daemon.resume(); } } resume{daemon};
  daemon.suspend();
  unsigned admitted = 0;
  while (admitted < 10000 && blocked.respond(Message(dbus_message_new_method_return(request_template.get())))) {
    ++admitted; check(blocked.response_count() <= 2);
  }
  check(admitted > 0 && admitted < 10000 && blocked.response_count() == 2 &&
        blocked.failure() && std::string(blocked.failure()) == "resource_limit");
  blocked.close(); check(blocked.response_count() == 0 && blocked.export_count() == 0);
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
  if (argc != 3 && argc != 5) return 2;
  try {
    if (argc == 5) {
      if (std::string(argv[1]) != "--pair-input") return 2;
      Json result;
      {
        Daemon daemon(argv[3], argv[4]);
        result = pairing_test::projection(parse_line(std::string(argv[2]) + "\n"), daemon.address);
      }
      dbus_shutdown(); std::cout << result.dump() << '\n'; return 0;
    }
    if (std::string(argv[1]) == "--agent-input") {
      const auto result = agent_test::projection(parse_line(std::string(argv[2]) + "\n"));
      dbus_shutdown(); std::cout << result.dump() << '\n'; return 0;
    }
    object_test::invariants();
    agent_test::invariants();
    Daemon daemon(argv[1], argv[2]);
    invariants(daemon.address);
    signals(daemon.address);
    service_identity(daemon.address);
    exported_methods(daemon);
    discovery_test::invariants(daemon.address);
    discovery_test::connection_invariants(daemon.address);
    pairing_test::invariants(daemon.address);
    unix_fds(daemon.address, 1);
#ifdef __linux__
    unix_fds(daemon.address, 2);
#endif
    const auto descriptors_before = descriptor_count();
    descriptor_process(daemon.address);
    check(descriptor_count() == descriptors_before);
    dbus_shutdown();
    std::cout << "native bus ownership invariants passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
