"""Injected D-Bus contract tests; virtual-controller interoperability is separate."""

import asyncio
import copy
import json
import pathlib
import sys
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "priv" / "bluez"))
import client
import bridge

PEER = {"adapter": "/org/bluez/hci0", "address": "AA:BB:CC:DD:EE:FF", "address_type": "random"}
DEVICE_PATH = "/unrelated/device"
SERVICE_PATH = "/actual/service"
CHAR_PATH = "/another/characteristic"
OPTIONS = {"peer": PEER, "connection": "borrowed", "bus_address": "unix:path=/tmp/test-bus"}


def objects(connected=True, resolved=True, count=2):
    result = {
        PEER["adapter"]: {client.ADAPTER: {}},
        DEVICE_PATH: {client.DEVICE: {"Adapter": PEER["adapter"], "Address": PEER["address"], "AddressType": "random", "Connected": connected, "ServicesResolved": resolved}},
        SERVICE_PATH: {client.SERVICE: {"Device": DEVICE_PATH, "UUID": "180f"}},
    }
    for index in range(count):
        result[CHAR_PATH + str(index)] = {client.CHARACTERISTIC: {"Service": SERVICE_PATH, "UUID": "2a19", "Flags": ["read", "future-flag"], "Handle": index + 1}}
    return result


class Bus:
    def __init__(self, data=None):
        self.data = data if data is not None else objects()
        self.calls = []
        self.handlers = []
        self.closed = asyncio.Event()
        self.unique_name = ":1.55"
        self.before_snapshot = None
        self.connect_error = None
        self.resolve_on_connect = True
        self.connect_block = False
        self.connect_entered = asyncio.Event()
        self.close_error = False

    async def connect(self):
        self.calls.append(("bus", "connect"))

    def listen(self, handler):
        self.handlers.append(handler)

    def unlisten(self, handler):
        self.handlers.remove(handler)

    def disconnect(self):
        self.calls.append(("bus", "disconnect"))
        self.closed.set()

    async def wait_closed(self):
        await self.closed.wait()

    def emit(self, member, body, interface=client.MANAGER, object_path="/", sender=":1.2"):
        for handler in self.handlers[:]:
            handler(sender, object_path, interface, member, body)

    async def call(self, destination, object_path, interface, member, signature, body):
        self.calls.append((destination, object_path, interface, member, signature, body))
        if member == "GetNameOwner":
            return [":1.2"]
        if member == "GetManagedObjects":
            self.assert_listener()
            data = copy.deepcopy(self.data)
            if self.before_snapshot:
                self.before_snapshot(self)
            return [data]
        if member == "Connect":
            self.connect_entered.set()
            if self.connect_error:
                raise client.Failure(self.connect_error)
            if self.connect_block:
                await asyncio.Event().wait()
            self.data[DEVICE_PATH][client.DEVICE].update(Connected=True, ServicesResolved=self.resolve_on_connect)
        if member == "Disconnect" and self.close_error:
            raise client.Failure("remote_error")
        return []

    def assert_listener(self):
        if not self.handlers:
            raise AssertionError("snapshot preceded signal listener")

    def count(self, member):
        return sum(len(call) == 6 and call[3] == member for call in self.calls)


class DiscoveryTest(unittest.IsolatedAsyncioTestCase):
    async def open(self, bus=None, **options):
        bus = bus or Bus()
        events = []
        central = client.Central(events.append, lambda address: bus)
        self.addAsyncCleanup(central.close)
        result = await central.open({**OPTIONS, **options}, 500)
        return central, bus, events, result

    async def test_WBL_V03_S01_N01_exact_associations_and_duplicate_uuid_pages(self):
        central, bus, _, opened = await self.open()
        self.assertEqual(opened, {"generation": 1, "device_path": DEVICE_PATH, "link_owned": False, "sender": ":1.55"})
        page = await central.discover({"limit": 1}, 100)
        self.assertEqual(page["characteristics"][0], {"service_uuid": "0000180f-0000-1000-8000-00805f9b34fb", "characteristic_uuid": "00002a19-0000-1000-8000-00805f9b34fb", "service_path": SERVICE_PATH, "object_path": CHAR_PATH + "0", "handle": 1, "flags": ["read", "future-flag"], "generation": 1})
        second = await central.discover({"cursor": page["cursor"], "limit": 1}, 100)
        self.assertEqual(second["characteristics"][0]["object_path"], CHAR_PATH + "1")
        self.assertIsNone(second["cursor"])
        self.assertEqual(bus.count("GetManagedObjects"), 2)
        with self.assertRaisesRegex(client.Failure, "invalid_cursor"):
            await central.discover({"cursor": "a" * 32}, 100)
        await central.close()
        await central.close()
        self.assertEqual(bus.count("Disconnect"), 0)
        self.assertEqual(bus.handlers, [])

    async def test_WBL_V03_snapshot_listener_race_reconciles(self):
        bus = Bus()
        def change(bus):
            bus.before_snapshot = None
            bus.data[CHAR_PATH + "0"][client.CHARACTERISTIC]["Handle"] = 44
            bus.emit("InterfacesAdded", ["/new", {}])
        bus.before_snapshot = change
        central, bus, _, _ = await self.open(bus)
        self.assertEqual(bus.count("GetManagedObjects"), 2)
        self.assertEqual(central.characteristics[0]["handle"], 44)

    async def test_WBL_V03_topology_invalidates_cursor_but_value_does_not(self):
        central, bus, _, _ = await self.open()
        first = await central.discover({"limit": 1}, 100)
        bus.emit("PropertiesChanged", [client.CHARACTERISTIC, {"Value": b"abc"}, []], interface=client.PROPERTIES, object_path=CHAR_PATH + "0")
        self.assertIsNotNone((await central.discover({"cursor": first["cursor"]}, 100)))
        bus.emit("PropertiesChanged", [client.CHARACTERISTIC, {"Flags": ["write"]}, []], interface=client.PROPERTIES, object_path=CHAR_PATH + "0")
        with self.assertRaisesRegex(client.Failure, "stale_discovery"):
            await central.discover({"cursor": first["cursor"]}, 100)
        page = await central.discover({}, 100)
        self.assertEqual(page["generation"], 2)
        with self.assertRaisesRegex(client.Failure, "invalid_cursor"):
            await central.discover({"cursor": first["cursor"]}, 100)

    async def test_WBL_V04_ownership_modes(self):
        for mode, connected, expected in [("borrowed", True, False), ("owned", True, False), ("owned", False, True)]:
            with self.subTest(mode=mode, connected=connected):
                central, bus, _, result = await self.open(Bus(objects(connected, connected)), connection=mode)
                self.assertEqual(result["link_owned"], expected)
                self.assertEqual(bus.count("Connect"), int(expected))
                await central.close()
                self.assertEqual(bus.count("Disconnect"), int(expected))
                self.assertTrue(bus.closed.is_set())

    async def test_WBL_V04_failed_startup_unwinds_acquisitions(self):
        for connected, resolved, mode, error in [(False, False, "borrowed", "disconnected"), (True, False, "borrowed", "services_unresolved"), (False, False, "owned", "timeout")]:
            bus = Bus(objects(connected, resolved))
            bus.resolve_on_connect = False
            central = client.Central(lambda _: None, lambda _: bus)
            with self.assertRaisesRegex(client.Failure, error):
                await central.open({**OPTIONS, "connection": mode}, 20)
            self.assertEqual(bus.handlers, [])
            self.assertTrue(bus.closed.is_set())
            self.assertEqual(bus.count("Disconnect"), int(mode == "owned"))

    async def test_WBL_V04_failed_connect_and_pending_connect_cancellation(self):
        for failure, expected in [("not_permitted", 0), ("timeout", 1)]:
            bus = Bus(objects(False, False))
            bus.connect_error = failure
            central = client.Central(lambda _: None, lambda _: bus)
            with self.assertRaisesRegex(client.Failure, failure):
                await central.open({**OPTIONS, "connection": "owned"}, 100)
            self.assertEqual(bus.count("Disconnect"), expected)
        bus = Bus(objects(False, False))
        bus.connect_block = True
        central = client.Central(lambda _: None, lambda _: bus)
        task = asyncio.create_task(central.open({**OPTIONS, "connection": "owned"}, 60000))
        await bus.connect_entered.wait()
        started = time.monotonic()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertLess(time.monotonic() - started, 0.1)
        self.assertEqual(bus.count("Disconnect"), 1)
        self.assertEqual(bus.handlers, [])

    async def test_WBL_V04_owner_or_device_loss_is_terminal_once(self):
        cases = [
            ("NameOwnerChanged", ["org.bluez", ":1.2", ":1.3"], "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "owner_changed"),
            ("InterfacesRemoved", [SERVICE_PATH, [client.SERVICE]], client.MANAGER, "/", ":1.2", "disconnected"),
            ("PropertiesChanged", [client.DEVICE, {"Connected": False}, []], client.PROPERTIES, DEVICE_PATH, ":1.2", "disconnected"),
        ]
        for member, body, interface, path, sender, error in cases:
            central, bus, events, _ = await self.open()
            bus.emit(member, body, interface, path, ":99.99")
            self.assertEqual(events, [])
            bus.emit(member, body, interface, path, sender)
            bus.emit(member, body, interface, path, sender)
            self.assertEqual(events, [error])
            with self.assertRaisesRegex(client.Failure, error):
                await central.discover({}, 100)
            await central.close()
        central, bus, events, _ = await self.open()
        bus.closed.set()
        await asyncio.sleep(0)
        self.assertEqual(events, ["disconnected"])

    async def test_WBL_V03_unstable_snapshot_and_retarget_fail_closed(self):
        bus = Bus()
        bus.before_snapshot = lambda bus: bus.emit("InterfacesAdded", ["/new", {}])
        central = client.Central(lambda _: None, lambda _: bus)
        with self.assertRaisesRegex(client.Failure, "snapshot_unstable"):
            await central.open(OPTIONS, 100)
        self.assertEqual(bus.count("GetManagedObjects"), 4)
        central, bus, _, _ = await self.open()
        bus.data["/replacement"] = bus.data.pop(DEVICE_PATH)
        with self.assertRaisesRegex(client.Failure, "peer_changed"):
            await central.discover({}, 100)

    async def test_WBL_C02_page_options_limits_and_cleanup_errors(self):
        central, bus, _, _ = await self.open(Bus(objects(count=70)))
        first = await central.discover({}, 100)
        self.assertEqual(len(first["characteristics"]), 64)
        for parameters in [None, [], {"limit": 0}, {"limit": 65}, {"limit": True}, {"foreign": 1}, {"cursor": []}]:
            with self.assertRaises(client.Failure):
                await central.discover(parameters, 100)
        central.link_owned = True
        bus.close_error = True
        await central.close()
        self.assertTrue(bus.closed.is_set())
        self.assertEqual(bus.handlers, [])


class ValuesTest(unittest.TestCase):
    def test_WBL_C02_peer_and_object_limits(self):
        for value in [None, {}, {**OPTIONS, "extra": 1}, {**OPTIONS, "peer": {}}, {**OPTIONS, "peer": {**PEER, "address": 1}}, {**OPTIONS, "peer": {**PEER, "address_type": "name"}}, {**OPTIONS, "connection": "automatic"}, {**OPTIONS, "bus_address": "tcp:host=example.com"}]:
            with self.assertRaises(client.Failure):
                client.peer_options(value)
        for value in [{}, {str(i): {} for i in range(4097)}, {"bad path": {}}, {PEER["adapter"]: []}]:
            with self.assertRaises(client.Failure):
                client.catalogue(value, PEER, 1)
        duplicate = objects()
        duplicate["/duplicate"] = duplicate[DEVICE_PATH]
        with self.assertRaisesRegex(client.Failure, "ambiguous_peer"):
            client.catalogue(duplicate, PEER, 1)

    def test_WBL_V03_invalid_fields_and_false_path_prefix_association(self):
        for field, value in [("UUID", "wrong"), ("Handle", 0), ("Handle", True), ("Flags", ["read", "read"]), ("Flags", ["x" * 65]), ("Flags", None)]:
            data = objects()
            data[CHAR_PATH + "0"][client.CHARACTERISTIC][field] = value
            with self.assertRaisesRegex(client.Failure, "invalid_characteristic"):
                client.catalogue(data, PEER, 1)
        for field, value in [("Service", DEVICE_PATH + "/fake"), ("Service", [])]:
            data = objects(count=1)
            data[CHAR_PATH + "0"][client.CHARACTERISTIC][field] = value
            self.assertEqual(client.catalogue(data, PEER, 1)[2], [])
        data = objects(count=1)
        data[SERVICE_PATH][client.SERVICE]["Device"] = DEVICE_PATH + "0"
        self.assertEqual(client.catalogue(data, PEER, 1)[2], [])
        for field in ["Address", "Adapter", "AddressType"]:
            data = objects()
            data[DEVICE_PATH][client.DEVICE][field] = []
            with self.assertRaisesRegex(client.Failure, "peer_not_found"):
                client.catalogue(data, PEER, 1)

    def test_WBL_C07_duplicate_depth_nodes_unknown_and_nonfinite_frames(self):
        request = {"version": 1, "id": "a", "operation": "discover", "parameters": {}, "timeout_ms": 100}
        line = json.dumps(request).encode() + b"\n"
        self.assertEqual(bridge.decode(line), request)
        malformed = [line[:-1], b"{}\n", b"\xff\n", b"[\n", b'{"version":1,"version":1}\n', b"\n" * 131073]
        for change in [{"version": True}, {"id": 1}, {"operation": []}, {"operation": "inject"}, {"timeout_ms": 0}, {"parameters": {"x": float("nan")}}, {"parameters": {"x": "\ud800"}}, {"parameters": {"x": [0] * 1025}}, {"extra": 1}]:
            malformed.append(json.dumps({**request, **change}).encode() + b"\n")
        nested = {}; current = nested
        for _ in range(8):
            current["x"] = {}; current = current["x"]
        malformed.append(json.dumps({**request, "parameters": nested}).encode() + b"\n")
        for value in malformed:
            with self.subTest(value=value[:90]):
                with self.assertRaises(client.Failure):
                    bridge.decode(value)


class OwnerTest(unittest.IsolatedAsyncioTestCase):
    async def test_WBL_C03_EOF_cancels_blocked_connect_and_releases_bus(self):
        bus = Bus(objects(False, False)); bus.connect_block = True
        central = client.Central(lambda _: None, lambda _: bus)
        owner = bridge.Bridge(lambda _: None, lambda _: central)
        reader = asyncio.StreamReader()
        reader.feed_data(json.dumps({"version": 1, "id": "open", "operation": "open", "parameters": {**OPTIONS, "connection": "owned"}, "timeout_ms": 60000}).encode() + b"\n")
        task = asyncio.create_task(owner.run(reader))
        await bus.connect_entered.wait()
        start = time.monotonic()
        reader.feed_eof()
        await task
        self.assertLess(time.monotonic() - start, 0.1)
        self.assertEqual(bus.count("Disconnect"), 1)
        self.assertEqual(bus.handlers, [])
        self.assertTrue(bus.closed.is_set())

    async def test_WBL_C07_single_sender_request_sequence(self):
        bus = Bus(); outputs = []
        owner = bridge.Bridge(outputs.append, lambda signal: client.Central(signal, lambda _: bus))
        reader = asyncio.StreamReader()
        task = asyncio.create_task(owner.run(reader))
        for index, (identifier, operation, parameters) in enumerate([("a", "open", OPTIONS), ("b", "discover", {"limit": 1}), ("c", "close", {})]):
            reader.feed_data(json.dumps({"version": 1, "id": identifier, "operation": operation, "parameters": parameters, "timeout_ms": 1000}).encode() + b"\n")
            while len(outputs) <= index:
                await asyncio.sleep(0)
        await asyncio.wait_for(task, 1)
        self.assertEqual([output["id"] for output in outputs], ["a", "b", "c"])
        self.assertTrue(all(output["ok"] for output in outputs))
        self.assertEqual(outputs[-1]["result"], None)
        self.assertTrue(bus.closed.is_set())


if __name__ == "__main__":
    unittest.main()
