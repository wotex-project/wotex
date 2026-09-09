"""Read-only private-bus accounting for successful BlueZ ownership calls.

Counters follow real method replies and unique-name loss. The monitor never
stands in for BlueZ and never accepts native pairing or subscription requests.
"""

from collections import deque
from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus


class OwnershipMonitor:
    def __init__(self, bus, bluez_owner):
        self.bus = bus
        self.bluez_owner = bluez_owner
        self.senders = set()
        self.pending = {}
        self.agents = {}
        self.notifications = set()
        self.calls = deque(maxlen=4096)
        self.acknowledgements = deque(maxlen=4096)
        self.failure = None
        bus.add_message_handler(self.receive)

    @classmethod
    async def start(cls, address):
        bus = await MessageBus(bus_address=address).connect()
        owner = await bus.call(
            Message(
                destination="org.freedesktop.DBus",
                path="/org/freedesktop/DBus",
                interface="org.freedesktop.DBus",
                member="GetNameOwner",
                signature="s",
                body=["org.bluez"],
            )
        )
        assert (
            owner.message_type == MessageType.METHOD_RETURN and owner.signature == "s"
        )
        monitor = cls(bus, owner.body[0])
        reply = await bus.call(
            Message(
                destination="org.freedesktop.DBus",
                path="/org/freedesktop/DBus",
                interface="org.freedesktop.DBus.Monitoring",
                member="BecomeMonitor",
                signature="asu",
                body=[[], 0],
            )
        )
        if reply.message_type != MessageType.METHOD_RETURN or reply.signature != "":
            raise RuntimeError("Private D-Bus did not allow its owned fixture monitor")
        return monitor

    def watch(self, sender):
        if len(self.senders) >= 64:
            raise RuntimeError("Native fixture sender bound exceeded")
        self.senders.add(sender)

    def receive(self, message):
        try:
            self.account(message)
        except Exception as error:
            self.failure = error
        # dbus-next must not synthesize replies to calls observed by a monitor.
        return True if message.message_type == MessageType.METHOD_CALL else None

    def account(self, message):
        if message.message_type == MessageType.METHOD_CALL:
            if len(self.calls) == self.calls.maxlen:
                raise RuntimeError("Private D-Bus trace bound exceeded")
            self.calls.append(
                (message.sender, message.path, message.interface, message.member)
            )
            if message.sender not in self.senders:
                return
            if message.member not in (
                "RegisterAgent",
                "UnregisterAgent",
                "StartNotify",
                "StopNotify",
            ):
                return
            if len(self.pending) >= 256:
                raise RuntimeError("Private D-Bus accounting bound exceeded")
            assert message.destination == self.bluez_owner
            target = (
                message.body[0] if message.member.endswith("Agent") else message.path
            )
            self.pending[(message.sender, message.serial)] = (message.member, target)
        elif message.message_type in (MessageType.METHOD_RETURN, MessageType.ERROR):
            operation = self.pending.pop(
                (message.destination, message.reply_serial), None
            )
            if operation is None or message.message_type == MessageType.ERROR:
                return
            assert message.sender == self.bluez_owner
            if message.signature != "":
                raise AssertionError(
                    "Owned BlueZ control acknowledgement has a payload"
                )
            member, target = operation
            sender = message.destination
            if len(self.acknowledgements) == self.acknowledgements.maxlen:
                raise RuntimeError("Private D-Bus acknowledgement trace bound exceeded")
            self.acknowledgements.append((sender, member, target))
            if member == "RegisterAgent":
                assert sender not in self.agents
                self.agents[sender] = target
            elif member == "UnregisterAgent":
                assert self.agents.pop(sender) == target
            elif member == "StartNotify":
                assert (sender, target) not in self.notifications
                self.notifications.add((sender, target))
            elif member == "StopNotify":
                self.notifications.discard((sender, target))
        elif (
            message.message_type == MessageType.SIGNAL
            and message.sender == "org.freedesktop.DBus"
            and message.member == "NameOwnerChanged"
        ):
            name, previous, current = message.body
            if previous and not current:
                self.agents.pop(name, None)
                self.notifications.difference_update(
                    item for item in list(self.notifications) if item[0] == name
                )
                for identifier in list(self.pending):
                    if identifier[0] == name:
                        self.pending.pop(identifier)

    def assert_released(self):
        if self.failure is not None:
            raise self.failure
        assert not self.agents, self.agents
        assert not self.notifications, self.notifications
        assert not self.pending, self.pending

    async def close(self):
        self.bus.disconnect()
        await self.bus.wait_for_disconnect()
