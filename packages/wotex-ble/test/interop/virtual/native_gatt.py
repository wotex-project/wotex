"""WBL-N03 / WBL-V03..V09,V11 native virtual-controller assertions.

The provider implements a private fixture GATT service through BlueZ's server
API. First-party Central uses its own real D-Bus connection; no injected backend
or expectation is supplied to it. Public BEAM/Runtime proof is a separate lane.
"""

import asyncio
import json
import os
import sys
import time
from pathlib import Path
from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus

sys.path.insert(0, "/opt/wbl/bluez")
from client import Central, Failure
from procedures import execute, bytes_value
from dbus_monitor import OwnershipMonitor

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
                return Message.new_method_return(message, "ay", [self.values[label]])
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


async def main():
    address = os.environ["DBUS_SYSTEM_BUS_ADDRESS"]
    bus = await MessageBus(bus_address=address).connect()
    peer = Peer(bus)
    await bus.request_name("io.wotex.BLEFixture")

    async def adapters_ready():
        try:
            objects = (await call(bus, "/", OM, "GetManagedObjects"))[0]
            return (
                objects
                if all(
                    ADAPTER in objects.get("/org/bluez/hci" + str(n), {})
                    for n in range(2)
                )
                else None
            )
        except RuntimeError:
            return None

    objects = await until(adapters_ready, "two BlueZ adapters")
    await call(
        bus,
        "/org/bluez",
        "org.bluez.AgentManager1",
        "RegisterAgent",
        "os",
        [ROOT + "/agent", "DisplayYesNo"],
    )
    await call(
        bus,
        "/org/bluez",
        "org.bluez.AgentManager1",
        "RequestDefaultAgent",
        "o",
        [ROOT + "/agent"],
    )
    for n in range(2):
        await call(
            bus,
            "/org/bluez/hci" + str(n),
            PROPS,
            "Set",
            "ssv",
            [ADAPTER, "Powered", Variant("b", True)],
        )
    await call(
        bus,
        "/org/bluez/hci1",
        "org.bluez.GattManager1",
        "RegisterApplication",
        "oa{sv}",
        [ROOT, {}],
    )
    await call(
        bus,
        "/org/bluez/hci1",
        "org.bluez.LEAdvertisingManager1",
        "RegisterAdvertisement",
        "oa{sv}",
        [ROOT + "/advertisement", {}],
    )
    remote_address = objects["/org/bluez/hci1"][ADAPTER]["Address"].value
    await call(
        bus,
        "/org/bluez/hci0",
        ADAPTER,
        "SetDiscoveryFilter",
        "a{sv}",
        [{"Transport": Variant("s", "le")}],
    )
    await call(bus, "/org/bluez/hci0", ADAPTER, "StartDiscovery")

    async def discovered():
        objects = (await call(bus, "/", OM, "GetManagedObjects"))[0]
        for path, interfaces in objects.items():
            props = interfaces.get(DEVICE, {})
            if (
                props.get("Address", Variant("s", "")).value == remote_address
                and props.get("Adapter", Variant("o", "/")).value == "/org/bluez/hci0"
            ):
                return path, props

    remote_path, remote = await until(discovered, "advertised peer")
    await call(bus, "/org/bluez/hci0", ADAPTER, "StopDiscovery")
    await call(bus, remote_path, DEVICE, "Connect")

    async def resolved():
        props = (await call(bus, remote_path, PROPS, "GetAll", "s", [DEVICE]))[0]
        return props.get("ServicesResolved", Variant("b", False)).value

    await until(resolved, "real GATT service discovery")
    parameters = {
        "peer": {
            "adapter": "/org/bluez/hci0",
            "address": remote_address,
            "address_type": remote["AddressType"].value,
        },
        "connection": "borrowed",
        "bus_address": address,
    }
    events = []
    monitor = await OwnershipMonitor.start(address)
    owners = []
    central = Central(events.append)
    owners.append(central)
    await central.open(parameters, 10000)
    monitor.watch(central.bus.unique_name)
    page = await central.discover({}, 10000)
    Path("/results/catalogue.json").write_text(json.dumps(page, indent=2) + "\n")
    items = [
        item for item in page["characteristics"] if item["service_uuid"] == SERVICE_UUID
    ]
    assert len(items) == 5, items

    def target(label):
        item = next(
            item for item in items if item["characteristic_uuid"] == UUIDS[label]
        )
        return {
            "service": SERVICE_UUID,
            "characteristic": UUIDS[label],
            **{key: item[key] for key in ("object_path", "handle", "generation")},
        }

    try:
        ambiguous = dict(target("duplicate_a"), object_path=None, handle=None)
        try:
            await execute(central, "read", {"address": ambiguous}, 10000, "1")
        except Failure as error:
            assert error.code == "ambiguous_characteristic", error
        else:
            raise AssertionError("duplicate UUID was guessed")
        duplicates = [
            item
            for item in items
            if item["characteristic_uuid"] == UUIDS["duplicate_a"]
        ]
        selected_values = []
        for item in duplicates:
            selected = {
                "service": SERVICE_UUID,
                "characteristic": UUIDS["duplicate_a"],
                **{key: item[key] for key in ("object_path", "handle", "generation")},
            }
            selected_values.append(
                bytes_value(
                    await execute(
                        central, "read", {"address": selected}, 10000, "selected"
                    )
                )
            )
        assert set(selected_values) == {b"\xa1", b"\xb2"}
        before_writes = len(
            [item for item in peer.trace if item["member"] == "WriteValue"]
        )
        for invalid, expected in [
            (dict(target("value"), generation=2), "stale_discovery"),
            (
                dict(target("value"), object_path=target("notify")["object_path"]),
                "address_mismatch",
            ),
        ]:
            try:
                await execute(
                    central,
                    "write",
                    {"address": invalid, "value": {"type": "bytes", "base64": "AA=="}},
                    10000,
                    "invalid-selection",
                )
            except Failure as error:
                assert error.code == expected
            else:
                raise AssertionError("Invalid GATT selection reached the peripheral")
        assert (
            len([item for item in peer.trace if item["member"] == "WriteValue"])
            == before_writes
        )
        assert (
            bytes_value(
                await execute(central, "read", {"address": target("value")}, 10000, "2")
            )
            == b"\x34\x12"
        )
        central.emit = events.append
        assert (
            await execute(
                central,
                "write",
                {
                    "address": target("value"),
                    "value": {"type": "bytes", "base64": "eFY="},
                },
                10000,
                "3",
            )
            is None
        )
        assert (
            bytes_value(
                await execute(central, "read", {"address": target("value")}, 10000, "4")
            )
            == b"\x78\x56"
        )
        print("READ_WRITE_PASSED", flush=True)
        peer.denied.add("value")
        try:
            await execute(central, "read", {"address": target("value")}, 10000, "5")
        except Failure as error:
            assert error.code == "not_permitted", error
        else:
            raise AssertionError("denied read returned cached value")
        peer.denied.clear()
        for label in ("notify", "indicate"):
            reports = []
            central.emit = reports.append
            result = await central.notifications.subscribe(
                {"address": target(label), "mode": label}, 10000, label
            )
            central.notifications.activate(label)
            assert result["effective_mode"] == label
            before = peer.confirms
            for count in (1, 2):
                await peer.changed(label, b"\x01")
                await until(lambda: len(reports) == count, label + " delivery")
                assert (
                    reports[-1]["event"] == "value"
                    and bytes_value(reports[-1]["value"]) == b"\x01"
                ), reports
                assert reports[-1]["metadata"]["source"] == "bluez_value_change"
                if label == "indicate":
                    await until(
                        lambda: peer.confirms == before + count,
                        "ATT indication confirmation",
                    )
            await central.notifications.unsubscribe({"subscription_id": label}, 10000)
            await until(lambda: label not in peer.notifying, "peer StopNotify")
            print(label.upper() + "_PASSED", flush=True)
        # Independent unique senders borrow the fixture-owned physical link.
        second = Central(events.append)
        owners.append(second)
        second_reports = []
        second.emit = second_reports.append
        second_open = await second.open(parameters, 10000)
        monitor.watch(second_open["sender"])
        first_sender = central.bus.unique_name
        assert second_open["sender"] != first_sender
        first_reports = []
        central.emit = first_reports.append
        await central.notifications.subscribe(
            {"address": target("notify"), "mode": "notify"}, 10000, "first"
        )
        await second.notifications.subscribe(
            {"address": target("notify"), "mode": "notify"}, 10000, "second"
        )
        central.notifications.activate("first")
        second.notifications.activate("second")
        await peer.changed("notify", b"\x02")
        await until(
            lambda: len(first_reports) == 2 and len(second_reports) == 2,
            "two independent senders",
        )
        assert all(
            bytes_value(report["value"]) == b"\x02"
            for report in first_reports + second_reports
        )
        await central.close()
        await until(
            lambda: not central.notifications.entries,
            "first owner released native records",
        )
        names = (
            await call(
                bus,
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "ListNames",
                destination="org.freedesktop.DBus",
            )
        )[0]
        assert first_sender not in names and second_open["sender"] in names
        assert await second.health({}, 10000) == {
            "connected": True,
            "services_resolved": True,
        }
        await peer.changed("notify", b"\x03")
        await until(
            lambda: len(second_reports) == 3, "second sender survives first close"
        )
        assert (
            len([report for report in first_reports if report["event"] == "value"]) == 2
        )
        before = len(second_reports)
        # A real ReadValue updates BlueZ's cached Value; retain its actual source.
        peer.values["notify"] = b"\x04"
        await execute(
            second, "read", {"address": target("notify")}, 10000, "read-source"
        )
        await until(
            lambda: len(second_reports) == before + 1, "read-caused Value change"
        )
        assert second_reports[-1]["metadata"]["source"] == "bluez_value_change"
        await second.close()
        await until(lambda: not peer.notifying, "last sender releases peripheral CCC")
        print("INDEPENDENT_SENDER_AND_READ_SOURCE_PASSED", flush=True)

        # Every pairing case starts with disposable fixture-owned empty bonds.
        for pairing_case in ("accept", "reject", "timeout", "wrong_challenge"):
            objects = (await call(bus, "/", OM, "GetManagedObjects"))[0]
            for path, interfaces in objects.items():
                if DEVICE in interfaces:
                    await call(
                        bus,
                        interfaces[DEVICE]["Adapter"].value,
                        ADAPTER,
                        "RemoveDevice",
                        "o",
                        [path],
                    )
            # Reset only these two disposable controllers and their discovery cache.
            await call(
                bus,
                "/org/bluez/hci1",
                "org.bluez.LEAdvertisingManager1",
                "UnregisterAdvertisement",
                "o",
                [ROOT + "/advertisement"],
            )
            for n in range(2):
                await call(
                    bus,
                    "/org/bluez/hci" + str(n),
                    PROPS,
                    "Set",
                    "ssv",
                    [ADAPTER, "Powered", Variant("b", False)],
                )
                await call(
                    bus,
                    "/org/bluez/hci" + str(n),
                    PROPS,
                    "Set",
                    "ssv",
                    [ADAPTER, "Powered", Variant("b", True)],
                )
            await call(bus, "/org/bluez/hci0", ADAPTER, "StartDiscovery")
            await call(
                bus,
                "/org/bluez/hci1",
                "org.bluez.LEAdvertisingManager1",
                "RegisterAdvertisement",
                "oa{sv}",
                [ROOT + "/advertisement", {}],
            )
            remote_path, remote = await until(discovered, "fresh disposable peer")
            await call(bus, "/org/bluez/hci0", ADAPTER, "StopDiscovery")
            await call(bus, remote_path, DEVICE, "Connect")
            await until(resolved, "fresh peer GATT resolution")
            paired = Central(events.append)
            owners.append(paired)
            await paired.open(parameters, 10000)
            monitor.watch(paired.bus.unique_name)
            challenges = []

            def answer(event):
                if event.get("event") == "agent_challenge":
                    challenges.append(event["challenge"])
                    if pairing_case == "timeout":
                        return
                    identifier = (
                        event["challenge"]["id"]
                        if pairing_case != "wrong_challenge"
                        else "f" * 32
                    )
                    try:
                        paired.agent_reply(
                            {
                                "challenge_id": identifier,
                                "decision": {
                                    "action": "accept"
                                    if pairing_case == "accept"
                                    else "reject"
                                },
                            }
                        )
                    except Failure as error:
                        assert (
                            pairing_case == "wrong_challenge"
                            and error.code == "pairing_rejected"
                        )

            paired.emit = answer
            try:
                result = await paired.pair(
                    {"capability": "DisplayYesNo"},
                    1000 if pairing_case == "timeout" else 10000,
                    "pair-" + pairing_case,
                )
            except Failure as error:
                assert pairing_case != "accept" and error.code == "pairing_rejected", (
                    pairing_case,
                    error,
                )
            else:
                assert pairing_case == "accept" and result == {"paired": True}, (
                    pairing_case,
                    result,
                )
            assert (
                len(challenges) == 1 and challenges[0]["kind"] == "confirm_passkey"
            ), challenges
            assert paired.agent is None
            await paired.close()
            await until(lambda: not monitor.agents, "real Agent registration cleanup")
            assert any(
                sender == paired.bus.unique_name and member == "RegisterAgent"
                for sender, member, target in monitor.acknowledgements
            )
            assert any(
                sender == paired.bus.unique_name and member == "UnregisterAgent"
                for sender, member, target in monitor.acknowledgements
            )
            print("PAIR_" + pairing_case.upper() + "_PASSED", flush=True)
        await until(
            lambda: (
                not monitor.notifications and not monitor.agents and not monitor.pending
            ),
            "real native sender resources released",
        )
        monitor.assert_released()
        names = (
            await call(
                bus,
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "ListNames",
                destination="org.freedesktop.DBus",
            )
        )[0]
        assert not monitor.senders.intersection(names)
        assert not any(
            member
            in ("CancelPairing", "RemoveDevice", "RequestDefaultAgent", "Disconnect")
            for sender, path, interface, member in monitor.calls
            if sender in monitor.senders
        )
        # A separate explicitly owned generation connects and disconnects its link.
        properties = (await call(bus, remote_path, PROPS, "GetAll", "s", [DEVICE]))[0]
        if properties["Connected"].value:
            await call(bus, remote_path, DEVICE, "Disconnect")
        owned = Central(events.append)
        owners.append(owned)
        opened = await owned.open(dict(parameters, connection="owned"), 10000)
        monitor.watch(opened["sender"])
        assert opened["link_owned"] is True
        cleanup_started = time.monotonic()
        await owned.close()

        async def sender_released():
            names = (
                await call(
                    bus,
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "ListNames",
                    destination="org.freedesktop.DBus",
                )
            )[0]
            return opened["sender"] not in names

        await until(
            sender_released,
            "owned sender cleanup",
            max(1 - (time.monotonic() - cleanup_started), 0.001),
        )
        local_cleanup_ms = (time.monotonic() - cleanup_started) * 1000
        assert local_cleanup_ms <= 1000

        async def disconnected():
            properties = (await call(bus, remote_path, PROPS, "GetAll", "s", [DEVICE]))[
                0
            ]
            return properties["Connected"].value is False

        # BlueZ device.c:DISCONNECT_TIMER deliberately postpones the kernel
        # disconnect by two seconds. Its daemon-owned drain is separate from
        # the library's sender/process/listener cleanup grace.
        await until(
            disconnected,
            "BlueZ managed link drain",
            max(3.5 - (time.monotonic() - cleanup_started), 0.001),
        )
        bluez_link_drain_ms = (time.monotonic() - cleanup_started) * 1000
        assert bluez_link_drain_ms <= 3500
        assert [
            member
            for sender, path, interface, member in monitor.calls
            if sender == opened["sender"] and interface == DEVICE
        ] == ["Connect", "Disconnect"]
        await until(
            lambda: (
                not monitor.agents and not monitor.notifications and not monitor.pending
            ),
            "owned link cleanup",
        )
        monitor.assert_released()
        names = (
            await call(
                bus,
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "ListNames",
                destination="org.freedesktop.DBus",
            )
        )[0]
        assert not monitor.senders.intersection(names)
        Path("/results/native-ownership.json").write_text(
            json.dumps(
                {
                    "senders": sorted(monitor.senders),
                    "calls": list(monitor.calls),
                    "acknowledgements": list(monitor.acknowledgements),
                    "local_cleanup_ms": local_cleanup_ms,
                    "bluez_link_drain_ms": bluez_link_drain_ms,
                    "agents_remaining": len(monitor.agents),
                    "notifications_remaining": len(monitor.notifications),
                    "native_senders_remaining": len(
                        monitor.senders.intersection(names)
                    ),
                },
                indent=2,
            )
            + "\n"
        )
    finally:
        await asyncio.gather(*(owner.close() for owner in owners))
        objects = (await call(bus, "/", OM, "GetManagedObjects"))[0]
        properties = objects.get(remote_path, {}).get(DEVICE, {})
        if properties.get("Connected", Variant("b", False)).value:
            await call(bus, remote_path, DEVICE, "Disconnect")
        await call(
            bus,
            "/org/bluez/hci1",
            "org.bluez.LEAdvertisingManager1",
            "UnregisterAdvertisement",
            "o",
            [ROOT + "/advertisement"],
        )
        await call(
            bus,
            "/org/bluez/hci1",
            "org.bluez.GattManager1",
            "UnregisterApplication",
            "o",
            [ROOT],
        )
        Path("/results/peer-trace.json").write_text(
            json.dumps(peer.trace, indent=2) + "\n"
        )
        bus.disconnect()
        await bus.wait_for_disconnect()
        await monitor.close()
    Path("/results/native-result.json").write_text(
        json.dumps(
            {
                "result": "passed",
                "scope": "first_party_sdk_virtual_gatt",
                "public_beam_runtime_lane": "pending",
                "requirements_exercised": [
                    "WBL-S01",
                    "WBL-S02",
                    "WBL-S03",
                    "WBL-S04",
                    "WBL-N03",
                ],
                "cases": [
                    "duplicate_uuid_rejected",
                    "read_3412",
                    "write_7856_readback",
                    "denied_read_not_cached",
                    "two_equal_notifications",
                    "two_equal_indications_with_confirm",
                    "independent_sender_survival",
                    "read_caused_bluez_value_change",
                    "pair_accept",
                    "pair_reject",
                    "pair_timeout",
                    "pair_wrong_challenge",
                    "owned_link_cleanup",
                    "exact_duplicate_selection",
                    "stale_and_wrong_target_rejected",
                ],
                "peripheral_notifications_remaining": len(peer.notifying),
                "indication_confirmations": peer.confirms,
            },
            indent=2,
        )
        + "\n"
    )
    print("WBL_NATIVE_VIRTUAL_GATT_PASSED", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
