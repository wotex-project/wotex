// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "pairing_test.hpp"

namespace pending_test {
using namespace wotex::ble;
inline void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("pending ownership assertion at line " + std::to_string(line));
}
#define PENDING_CHECK(value) ::pending_test::verify((value), __LINE__)
inline Message request(const std::string &sender) {
  return Message(dbus_message_new_method_call(sender.c_str(), "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"));
}
inline void invariants(const std::string &address) {
  pairing_test::Fixture fixture(address);
  auto &bus = fixture.owner.bus();
  std::vector<Message> requests;
  fixture.peer.on_query = [&](DBusMessage *message) { requests.emplace_back(dbus_message_ref(message)); };
  unsigned callbacks = 0;
  auto first = request(fixture.peer.sender()), second = request(fixture.peer.sender());
  const auto a = bus.pending_call(first.get(), "a{oa{sa{sv}}}", Clock::now() + std::chrono::seconds(2),
    [&](BusReply) { PENDING_CHECK(false); });
  const auto b = bus.pending_call(second.get(), "a{oa{sa{sv}}}", Clock::now() + std::chrono::seconds(2),
    [&](BusReply reply) { PENDING_CHECK(!reply.error); ++callbacks; });
  PENDING_CHECK(a && b && bus.pending_count() == 2 && !bus.cancel(Bus::Ticket{}));
  fixture.until([&] { return requests.size() == 2; });
  PENDING_CHECK(bus.cancel(*a) && !bus.cancel(*a) && bus.pending_count() == 1);
  fixture.peer.reply(requests[0].get()); fixture.peer.reply(requests[1].get());
  fixture.until([&] { return callbacks == 1; });
  PENDING_CHECK(bus.pending_count() == 0 && !bus.cancel(*b)); requests.clear();

  Bus foreign(address); bool ready = false;
  PENDING_CHECK(foreign.hello(Clock::now() + std::chrono::seconds(2), [&](BusReply reply) { PENDING_CHECK(!reply.error); ready = true; }));
  const auto deadline = Clock::now() + std::chrono::seconds(2);
  while (!ready && Clock::now() < deadline) { std::vector<pollfd> none; foreign.poll(none, 1); }
  PENDING_CHECK(ready);
  auto other = request(fixture.peer.sender());
  auto foreign_ticket = foreign.pending_call(other.get(), "a{oa{sa{sv}}}", Clock::now() + std::chrono::seconds(2),
    [&](BusReply) { PENDING_CHECK(false); });
  PENDING_CHECK(foreign_ticket && !bus.cancel(*foreign_ticket) && foreign.pending_count() == 1 &&
    foreign.cancel(*foreign_ticket) && foreign.pending_count() == 0);
  foreign.close(); PENDING_CHECK(!foreign.cancel(*foreign_ticket));

  // WBL-C03: local tickets cannot cancel a later call even if libdbus reuses a
  // pending-call address. Storage contains only active calls, never tombstones.
  std::optional<Bus::Ticket> old = a;
  fixture.peer.on_query = [&](DBusMessage *message) { fixture.peer.reply(message); };
  for (unsigned index = 0; index < 1000; ++index) {
    auto message = request(fixture.peer.sender());
    auto current = bus.pending_call(message.get(), "a{oa{sa{sv}}}", Clock::now() + std::chrono::seconds(2),
      [&](BusReply) { PENDING_CHECK(false); });
    PENDING_CHECK(current && !bus.cancel(*old) && bus.pending_count() == 1 && bus.cancel(*current) &&
                  !bus.cancel(*current) && bus.pending_count() == 0);
    old = current; fixture.peer.poll(); std::vector<pollfd> none; fixture.owner.poll(none, 0);
  }
  auto invalid = request(fixture.peer.sender());
  PENDING_CHECK(!bus.pending_call(invalid.get(), "", Clock::now() + std::chrono::seconds(1), {}) &&
    dbus_message_get_serial(invalid.get()) == 0 && bus.pending_count() == 0 && fixture.owner.active());
  fixture.owner.close(); PENDING_CHECK(!bus.cancel(*old));
}
} // namespace pending_test
