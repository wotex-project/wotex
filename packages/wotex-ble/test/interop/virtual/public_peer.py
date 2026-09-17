"""Owned real-GATT fixture control for public BEAM/Runtime assertions.

The Unix socket controls only fixture stimuli and observations. Its responses
are never supplied as transport responses to the library under test.
"""

import asyncio
import json
import os
from pathlib import Path
import signal

from dbus_next import MessageType, Variant
from dbus_next.aio import MessageBus

from dbus_monitor import OwnershipMonitor
from gatt_peer import Peer, call, until, PROPS, OM, ADAPTER, DEVICE, ROOT, UUIDS


class PublicPeer:
    def __init__(self, address, bus, monitor):
        self.address = address
        self.bus = bus
        self.monitor = monitor
        self.peer = Peer(bus)
        self.advertising = False
        self.device = None
        self.baseline = set()
        self.lock = asyncio.Lock()
        self.stop = asyncio.Event()
        self.generation = 0
        self.failure = None
        self.bus.add_message_handler(self.watch_sender)

    def watch_sender(self, message):
        if (
            message.message_type == MessageType.SIGNAL
            and message.sender == "org.freedesktop.DBus"
            and message.member == "NameOwnerChanged"
        ):
            name, previous, current = message.body
            if (
                not previous
                and current == name
                and name.startswith(":")
                and name not in self.baseline
            ):
                self.monitor.watch(name)
        return None

    async def names(self):
        return set(
            (
                await call(
                    self.bus,
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "ListNames",
                    destination="org.freedesktop.DBus",
                )
            )[0]
        )

    async def start(self):
        await self.bus.request_name("io.wotex.BLESoftwarePeer")
        await call(
            self.bus,
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "AddMatch",
            "s",
            [
                "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'"
            ],
            destination="org.freedesktop.DBus",
        )
        self.baseline = await self.names()
        await call(
            self.bus,
            "/org/bluez",
            "org.bluez.AgentManager1",
            "RegisterAgent",
            "os",
            [ROOT + "/agent", "DisplayYesNo"],
        )
        await call(
            self.bus,
            "/org/bluez",
            "org.bluez.AgentManager1",
            "RequestDefaultAgent",
            "o",
            [ROOT + "/agent"],
        )
        await call(
            self.bus,
            "/org/bluez/hci1",
            "org.bluez.GattManager1",
            "RegisterApplication",
            "oa{sv}",
            [ROOT, {}],
        )
        return await self.reset()

    async def snapshot(self):
        if self.monitor.failure is not None:
            raise self.monitor.failure
        native = (await self.names()) - self.baseline
        native = {name for name in native if name.startswith(":")}
        counts = {}
        for sender, path, interface, member in self.monitor.calls:
            if sender in self.monitor.senders:
                counts[member] = counts.get(member, 0) + 1
        peer_counts = {}
        for item in self.peer.trace:
            member = item["member"]
            peer_counts[member] = peer_counts.get(member, 0) + 1
        objects = (await call(self.bus, "/", OM, "GetManagedObjects"))[0]
        properties = objects.get(self.device, {}).get(DEVICE, {})
        connected = properties.get("Connected")
        return {
            "peer_connected": connected.value if connected is not None else False,
            "native_senders": sorted(native),
            "agents": len(self.monitor.agents),
            "notification_sessions": len(self.monitor.notifications),
            "pending_controls": len(self.monitor.pending),
            "calls": counts,
            "peer_calls": peer_counts,
            "notifying": sorted(self.peer.notifying),
            "confirms": self.peer.confirms,
            "values": {key: value.hex() for key, value in self.peer.values.items()},
            "generation": self.generation,
        }

    async def reset(self):
        if self.baseline:
            stats = await self.snapshot()
            assert (
                stats["native_senders"] == []
                and stats["agents"] == 0
                and stats["notification_sessions"] == 0
            ), stats
        if self.advertising:
            await call(
                self.bus,
                "/org/bluez/hci1",
                "org.bluez.LEAdvertisingManager1",
                "UnregisterAdvertisement",
                "o",
                [ROOT + "/advertisement"],
            )
            self.advertising = False
        objects = (await call(self.bus, "/", OM, "GetManagedObjects"))[0]
        for path, interfaces in objects.items():
            properties = interfaces.get(DEVICE)
            if properties and properties["Adapter"].value in (
                "/org/bluez/hci0",
                "/org/bluez/hci1",
            ):
                await call(
                    self.bus,
                    properties["Adapter"].value,
                    ADAPTER,
                    "RemoveDevice",
                    "o",
                    [path],
                )
        for number in range(2):
            path = "/org/bluez/hci" + str(number)
            await call(
                self.bus,
                path,
                PROPS,
                "Set",
                "ssv",
                [ADAPTER, "Powered", Variant("b", False)],
            )
            await call(
                self.bus,
                path,
                PROPS,
                "Set",
                "ssv",
                [ADAPTER, "Powered", Variant("b", True)],
            )
        objects = (await call(self.bus, "/", OM, "GetManagedObjects"))[0]
        remote_address = objects["/org/bluez/hci1"][ADAPTER]["Address"].value
        await call(
            self.bus,
            "/org/bluez/hci0",
            ADAPTER,
            "SetDiscoveryFilter",
            "a{sv}",
            [{"Transport": Variant("s", "le")}],
        )
        await call(self.bus, "/org/bluez/hci0", ADAPTER, "StartDiscovery")
        # btvirt emits advertisements on enabling, so scanning must be ready first.
        await call(
            self.bus,
            "/org/bluez/hci1",
            "org.bluez.LEAdvertisingManager1",
            "RegisterAdvertisement",
            "oa{sv}",
            [ROOT + "/advertisement", {}],
        )
        self.advertising = True

        async def discovered():
            objects = (await call(self.bus, "/", OM, "GetManagedObjects"))[0]
            for path, interfaces in objects.items():
                props = interfaces.get(DEVICE, {})
                if (
                    props.get("Address", Variant("s", "")).value == remote_address
                    and props.get("Adapter", Variant("o", "/")).value
                    == "/org/bluez/hci0"
                ):
                    return path, props

        self.device, properties = await until(
            discovered, "public fixture advertisement"
        )
        await call(self.bus, "/org/bluez/hci0", ADAPTER, "StopDiscovery")
        await call(self.bus, self.device, DEVICE, "Connect")

        async def resolved():
            props = (await call(self.bus, self.device, PROPS, "GetAll", "s", [DEVICE]))[
                0
            ]
            return props["Connected"].value and props["ServicesResolved"].value

        await until(resolved, "public fixture service resolution")
        self.peer.values.update(
            {label: b"\x34\x12" if label == "value" else b"\x00" for label in UUIDS}
        )
        self.peer.values["duplicate_a"] = b"\xa1"
        self.peer.values["duplicate_b"] = b"\xb2"
        self.peer.denied.clear()
        assert not self.peer.notifying
        self.peer.trace.clear()
        self.peer.confirms = 0
        self.monitor.assert_released()
        self.monitor.senders.clear()
        self.monitor.calls.clear()
        self.monitor.acknowledgements.clear()
        self.generation += 1
        return {
            "peer": {
                "adapter": "/org/bluez/hci0",
                "address": remote_address,
                "address_type": properties["AddressType"].value,
            },
            "bus_address": self.address,
        }

    async def operation(self, request):
        if not isinstance(request, dict) or set(request) != {"operation", "parameters"}:
            raise ValueError("invalid_request")
        operation, parameters = request["operation"], request["parameters"]
        if operation == "reset" and parameters == {}:
            return await self.reset()
        if operation == "stats" and parameters == {}:
            return await self.snapshot()
        if (
            operation == "value"
            and isinstance(parameters, dict)
            and set(parameters) == {"label", "hex", "emit"}
        ):
            label, encoded, emit = (
                parameters["label"],
                parameters["hex"],
                parameters["emit"],
            )
            if (
                label not in UUIDS
                or not isinstance(encoded, str)
                or len(encoded) > 1024
                or type(emit) is not bool
            ):
                raise ValueError("invalid_value")
            value = bytes.fromhex(encoded)
            if value.hex() != encoded:
                raise ValueError("invalid_value")
            if emit:
                await self.peer.changed(label, value)
            else:
                self.peer.values[label] = value
            return {}
        if (
            operation == "deny"
            and isinstance(parameters, dict)
            and set(parameters) == {"label", "denied"}
        ):
            if (
                parameters["label"] not in UUIDS
                or type(parameters["denied"]) is not bool
            ):
                raise ValueError("invalid_denial")
            if parameters["denied"]:
                self.peer.denied.add(parameters["label"])
            else:
                self.peer.denied.discard(parameters["label"])
            return {}
        if operation == "disconnect" and parameters == {}:
            await call(self.bus, self.device, DEVICE, "Disconnect")
            return {}
        raise ValueError("unsupported_operation")

    async def control(self, reader, writer):
        try:
            data = await asyncio.wait_for(reader.readline(), 5)
            if not data.endswith(b"\n") or len(data) > 4096:
                raise ValueError("invalid_frame")
            request = json.loads(data)
            async with self.lock:
                result = await asyncio.wait_for(self.operation(request), 20)
            response = {"ok": result}
        except Exception as error:
            self.failure = type(error).__name__
            response = {"error": self.failure}
        try:
            encoded = json.dumps(response, separators=(",", ":")).encode() + b"\n"
            assert len(encoded) <= 16384
            writer.write(encoded)
            await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()

    async def close(self):
        statistics = await self.snapshot()
        clean = (
            not statistics["native_senders"]
            and statistics["agents"] == 0
            and statistics["notification_sessions"] == 0
            and not statistics["notifying"]
            and self.failure is None
        )
        if self.advertising:
            await call(
                self.bus,
                "/org/bluez/hci1",
                "org.bluez.LEAdvertisingManager1",
                "UnregisterAdvertisement",
                "o",
                [ROOT + "/advertisement"],
            )
        await call(
            self.bus,
            "/org/bluez/hci1",
            "org.bluez.GattManager1",
            "UnregisterApplication",
            "o",
            [ROOT],
        )
        await call(
            self.bus,
            "/org/bluez",
            "org.bluez.AgentManager1",
            "UnregisterAgent",
            "o",
            [ROOT + "/agent"],
        )
        Path("/results/public-peer-result.json").write_text(
            json.dumps({"clean": clean, "statistics": statistics}, indent=2) + "\n"
        )
        await self.monitor.close()
        self.bus.disconnect()
        await self.bus.wait_for_disconnect()
        assert clean, statistics


async def main():
    address = os.environ["DBUS_SYSTEM_BUS_ADDRESS"]
    bus = await MessageBus(bus_address=address).connect()
    monitor = await OwnershipMonitor.start(address)
    fixture = PublicPeer(address, bus, monitor)
    config = await fixture.start()
    socket = "/run/wbl/control.sock"
    async with await asyncio.start_unix_server(
        fixture.control, path=socket, limit=4096
    ):
        config["control_socket"] = socket
        Path("/run/wbl/software.json").write_text(json.dumps(config) + "\n")
        loop = asyncio.get_running_loop()
        for number in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(number, fixture.stop.set)
        await fixture.stop.wait()
    await fixture.close()


if __name__ == "__main__":
    asyncio.run(main())
