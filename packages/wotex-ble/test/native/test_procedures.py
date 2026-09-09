"""Acknowledged procedure contract tests on an injected D-Bus boundary."""

import asyncio
import base64
import unittest

from test_bluez import Bus, OPTIONS, CHAR_PATH, DEVICE_PATH, objects
from client import Central, Failure, CHARACTERISTIC, DEVICE
from procedures import address, bytes_value, execute

TARGET = {"service": "180f", "characteristic": "2a19", "object_path": CHAR_PATH + "0", "handle": 1, "generation": 1}


def envelope(value):
    return {"type": "bytes", "base64": base64.b64encode(value).decode("ascii")}


class ProcedureBus(Bus):
    def __init__(self):
        super().__init__(objects())
        for item in self.data.values():
            if CHARACTERISTIC in item:
                item[CHARACTERISTIC]["Flags"] = ["read", "write"]
        self.value = b"\x2a\x00"
        self.error = None
        self.block = False
        self.malformed = False
        self.entered = asyncio.Event()

    @staticmethod
    def write_options():
        return {"type": "request", "offset": 0}

    async def call(self, destination, object_path, interface, member, signature, body):
        if member not in ("ReadValue", "WriteValue"):
            return await super().call(destination, object_path, interface, member, signature, body)
        self.calls.append((destination, object_path, interface, member, signature, body))
        self.entered.set()
        if member == "ReadValue":
            assert signature == "a{sv}" and body == [{}]
        else:
            assert signature == "aya{sv}" and body[1] == {"type": "request", "offset": 0}
            assert isinstance(body[0], bytes)
            self.value = body[0]
        if self.block:
            await asyncio.Event().wait()
        if self.error:
            raise self.error
        if self.malformed:
            return [True]
        return [self.value] if member == "ReadValue" else []


class ProcedureTest(unittest.IsolatedAsyncioTestCase):
    async def central(self):
        bus = ProcedureBus()
        central = Central(lambda _: None, lambda _: bus)
        self.addAsyncCleanup(central.close)
        await central.open(OPTIONS, 1000)
        events = []
        central.emit = events.append
        return central, bus, events

    async def test_WBL_P04_V05_exact_acknowledged_read_write_and_value_limit(self):
        central, bus, events = await self.central()
        self.assertEqual(await execute(central, "read", {"address": TARGET}, 1000, "r"), envelope(b"\x2a\x00"))
        for value in (b"", b"\x01", bytes(range(256)) * 2):
            self.assertIsNone(await execute(central, "write", {"address": TARGET, "value": envelope(value)}, 1000, "w"))
            self.assertEqual(await execute(central, "read", {"address": TARGET}, 1000, "r"), envelope(value))
        self.assertEqual(events, [{"version": 1, "id": "w", "event": "write_submitted"}] * 3)
        self.assertEqual(bus.count("WriteValue"), 3)
        self.assertTrue(all(call[0] == ":1.2" and call[1] == CHAR_PATH + "0" for call in bus.calls if len(call) == 6 and call[3] in ("ReadValue", "WriteValue")))

    async def test_WBL_C02_invalid_values_and_targets_never_call_gatt(self):
        central, bus, events = await self.central()
        for value in (None, {}, {"type": "bytes", "base64": "!"}, envelope(b"x" * 513), {"type": "bytes", "base64": "Zh=="}, {"type": "bytes", "base64": "Zg"}, {**envelope(b"a"), "extra": True}):
            with self.assertRaisesRegex(Failure, "invalid_value"):
                await execute(central, "write", {"address": TARGET, "value": value}, 1000, "w")
        self.assertEqual(bus.count("GetManagedObjects"), 1)
        for target, code in [({**TARGET, "service": "180a"}, "address_mismatch"), ({**TARGET, "handle": 2}, "address_mismatch"), ({**TARGET, "object_path": "/foreign"}, "address_mismatch"), ({**TARGET, "object_path": None, "handle": None}, "ambiguous_characteristic"), ({**TARGET, "generation": 0}, "stale_discovery")]:
            with self.assertRaisesRegex(Failure, code):
                await execute(central, "read", {"address": target}, 1000, "r")
        self.assertEqual(bus.count("ReadValue"), 0)
        self.assertEqual(bus.count("WriteValue"), 0)
        self.assertEqual(events, [])

    async def test_WBL_V05_flags_and_stale_generation_prevent_submission(self):
        central, bus, events = await self.central()
        bus.data[CHAR_PATH + "0"][CHARACTERISTIC]["Flags"] = ["write-without-response"]
        with self.assertRaisesRegex(Failure, "stale_discovery"):
            await execute(central, "write", {"address": TARGET, "value": envelope(b"x")}, 1000, "w")
        for operation in ("read", "write"):
            parameters = {"address": {**TARGET, "generation": None}}
            if operation == "write":
                parameters["value"] = envelope(b"x")
            with self.assertRaisesRegex(Failure, "not_permitted"):
                await execute(central, operation, parameters, 1000, "w")
        self.assertEqual(bus.count("WriteValue"), 0)
        self.assertEqual(bus.count("ReadValue"), 0)
        self.assertEqual(events, [])

    async def test_WBL_V05_errors_and_timeout_never_retry_a_partial_write(self):
        central, bus, events = await self.central()
        for code in ("not_permitted", "not_authorized", "not_supported", "busy", "invalid_offset", "invalid_value_length", "improperly_configured", "remote_error"):
            bus.error = Failure(code, "org.bluez.Error.Failed")
            count = bus.count("WriteValue")
            with self.assertRaisesRegex(Failure, code):
                await execute(central, "write", {"address": TARGET, "value": envelope(b"changed")}, 1000, "w")
            self.assertEqual(bus.count("WriteValue"), count + 1)
        bus.error = None
        bus.block = True
        with self.assertRaisesRegex(Failure, "timeout"):
            await execute(central, "write", {"address": TARGET, "value": envelope(b"partial")}, 10, "timeout")
        self.assertEqual(bus.value, b"partial")
        self.assertEqual(bus.count("WriteValue"), 9)
        self.assertEqual(events[-1]["id"], "timeout")

    async def test_WBL_C07_malformed_procedure_results_never_report_success(self):
        central, bus, _ = await self.central()
        bus.malformed = True
        for operation in ("read", "write"):
            parameters = {"address": TARGET}
            if operation == "write":
                parameters["value"] = envelope(b"x")
            with self.assertRaisesRegex(Failure, "invalid_response"):
                await execute(central, operation, parameters, 1000, "1")
        bus.malformed = False
        bus.value = b"x" * 513
        with self.assertRaisesRegex(Failure, "invalid_response"):
            await execute(central, "read", {"address": TARGET}, 1000, "r")

    async def test_WBL_S02_snapshot_disconnect_prevents_new_procedures(self):
        central, bus, _ = await self.central()
        bus.data[DEVICE_PATH][DEVICE]["Connected"] = False
        with self.assertRaisesRegex(Failure, "disconnected"):
            await execute(central, "read", {"address": TARGET}, 1000, "r")
        self.assertEqual(bus.count("ReadValue"), 0)


class ProcedureValuesTest(unittest.TestCase):
    def test_WBL_C02_forged_native_address_and_bytes_are_rejected(self):
        for target in (None, {}, {**TARGET, "extra": 1}, {**TARGET, "handle": True}, {**TARGET, "handle": 0}, {**TARGET, "object_path": "/bad path"}, {**TARGET, "generation": 2**64}, {**TARGET, "characteristic": "not-uuid"}):
            with self.assertRaises(Failure):
                address(target)
        for value in (False, {"type": "bytes", "base64": 1}, {"type": "bytes", "base64": "é"}, {"type": "bytes", "base64": "A" * 685}):
            with self.assertRaises(Failure):
                bytes_value(value)

    def test_WBL_C07_error_names_are_bounded_without_message_text(self):
        self.assertEqual(Failure("remote_error", "org.bluez.Error.FutureCase").envelope(), {"code": "remote_error", "name": "org.bluez.Error.FutureCase"})
        for name in (None, "org.foreign.Error.Name", "org.bluez.Error.", "org.bluez.Error.bad-name", "org.bluez.Error.123", "org.bluez.Error.X" * 20, "org.bluez.Error.é"):
            self.assertEqual(Failure("remote_error", name).envelope(), {"code": "remote_error"})


if __name__ == "__main__":
    unittest.main()
