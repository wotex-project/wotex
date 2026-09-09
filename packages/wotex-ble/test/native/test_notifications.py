"""Native notification ownership tests; no virtual Bluetooth claim."""

import asyncio
import base64
import json
import pathlib
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from client import Central, CHARACTERISTIC, PROPERTIES, SERVICE, DEVICE, Failure
from bridge import Bridge
from test_bluez import Bus, CHAR_PATH, SERVICE_PATH, DEVICE_PATH, OPTIONS, objects
from test_procedures import TARGET


class NotificationBus(Bus):
    def __init__(self, count=2):
        super().__init__(objects(count=count))
        for item in self.data.values():
            if CHARACTERISTIC in item:
                item[CHARACTERISTIC]["Flags"] = ["read", "notify"]
        self.sessions = set()
        self.early = []
        self.start_error = None
        self.stop_error = None
        self.start_blocked = False
        self.stop_blocked = False
        self.started = asyncio.Event()
        self.stopping = asyncio.Event()
        self.start_release = None
        self.stop_release = None
        self.start_signature_invalid = False
        self.stop_signature_invalid = False
        self.owner = None
        self.client_calls = []
        self.read_started = asyncio.Event()
        self.read_blocked = False

    def value(self, value, object_path=CHAR_PATH + "0", sender=":1.2"):
        self.emit("PropertiesChanged", [CHARACTERISTIC, {"Value": value}, []], PROPERTIES, object_path, sender)

    def disconnect(self):
        self.sessions.difference_update(item for item in list(self.sessions) if item[0] == self.unique_name)
        super().disconnect()

    async def call(self, destination, object_path, interface, member, signature, body):
        if member == "ReadValue" and self.read_blocked:
            self.read_started.set()
            await asyncio.Event().wait()
        if member not in ("StartNotify", "StopNotify"):
            return await super().call(destination, object_path, interface, member, signature, body)
        self.calls.append((destination, object_path, interface, member, signature, body))
        self.client_calls.append((self.unique_name, member, object_path))
        assert destination == ":1.2" and interface == CHARACTERISTIC and signature == "" and body in (None, [])
        if member == "StartNotify":
            assert object_path in self.owner.notifications.paths
            self.started.set()
            if self.start_error:
                raise self.start_error
            self.sessions.add((self.unique_name, object_path))
            for value in self.early:
                self.value(value, object_path)
            if self.start_release is not None:
                await self.start_release.wait()
            if self.start_blocked:
                await asyncio.Event().wait()
            return [True] if self.start_signature_invalid else []
        self.stopping.set()
        if self.stop_release is not None:
            await self.stop_release.wait()
        # A late value while releasing must already be locally suppressed.
        self.value(b"late", object_path)
        if self.stop_blocked:
            await asyncio.Event().wait()
        if self.stop_error:
            raise self.stop_error
        self.sessions.discard((self.unique_name, object_path))
        return [True] if self.stop_signature_invalid else []


class NotificationTest(unittest.IsolatedAsyncioTestCase):
    async def central(self, bus=None):
        bus = bus or NotificationBus()
        central = Central(lambda _: None, lambda _: bus)
        bus.owner = central
        self.addAsyncCleanup(central.close)
        await central.open(OPTIONS, 1000)
        events = []
        central.emit = events.append
        return central, bus, events

    async def subscribe(self, central, identifier="sub-1", target=TARGET, mode="auto"):
        result = await central.notifications.subscribe({"address": target, "mode": mode}, 1000, identifier)
        central.notifications.activate(identifier)
        return result

    async def settled(self, central):
        for _ in range(100):
            if not central.notifications.entries and not central.notifications.background:
                return
            await asyncio.sleep(0.001)
        self.fail("native subscription resources did not settle")

    async def trace(self, data):
        bus = NotificationBus()
        target_path = data.get("path", CHAR_PATH + "0")
        characteristic = bus.data.pop(CHAR_PATH + "0")
        characteristic[CHARACTERISTIC]["Flags"] = data["flags"]
        bus.data[target_path] = characteristic
        central, bus, events = await self.central(bus)
        target = {**TARGET, "object_path": target_path}
        bus.start_release = asyncio.Event()
        bus.stop_release = asyncio.Event()
        clock = {"now": 0}
        source_clock = SimpleNamespace(monotonic=lambda: clock["now"])
        result = None
        canceled_deliveries = None
        pending = None
        identifier = None
        with patch("notifications.time", source_clock), patch("procedures.time", source_clock), patch("client.time", source_clock):
            for step in data["events"]:
                self.assertGreaterEqual(step["at_ms"] / 1000, clock["now"])
                clock["now"] = step["at_ms"] / 1000
                if step["event"] == "subscribe":
                    identifier = step["id"]
                    pending = asyncio.create_task(central.notifications.subscribe({"address": target, "mode": data["mode"]}, 1000, identifier))
                    while not pending.done() and not bus.started.is_set():
                        await asyncio.sleep(0)
                    if pending.done():
                        try:
                            await pending
                        except Failure as error:
                            result = {"error": {"code": error.code, "effect": "none"}}
                elif step["event"] == "start_notify_ok":
                    bus.start_release.set()
                    await pending
                    central.notifications.activate(identifier)
                elif step["event"] == "value_changed":
                    source = central.bluez_owner if step["sender"] == data["sender"] else ":9.9"
                    object_path = target_path if step["path"] == "bound" else step["path"]
                    bus.value(bytes.fromhex(step["bytes_hex"]), object_path, source)
                elif step["event"] == "cancel":
                    self.assertEqual(step["id"], identifier)
                    pending = asyncio.create_task(central.notifications.unsubscribe({"subscription_id": identifier}, 1000))
                    await bus.stopping.wait()
                elif step["event"] == "stop_notify_ok":
                    bus.stop_release.set()
                    await pending
                    canceled_deliveries = len(events)
                else:
                    self.fail("unknown lifecycle event")
        self.assertNotEqual(central.bluez_owner, bus.unique_name)
        self.assertTrue(all(sender == bus.unique_name for sender, _, _ in bus.client_calls))
        senders = [data.get("client_sender") for _, _, _ in bus.client_calls]
        return {"result": result,
                "deliveries": [{"bytes_hex": base64.b64decode(event["value"]["base64"]).hex(), "source": event["metadata"]["source"]} for event in events],
                "calls": {"start_notify": bus.count("StartNotify"), "stop_notify": bus.count("StopNotify")},
                "sender_pairs": [senders] if senders else [],
                "active_subscriptions": len(central.notifications.entries),
                "deliveries_after_cancel": len(events) - canceled_deliveries if canceled_deliveries is not None else 0}

    async def test_WBL_F06_F07_F08_exact_lifecycle_corpus_drives_real_native_owners(self):
        corpus = json.loads((pathlib.Path(__file__).resolve().parents[2] / "docs/specs/fixtures/contract-v1.json").read_text())
        self.assertEqual(corpus["format_version"], "1.0.0")
        fixtures = [case for case in corpus["cases"] if case["kind"] == "lifecycle_contract"]
        self.assertEqual({case["id"] for case in fixtures}, {"WBL-F06", "WBL-F07", "WBL-F08"})
        for case in fixtures:
            self.assertIn(case["operation"], ("subscribe_value_changes", "subscribe_wrong_source", "subscribe_ambiguous_procedure"))
            observed = await self.trace(case["input"])
            self.assertEqual(case["expectation"]["operator"], "exact")
            expected = case["expectation"]["value"]
            self.assertEqual({key: observed[key] for key in expected}, expected)

    async def test_WBL_P05_V07_explicit_modes_duplicate_and_same_sender_cleanup(self):
        for flags, requested, effective in [(["notify"], "notify", "notify"), (["indicate"], "indicate", "indicate"), (["notify", "indicate"], "auto", "bluez_selected")]:
            bus = NotificationBus()
            bus.data[CHAR_PATH + "0"][CHARACTERISTIC]["Flags"] = flags
            central, bus, events = await self.central(bus)
            result = await self.subscribe(central, mode=requested)
            self.assertEqual(result["effective_mode"], effective)
            self.assertEqual(result["generation"], 1)
            with self.assertRaisesRegex(Failure, "already_subscribed"):
                await self.subscribe(central, "duplicate")
            self.assertEqual(bus.count("StartNotify"), 1)
            self.assertEqual(events, [])
            await central.notifications.unsubscribe({"subscription_id": "sub-1"}, 1000)
            self.assertEqual(bus.client_calls, [(":1.55", "StartNotify", CHAR_PATH + "0"), (":1.55", "StopNotify", CHAR_PATH + "0")])
            self.assertEqual(events, [])
            self.assertEqual(bus.sessions, set())
            self.assertEqual(central.notifications.entries, {})
            self.assertEqual(central.notifications.paths, {})
            with self.assertRaisesRegex(Failure, "invalid_subscription"):
                await central.notifications.unsubscribe({"subscription_id": "foreign"}, 1000)

    async def test_WBL_V08_one_early_value_is_released_only_after_ack_and_equal_reports_survive(self):
        bus = NotificationBus()
        bus.early = [b"\x01"]
        central, bus, events = await self.central(bus)
        result = await central.notifications.subscribe({"address": TARGET, "mode": "notify"}, 1000, "sub-1")
        self.assertEqual(events, [])
        central.notifications.activate("sub-1")
        bus.value(b"\x01")
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0], events[1])
        self.assertEqual(events[0], {"version": 1, "subscription_id": "sub-1", "generation": 1, "event": "value", "value": {"type": "bytes", "base64": "AQ=="}, "metadata": {"source": "bluez_value_change", "characteristic": result["characteristic"], "requested_mode": "notify", "effective_mode": "notify"}})
        bus.value(b"wrong", sender=":9.9")
        bus.value(b"wrong", object_path="/foreign")
        self.assertEqual(len(events), 2)
        await central.notifications.unsubscribe({"subscription_id": "sub-1"}, 1000)
        bus.value(b"late")
        self.assertEqual(len(events), 2)

    async def test_WBL_V08_early_overflow_malformed_value_and_notifying_loss_are_terminal_once(self):
        bus = NotificationBus()
        bus.early = [b"one", b"two"]
        central, bus, events = await self.central(bus)
        with self.assertRaisesRegex(Failure, "response_limit"):
            await self.subscribe(central)
        self.assertEqual(events, [])
        self.assertEqual(bus.count("StopNotify"), 1)
        self.assertEqual(bus.sessions, set())
        for value in (False, [1], b"x" * 513):
            central, bus, events = await self.central()
            await self.subscribe(central)
            bus.value(value)
            bus.value(value)
            await self.settled(central)
            self.assertEqual([event["metadata"] for event in events], [{"error": {"code": "invalid_response"}}])
            self.assertEqual(bus.count("StopNotify"), 1)
        central, bus, events = await self.central()
        await self.subscribe(central)
        for _ in range(2):
            bus.emit("PropertiesChanged", [CHARACTERISTIC, {"Notifying": False}, []], PROPERTIES, CHAR_PATH + "0")
        await self.settled(central)
        self.assertEqual([event["metadata"] for event in events], [{"error": {"code": "subscription_lost"}}])

    async def test_WBL_V09_stop_failure_releases_only_our_bus_sender(self):
        central, bus, events = await self.central()
        await self.subscribe(central)
        foreign = (":9.9", CHAR_PATH + "0")
        bus.sessions.add(foreign)
        bus.stop_error = Failure("remote_error", "org.bluez.Error.Failed")
        with self.assertRaisesRegex(Failure, "remote_error"):
            await central.notifications.unsubscribe({"subscription_id": "sub-1"}, 1000)
        self.assertTrue(central.closed)
        self.assertEqual(bus.sessions, {foreign})
        self.assertEqual(bus.handlers, [])
        self.assertEqual(central.notifications.entries, {})
        self.assertEqual(events, [])

    async def test_WBL_C03_pending_start_and_blocked_stop_have_bounded_owner_cleanup(self):
        central, bus, _ = await self.central()
        bus.start_blocked = True
        task = asyncio.create_task(self.subscribe(central))
        await bus.started.wait()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertEqual(bus.count("StopNotify"), 1)
        self.assertEqual(bus.sessions, set())
        central, bus, _ = await self.central()
        await self.subscribe(central)
        bus.stop_blocked = True
        before = time.monotonic()
        await central.close()
        self.assertLess(time.monotonic() - before, 1)
        self.assertEqual(bus.sessions, set())
        self.assertEqual(bus.handlers, [])
        self.assertEqual(central.notifications.entries, {})

    async def test_WBL_C07_rejected_or_malformed_acknowledgements_never_establish(self):
        for malformed in (False, True):
            central, bus, events = await self.central()
            bus.start_signature_invalid = malformed
            if not malformed:
                bus.start_error = Failure("not_permitted")
            with self.assertRaisesRegex(Failure, "invalid_response" if malformed else "not_permitted"):
                await self.subscribe(central)
            self.assertEqual(events, [])
            self.assertEqual(bus.sessions, set())
            self.assertEqual(bus.count("StopNotify"), int(malformed))
        central, bus, _ = await self.central()
        await self.subscribe(central)
        bus.stop_signature_invalid = True
        with self.assertRaisesRegex(Failure, "invalid_response"):
            await central.notifications.unsubscribe({"subscription_id": "sub-1"}, 1000)
        self.assertTrue(central.closed)

    async def test_WBL_V09_owned_identity_and_malformed_signals_end_one_generation(self):
        for path, body, expected in [
            (CHAR_PATH + "0", [CHARACTERISTIC, {"Notifying": 1}, []], "invalid_response"),
            (CHAR_PATH + "0", [CHARACTERISTIC, {}, ["Value"]], "invalid_response"),
            (CHAR_PATH + "0", [CHARACTERISTIC, {}, [[]]], "invalid_response"),
            (CHAR_PATH + "0", [[], {}, []], "invalid_response"),
            (CHAR_PATH + "0", [CHARACTERISTIC, {"Flags": ["indicate"]}, []], "stale_discovery"),
            (SERVICE_PATH, [SERVICE, {"UUID": "180a"}, []], "stale_discovery"),
            (DEVICE_PATH, [DEVICE, {"AddressType": "public"}, []], "peer_changed"),
        ]:
            central, bus, events = await self.central()
            await self.subscribe(central)
            bus.emit("PropertiesChanged", body, PROPERTIES, path, ":9.9")
            self.assertEqual(events, [])
            bus.emit("PropertiesChanged", body, PROPERTIES, path)
            bus.emit("PropertiesChanged", body, PROPERTIES, path)
            await self.settled(central)
            self.assertEqual([event["metadata"]["error"]["code"] for event in events], [expected])
            self.assertEqual(bus.count("StopNotify"), 1)
            self.assertEqual(bus.sessions, set())

    async def test_WBL_C03_unsubscribe_control_preempts_blocked_read_and_escalates(self):
        for blocked_stop in (False, True):
            bus = NotificationBus()
            bus.read_blocked = True
            bus.stop_blocked = blocked_stop
            outputs = asyncio.Queue()
            owner = Bridge(outputs.put_nowait, lambda signal: Central(signal, lambda _: bus))
            bus.owner = owner.central
            reader = asyncio.StreamReader()
            task = asyncio.create_task(owner.run(reader))
            try:
                def feed(identifier, operation, parameters, timeout=1000):
                    reader.feed_data(json.dumps({"version": 1, "id": identifier, "operation": operation, "parameters": parameters, "timeout_ms": timeout}).encode() + b"\n")
                feed("1", "open", OPTIONS)
                self.assertTrue((await asyncio.wait_for(outputs.get(), 1))["ok"])
                feed("2", "subscribe", {"address": TARGET, "mode": "auto"})
                self.assertTrue((await asyncio.wait_for(outputs.get(), 1))["ok"])
                feed("3", "read", {"address": TARGET}, 60000)
                await asyncio.wait_for(bus.read_started.wait(), 1)
                started = time.monotonic()
                feed("4", "unsubscribe", {"subscription_id": "2"}, 100)
                await asyncio.wait_for(bus.stopping.wait(), 0.1)
                if blocked_stop:
                    await asyncio.wait_for(task, 0.5)
                    self.assertTrue(bus.closed.is_set())
                else:
                    response = await asyncio.wait_for(outputs.get(), 0.5)
                    self.assertEqual(response, {"version": 1, "id": "4", "ok": True, "result": None})
                    self.assertEqual(owner.active["id"], "3")
                    self.assertFalse(bus.closed.is_set())
                self.assertLess(time.monotonic() - started, 0.5)
                self.assertEqual(bus.sessions, set())
                self.assertEqual(owner.central.notifications.entries, {})
                self.assertEqual(bus.count("StopNotify"), 1)
            finally:
                reader.feed_eof()
                await asyncio.wait_for(task, 1)
            self.assertEqual(owner.controls, set())

    async def test_WBL_C05_unsubscribe_controls_share_finite_admission_with_data(self):
        bus = NotificationBus()
        bus.stop_blocked = True
        outputs = []
        owner = Bridge(outputs.append, lambda signal: Central(signal, lambda _: bus))
        bus.owner = owner.central
        await owner.central.open(OPTIONS, 1000)
        self.addAsyncCleanup(owner.central.close)
        owner.opened = True
        await self.subscribe(owner.central, "1")
        owner.active = {"id": "active"}
        for index in range(62):
            owner.queue.put_nowait(({"id": str(index)}, 0))
        reader = asyncio.StreamReader()
        for identifier in ("2", "3"):
            reader.feed_data(json.dumps({"version": 1, "id": identifier, "operation": "unsubscribe", "parameters": {"subscription_id": "1"}, "timeout_ms": 50}).encode() + b"\n")
        reader.feed_eof()
        await owner.accept(reader)
        self.assertEqual(len(owner.controls), 1)
        self.assertEqual(outputs, [{"version": 1, "id": "3", "ok": False, "error": {"code": "busy"}}])
        await asyncio.gather(*owner.controls)
        await asyncio.sleep(0)
        self.assertEqual(owner.controls, set())
        self.assertEqual(bus.count("StopNotify"), 1)
        self.assertTrue(bus.closed.is_set())

    async def test_WBL_C05_active_bound_and_one_thousand_retired_lifetimes_keep_no_tombstones(self):
        central, bus, _ = await self.central(NotificationBus(count=65))
        for index in range(64):
            await self.subscribe(central, "sub-" + str(index), {**TARGET, "object_path": CHAR_PATH + str(index), "handle": index + 1})
        with self.assertRaisesRegex(Failure, "busy"):
            await self.subscribe(central, "overflow", {**TARGET, "object_path": CHAR_PATH + "64", "handle": 65})
        self.assertEqual(bus.count("StartNotify"), 64)
        await central.close()
        self.assertEqual(bus.sessions, set())
        central, bus, _ = await self.central()
        for index in range(1000):
            identifier = "sub-" + str(index)
            await self.subscribe(central, identifier)
            await central.notifications.unsubscribe({"subscription_id": identifier}, 1000)
            self.assertEqual(central.notifications.entries, {})
            self.assertEqual(central.notifications.paths, {})
            self.assertEqual(bus.sessions, set())
        self.assertEqual(bus.count("StartNotify"), 1000)
        self.assertEqual(bus.count("StopNotify"), 1000)


if __name__ == "__main__":
    unittest.main()
