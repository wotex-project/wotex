// SPDX-License-Identifier: Apache-2.0
#include "../../priv/corebluetooth/native/operation.hpp"
#include <cstdlib>
#include <iostream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>

using namespace wotex::ble::corebluetooth;
static void check(bool value) {
  if (!value) std::abort();
}
static constexpr Ticket ticket{7, 11, 13};
static constexpr Route route{7, 13, true, true, true};
static const std::vector<std::uint8_t> payload{0, 1, 127, 128, 255};

struct FakePort final : Port {
  struct Call {
    Ticket ticket;
    Route route;
    Mode mode;
    std::vector<std::uint8_t> bytes;
  };
  bool permission = true, link = true, same_route = true, writable = true;
  std::size_t write_max = 512, command_max = 20;
  Submission admission = Submission::accepted;
  Retirement retired = Retirement::confirmed;
  std::vector<Call> calls;
  std::vector<Ticket> retirements;
  std::vector<std::string> order;
  bool authorized() const noexcept override { return permission; }
  bool connected() const noexcept override { return link; }
  bool current(const Route &value) const noexcept override {
    return same_route && value.generation == 7 && value.token == 13;
  }
  std::size_t maximum(Mode mode) const noexcept override {
    return mode == Mode::command ? command_max : write_max;
  }
  bool ready() const noexcept override { return writable; }
  Submission submit(Ticket id, const Route &target, Mode mode,
                    const std::vector<std::uint8_t> &bytes) noexcept override try {
    order.emplace_back("sdk");
    calls.push_back({id, target, mode, bytes});
    return admission;
  } catch (...) {
    std::abort();
  }
  void retire(Ticket id) noexcept override try { retirements.push_back(id); } catch (...) {
    std::abort();
  }
  Retirement retirement(Ticket) const noexcept override { return retired; }
};
struct FakeSink final : Sink {
  FakePort &port;
  bool admit = true;
  std::vector<std::pair<Ticket, Mode>> markers;
  std::vector<Result> results;
  explicit FakeSink(FakePort &value) : port(value) {}
  bool submitted(Ticket id, Mode mode) noexcept override try {
    port.order.emplace_back("marker");
    markers.emplace_back(id, mode);
    return admit;
  } catch (...) {
    std::abort();
  }
  void result(Result value) noexcept override try {
    results.push_back(std::move(value));
  } catch (...) {
    std::abort();
  }
};
struct Rig {
  FakePort port;
  FakeSink sink{port};
  Operation operation{port, sink};
  void start(Mode mode = Mode::write, const std::vector<std::uint8_t> &bytes = payload,
             std::int64_t now = 100, std::int64_t deadline = 200) {
    check(operation.start(ticket, route, mode, bytes, now, deadline));
  }
  const Result &result(Code code, Evidence evidence = Evidence::none) const {
    check(operation.finished() && !operation.active() && sink.results.size() == 1);
    check(sink.results[0].ticket == ticket && sink.results[0].code == code &&
          sink.results[0].evidence == evidence);
    return sink.results[0];
  }
};

static void modes() {
  for (const auto mode : {Mode::read, Mode::write, Mode::command}) {
    Rig rig;
    const auto bytes = mode == Mode::read ? std::vector<std::uint8_t>{} : payload;
    rig.start(mode, bytes);
    check(rig.port.calls.size() == 1 && rig.port.calls[0].ticket == ticket &&
          rig.port.calls[0].mode == mode && rig.port.calls[0].bytes == bytes);
    if (mode == Mode::read) {
      check(rig.sink.markers.empty() && rig.sink.results.empty());
      check(rig.operation.complete(ticket, mode, Code::ok, payload, 101));
      check(rig.result(Code::ok, Evidence::value).bytes == payload);
    } else {
      check(rig.port.order == std::vector<std::string>({"marker", "sdk"}));
      check(rig.sink.markers[0].first == ticket && rig.sink.markers[0].second == mode);
      if (mode == Mode::write) {
        check(rig.sink.results.empty());
        check(rig.operation.complete(ticket, mode, Code::ok, {}, 101));
      }
      check(
          rig.result(Code::ok,
                     mode == Mode::write ? Evidence::att_response : Evidence::native_queue_accepted)
              .submitted);
    }
    check(rig.port.retirements.empty());
    check(!rig.operation.complete(ticket, mode, Code::ok, {}, 102));
    check(!rig.operation.start(ticket, route, mode, bytes, 103, 200));
    rig.operation.poll(1000);
    rig.operation.cancel(1000);
    check(rig.sink.results.size() == 1);
  }
}
static void bounds() {
  for (const auto mode : {Mode::write, Mode::command}) {
    for (const auto count : {0U, 20U, 512U}) {
      Rig rig;
      rig.port.command_max = 512;
      rig.start(mode, std::vector<std::uint8_t>(count, 0xff));
      check(rig.port.calls.size() == 1 && rig.port.calls[0].bytes.size() == count);
      if (mode == Mode::write) rig.operation.complete(ticket, mode, Code::ok, {}, 101);
      rig.result(Code::ok,
                 mode == Mode::write ? Evidence::att_response : Evidence::native_queue_accepted);
    }
    for (const auto maximum : {0U, 19U, 20U}) {
      Rig rig;
      rig.port.command_max = maximum;
      rig.port.write_max = maximum;
      rig.start(mode, std::vector<std::uint8_t>(21, 1));
      rig.result(maximum == 0 ? Code::not_supported : Code::invalid_value_length);
      check(rig.port.calls.empty() && rig.sink.markers.empty());
    }
    Rig rig;
    rig.sink.admit = false;
    rig.start(mode);
    check(!rig.result(Code::resource_limit).submitted && rig.port.calls.empty());
  }
}
static void invalid_start() {
  for (unsigned int i = 0; i < 10; ++i) {
    Rig rig;
    auto id = ticket;
    auto target = route;
    auto mode = Mode::write;
    auto bytes = payload;
    std::int64_t now = 100, deadline = 200;
    switch (i) {
    case 0:
      id.generation = 0;
      break;
    case 1:
      id.request = 0;
      break;
    case 2:
      id.route = 0;
      break;
    case 3:
      target.generation = 8;
      break;
    case 4:
      target.token = 14;
      break;
    case 5:
      now = -1;
      break;
    case 6:
      deadline = now;
      break;
    case 7:
      deadline = now + 60001;
      break;
    case 8:
      bytes.resize(513);
      break;
    case 9:
      mode = Mode::read;
      break;
    default:
      std::abort();
    }
    check(!rig.operation.start(id, target, mode, bytes, now, deadline));
    check(!rig.operation.active() && rig.port.calls.empty() && rig.sink.results.empty());
  }
  for (const auto mode : {Mode::read, Mode::write, Mode::command}) {
    Rig rig;
    auto target = route;
    target.readable = false;
    target.writable = false;
    target.command = false;
    check(rig.operation.start(ticket, target, mode, {}, 100, 200));
    rig.result(Code::not_permitted);
    check(rig.port.calls.empty() && rig.sink.markers.empty());
  }
}
static void readiness() {
  Rig rig;
  rig.port.writable = false;
  rig.start(Mode::command);
  check(rig.operation.active() && rig.port.calls.empty() && rig.sink.markers.empty());
  for (std::int64_t now = 101; now <= 190; ++now) {
    check(rig.operation.ready(ticket, now));
    check(rig.port.calls.empty() && rig.sink.markers.empty());
  }
  rig.port.writable = true;
  check(!rig.operation.ready({8, 11, 13}, 191));
  check(rig.port.calls.empty());
  check(rig.operation.ready(ticket, 192));
  rig.result(Code::ok, Evidence::native_queue_accepted);
  check(rig.port.calls.size() == 1 && !rig.operation.ready(ticket, 193));
}
static void changed_facts() {
  const Code codes[] = {Code::not_authorized, Code::disconnected, Code::stale_discovery,
                        Code::invalid_value_length, Code::not_supported};
  for (unsigned int i = 0; i < 5; ++i) {
    Rig rig;
    rig.port.writable = false;
    rig.start(Mode::command);
    rig.port.writable = true;
    switch (i) {
    case 0:
      rig.port.permission = false;
      break;
    case 1:
      rig.port.link = false;
      break;
    case 2:
      rig.port.same_route = false;
      break;
    case 3:
      rig.port.command_max = payload.size() - 1;
      break;
    case 4:
      rig.port.command_max = 0;
      break;
    default:
      std::abort();
    }
    rig.operation.ready(ticket, 150);
    rig.result(codes[i]);
    check(rig.port.calls.empty() && rig.sink.markers.empty());
  }
}
static void deadline() {
  for (const auto mode : {Mode::read, Mode::write, Mode::command}) {
    Rig rig;
    rig.port.writable = false;
    rig.start(mode, mode == Mode::read ? std::vector<std::uint8_t>{} : payload);
    if (mode == Mode::command) {
      rig.port.writable = true;
      rig.operation.ready(ticket, 200);
      check(rig.port.calls.empty() && rig.sink.markers.empty());
    } else rig.operation.complete(ticket, mode, Code::ok, {}, 200);
    const auto &result = rig.result(Code::timeout);
    check(result.cleanup_confirmed && result.submitted == (mode == Mode::write));
    check(rig.port.retirements.size() == 1);
  }
}
static void foreign_callbacks() {
  Rig rig;
  rig.start();
  for (const auto id : {Ticket{8, 11, 13}, Ticket{7, 12, 13}, Ticket{7, 11, 14}})
    check(!rig.operation.complete(id, Mode::write, Code::ok, {}, 101));
  check(rig.sink.results.empty());
  check(rig.operation.complete(ticket, Mode::write, Code::ok, {}, 102));
  rig.result(Code::ok, Evidence::att_response);
}
static void malformed_callbacks() {
  for (unsigned int i = 0; i < 3; ++i) {
    Rig rig;
    const auto mode = i == 2 ? Mode::read : Mode::write;
    rig.start(mode, mode == Mode::read ? std::vector<std::uint8_t>{} : payload);
    const auto returned_mode = i == 0 ? Mode::read : mode;
    const auto bytes = i == 2 ? std::vector<std::uint8_t>(513) : payload;
    rig.operation.complete(ticket, returned_mode, Code::ok, bytes, 101);
    check(rig.result(Code::invalid_response).cleanup_confirmed);
    check(rig.port.retirements.size() == 1);
  }
}
static void submission_failure() {
  for (const auto admission : {Submission::refused, Submission::uncertain}) {
    Rig rig;
    rig.port.admission = admission;
    rig.start(Mode::command);
    const auto &result = rig.result(Code::transport_error);
    check(result.submitted && result.cleanup_confirmed && result.cause == Code::transport_error);
    check(rig.port.calls.size() == 1 && rig.port.retirements.size() == 1);
  }
  Rig rig;
  rig.start();
  rig.operation.complete(ticket, Mode::write, Code::not_permitted, {}, 101);
  check(rig.result(Code::not_permitted).submitted && rig.port.retirements.size() == 1);
}
static void retirement() {
  Rig rig;
  rig.port.retired = Retirement::pending;
  rig.start();
  rig.operation.cancel(110);
  check(rig.sink.results.empty() && rig.port.retirements.size() == 1);
  rig.operation.cancel(500);
  rig.operation.poll(600);
  check(rig.sink.results.empty() && rig.port.retirements.size() == 1);
  check(!rig.operation.complete(ticket, Mode::write, Code::ok, {}, 601));
  rig.port.retired = Retirement::confirmed;
  rig.operation.poll(609);
  const auto &result = rig.result(Code::disconnected);
  check(result.submitted && result.cleanup_confirmed && result.cause == Code::disconnected);
}
static void cleanup_expiry() {
  for (const auto retirement :
       {Retirement::pending, Retirement::confirmed, Retirement::unconfirmed}) {
    Rig rig;
    rig.port.retired = Retirement::pending;
    rig.start();
    rig.operation.poll(200);
    rig.operation.poll(699);
    check(rig.sink.results.empty());
    rig.port.retired = retirement;
    rig.operation.poll(700);
    const auto &result = rig.result(Code::cleanup_timeout);
    check(result.cause == Code::timeout && result.submitted && !result.cleanup_confirmed);
    rig.operation.poll(1000);
    check(rig.sink.results.size() == 1 && rig.port.retirements.size() == 1);
  }
  Rig rig;
  rig.port.retired = Retirement::unconfirmed;
  rig.start();
  rig.operation.cancel(110);
  check(rig.result(Code::cleanup_timeout).cause == Code::disconnected);
}
static void clock_regression() {
  Rig rig;
  rig.port.writable = false;
  rig.start(Mode::command);
  rig.operation.poll(150);
  rig.operation.ready(ticket, 149);
  check(!rig.result(Code::clock_regressed).submitted && rig.port.calls.empty());
  Rig pending;
  pending.port.retired = Retirement::pending;
  pending.start();
  pending.operation.poll(200);
  pending.operation.poll(699);
  pending.operation.poll(300);
  check(pending.sink.results.empty());
  pending.operation.poll(700);
  pending.result(Code::cleanup_timeout);
}
static void separate_owners() {
  Rig first, second;
  first.port.writable = false;
  first.start(Mode::command);
  second.start();
  first.operation.cancel(110);
  check(!first.result(Code::disconnected).submitted);
  check(second.sink.results.empty() && second.port.retirements.empty());
  second.operation.complete(ticket, Mode::write, Code::ok, {}, 120);
  second.result(Code::ok, Evidence::att_response);
}
static void unfinished_destruction() {
  const auto child = fork();
  check(child >= 0);
  if (child == 0) {
    std::set_terminate([] { _exit(73); });
    {
      Rig rig;
      rig.start();
    }
    _exit(74);
  }
  int status = 0;
  check(waitpid(child, &status, 0) == child);
  check(WIFEXITED(status) && WEXITSTATUS(status) == 73);
}
int main(int argc, char **argv) {
  if (argc != 2) return 2;
  const std::string name(argv[1]);
  if (name == "modes") modes();
  else if (name == "bounds") bounds();
  else if (name == "invalid_start") invalid_start();
  else if (name == "readiness") readiness();
  else if (name == "changed_facts") changed_facts();
  else if (name == "deadline") deadline();
  else if (name == "foreign_callbacks") foreign_callbacks();
  else if (name == "malformed_callbacks") malformed_callbacks();
  else if (name == "submission_failure") submission_failure();
  else if (name == "retirement") retirement();
  else if (name == "cleanup_expiry") cleanup_expiry();
  else if (name == "clock_regression") clock_regression();
  else if (name == "separate_owners") separate_owners();
  else if (name == "unfinished_destruction") unfinished_destruction();
  else return 2;
  std::cout << "ok " << name << '\n';
}
