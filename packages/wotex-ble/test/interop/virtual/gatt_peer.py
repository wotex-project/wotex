"""Independent fixture GATT application over the real BlueZ server API."""

import asyncio
import time
from dbus_next import Message, MessageType, Variant

PROPS = "org.freedesktop.DBus.Properties"

OM = "org.freedesktop.DBus.ObjectManager"

ADAPTER = "org.bluez.Adapter1"

CHAR = "org.bluez.GattCharacteristic1"

SERVICE = "org.bluez.GattService1"

DEVICE = "org.bluez.Device1"

SERVICE_UUID = "9bf00000-4689-4b5b-bdea-8d9f7c1b6000"

ROOT = "/fixture"

SERVICE_PATH = ROOT + "/service0"

UUIDS = {
    name: f"9bf0000{number}-4689-4b5b-bdea-8d9f7c1b6000"
    for name, number in [
        ("value", 1),
        ("notify", 2),
        ("indicate", 3),
        ("duplicate_a", 4),
        ("duplicate_b", 4),
    ]
}

FLAGS = {
    "value": ["read", "write"],
    "notify": ["read", "notify"],
    "indicate": ["read", "indicate"],
    "duplicate_a": ["read"],
    "duplicate_b": ["read"],
}


async def call(
    bus, path, interface, member, signature="", body=None, destination="org.bluez"
):
    response = await asyncio.wait_for(
        bus.call(
            Message(
                destination=destination,
                path=path,
                interface=interface,
                member=member,
                signature=signature,
                body=body or [],
            )
        ),
        10,
    )
    if response.message_type != MessageType.METHOD_RETURN:
        raise RuntimeError(
            (path, interface, member, response.error_name, response.body)
        )
    return response.body


async def until(predicate, label, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = (
            await asyncio.wait_for(predicate(), max(deadline - time.monotonic(), 0.001))
            if asyncio.iscoroutinefunction(predicate)
            else predicate()
        )
        if value:
            return value
        await asyncio.sleep(0.02)
    raise AssertionError("Timed out: " + label)


class Peer:
    def __init__(self, bus):
        self.bus = bus
        self.paths = {ROOT + "/service0/" + label: label for label in UUIDS}
        self.values = {
            label: b"\x34\x12" if label == "value" else b"\x00" for label in UUIDS
        }
        self.values["duplicate_a"] = b"\xa1"
        self.values["duplicate_b"] = b"\xb2"
        self.notifying = set()
        self.denied = set()
        self.delays = {}
        self.trace = []
        self.confirms = 0
        self.bus.add_message_handler(self.receive)

    def properties(self, label):
        return {
            "Service": Variant("o", SERVICE_PATH),
            "UUID": Variant("s", UUIDS[label]),
            "Flags": Variant("as", FLAGS[label]),
            "Value": Variant("ay", self.values[label]),
            "Notifying": Variant("b", label in self.notifying),
        }

    def objects(self):
        return {
            SERVICE_PATH: {
                SERVICE: {
                    "UUID": Variant("s", SERVICE_UUID),
                    "Primary": Variant("b", True),
                }
            },
            **{
                path: {CHAR: self.properties(label)}
                for path, label in self.paths.items()
            },
        }

    def changed(self, label, value):
        self.values[label] = value
        path = next(path for path, item in self.paths.items() if item == label)
        self.trace.append({"member": "stimulus", "label": label, "value": value.hex()})
        return self.bus.send(
            Message.new_signal(
                path,
                PROPS,
                "PropertiesChanged",
                "sa{sv}as",
                [CHAR, {"Value": Variant("ay", value)}, []],
            )
        )

    def receive(self, message):
        if message.message_type != MessageType.METHOD_CALL:
            return None
        if len(self.trace) >= 4096:
            raise RuntimeError("GATT fixture trace bound exceeded")
        self.trace.append(
            {"member": message.member, "path": message.path, "sender": message.sender}
        )
        if message.interface == "org.bluez.Agent1" and message.path == ROOT + "/agent":
            if message.member in ("Release", "Cancel"):
                return Message.new_method_return(message)
            assert message.body[0] == "/org/bluez/hci1/dev_00_AA_01_00_00_00", (
                message.body
            )
            if message.member in (
                "RequestConfirmation",
                "RequestAuthorization",
                "AuthorizeService",
            ):
                return Message.new_method_return(message)
            return Message.new_error(
                message, "org.bluez.Error.Rejected", "Unsupported fixture challenge"
            )
        if (
            message.interface == OM
            and message.member == "GetManagedObjects"
            and message.path == ROOT
        ):
            return Message.new_method_return(message, "a{oa{sa{sv}}}", [self.objects()])
        if message.interface == PROPS and message.member == "GetAll":
            if message.path in self.paths:
                properties = self.properties(self.paths[message.path])
            elif message.path == SERVICE_PATH:
                properties = self.objects()[SERVICE_PATH][SERVICE]
            elif message.path == ROOT + "/advertisement":
                properties = {
                    "Type": Variant("s", "peripheral"),
                    "Discoverable": Variant("b", True),
                    "ServiceUUIDs": Variant("as", [SERVICE_UUID]),
                    "LocalName": Variant("s", "WBL Software Fixture"),
                }
            else:
                return None
            return Message.new_method_return(message, "a{sv}", [properties])
        if (
            message.interface == "org.bluez.LEAdvertisement1"
            and message.member == "Release"
        ):
            return Message.new_method_return(message)
        if message.interface == CHAR and message.path in self.paths:
            label = self.paths[message.path]
            if label in self.denied and message.member in ("ReadValue", "WriteValue"):
                return Message.new_error(
                    message, "org.bluez.Error.NotPermitted", "Fixture denial"
                )
            if message.member == "ReadValue":
                assert message.signature == "a{sv}"
                self.trace[-1]["value"] = self.values[label].hex()
                reply = Message.new_method_return(message, "ay", [self.values[label]])
                delay = self.delays.get(label, 0)
                if delay:
                    # A delayed stimulus still answers exactly once; True marks it handled.
                    asyncio.get_running_loop().call_later(delay / 1000, self.bus.send, reply)
                    return True
                return reply
            if message.member == "WriteValue":
                assert message.signature == "aya{sv}" and type(message.body[0]) is bytes
                value, options = message.body
                self.trace[-1]["options"] = {
                    key: item.value for key, item in options.items()
                }
                self.trace[-1]["value"] = value.hex()
                self.values[label] = value
                return Message.new_method_return(message)
            if message.member == "StartNotify":
                assert label not in self.notifying
                self.notifying.add(label)
                return Message.new_method_return(message)
            if message.member == "StopNotify":
                self.notifying.discard(label)
                return Message.new_method_return(message)
            if message.member == "Confirm":
                self.confirms += 1
                return Message.new_method_return(message)
        return None
