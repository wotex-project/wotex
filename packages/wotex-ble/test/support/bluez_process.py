"""Actual process fixture with an injected D-Bus peer, never interoperability proof."""
import asyncio
import json
import pathlib
import os
import signal
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "priv" / "bluez"))
sys.path.insert(0, str(ROOT / "test" / "native"))
import bridge
import client
from test_bluez import Bus, objects
from test_agent import AgentBus
from test_procedures import ProcedureBus
from test_notifications import NotificationBus

MODE, RECORD = sys.argv[1:]


def record(value):
    with open(RECORD, "a", encoding="utf-8") as file:
        file.write(json.dumps(value) + "\n")


def emit(value):
    if isinstance(value.get("result"), dict) and "subscription_id" in value["result"]:
        if MODE == "stream_wrong_binding":
            value = {**value, "result": {**value["result"], "subscription_id": "foreign"}}
    if value.get("id") == "2" and value.get("ok") is True and value.get("result") is None:
        if MODE == "stream_lost_stop_ack":
            return
        if MODE == "stream_bad_stop_ack":
            value = {**value, "result": True}
    if value.get("event") == "value":
        if MODE == "stream_wrong_generation":
            value = {**value, "generation": 2}
        if MODE == "stream_wrong_metadata":
            value = {**value, "metadata": {**value["metadata"], "effective_mode": "indicate"}}
        if MODE == "stream_extra_report":
            value = {**value, "extra": True}
        if MODE == "stream_unknown_report":
            print(json.dumps({**value, "subscription_id": "unknown"}), flush=True)
    if MODE == "procedure_missing_event" and value.get("event") == "write_submitted":
        return
    if MODE == "procedure_wrong_event" and value.get("event") == "write_submitted":
        value = {**value, "id": "foreign"}
    if MODE == "procedure_extra_event" and value.get("event") == "write_submitted":
        value = {**value, "extra": True}
    if MODE == "procedure_read_event" and value.get("ok") is True and isinstance(value.get("result"), dict) and value["result"].get("type") == "bytes":
        print(json.dumps({"version": 1, "id": value["id"], "event": "write_submitted"}), flush=True)
    print(json.dumps(value), flush=True)
    if MODE == "procedure_duplicate_event" and value.get("event") == "write_submitted":
        print(json.dumps(value), flush=True)


class RecordedBus(Bus):
    async def call(self, *args):
        record({"method": args[3], "sender": self.unique_name})
        if args[3] == "GetManagedObjects" and self.count("GetManagedObjects") >= 1:
            if MODE in ("blocked", "slow"):
                await asyncio.sleep(60 if MODE == "blocked" else 0.05)
            if MODE == "remote_error":
                raise client.Failure("not_permitted")
            if MODE == "timeout_error":
                raise client.Failure("timeout")
            if MODE == "invalid_frame":
                print('{"version":1,"version":1}', flush=True)
                await asyncio.sleep(60)
            if MODE == "wrong_id":
                emit({"version": 1, "id": "foreign", "ok": True, "result": None})
                await asyncio.sleep(60)
        return await super().call(*args)

    def disconnect(self):
        if MODE == "close_slow":
            time.sleep(0.05)
        record({"bus_closed": True, "listeners": len(self.handlers)})
        super().disconnect()


class RecordedAgentBus(AgentBus):
    async def call(self, *args):
        record({"method": args[3], "sender": self.unique_name})
        return await super().call(*args)

    def disconnect(self):
        super().disconnect()
        record({"bus_closed": True, "agents": int(self.registered is not None), "listeners": len(self.handlers) + len(self.methods), "bonds": len(self.bonds)})


class RecordedProcedureBus(ProcedureBus):
    async def call(self, *args):
        record({"method": args[3], "sender": self.unique_name})
        if MODE == "procedure_slow" and args[3] == "WriteValue":
            await asyncio.sleep(0.05)
        if MODE == "procedure_crash_before_event" and args[3] == "GetManagedObjects" and self.count("GetManagedObjects") >= 1:
            os._exit(0)
        return await super().call(*args)

    def disconnect(self):
        super().disconnect()
        record({"bus_closed": True, "listeners": len(self.handlers)})


class RecordedNotificationBus(NotificationBus):
    async def call(self, *args):
        record({"method": args[3], "sender": self.unique_name})
        if args[3] == "StopNotify" and MODE == "stream_slow_stop":
            await asyncio.sleep(0.05)
        if args[3] == "ReadValue" and not self.read_blocked:
            self.value(b"\x34\x12")
            self.value(b"\x34\x12")
            return [b"\x34\x12"]
        result = await super().call(*args)
        if args[3] == "StopNotify":
            record({"sessions": len(self.sessions)})
        return result

    def disconnect(self):
        super().disconnect()
        record({"bus_closed": True, "listeners": len(self.handlers), "sessions": len(self.sessions)})


async def main():
    ready = {"version": 1, "event": "ready", "backend": "dbus-next", "revision": "0.2.3"}
    if MODE == "wrong_ready":
        ready["revision"] = "0.0.0"
    if MODE == "silent":
        await asyncio.sleep(60)
        return
    if MODE == "oversize":
        print("x" * 131073, flush=True)
        await asyncio.sleep(60)
        return
    if MODE == "truncated":
        sys.stdout.write('{"version":1'); sys.stdout.flush()
        return
    emit(ready)
    if MODE == "uncooperative":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        first = json.loads(sys.stdin.readline())
        emit({"version": 1, "id": first["id"], "ok": True, "result": {"generation": 1, "device_path": "/device", "link_owned": False, "sender": ":1.2"}})
        while True:
            time.sleep(1)
    reader = asyncio.StreamReader(limit=bridge.MAX_LINE)
    protocol = asyncio.StreamReaderProtocol(reader)
    transport, _ = await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin.buffer)
    bus = RecordedNotificationBus(count=65 if MODE == "stream_capacity" else 2) if MODE.startswith("stream") else RecordedAgentBus() if MODE.startswith("pair") else RecordedProcedureBus() if MODE.startswith("procedure") else RecordedBus(objects())
    if MODE.startswith("stream"):
        bus.early = [b"\x01\x00"]
        if MODE == "stream_canary":
            bus.early = [b"PRIVATE_STREAM_VALUE"]
        if MODE == "stream_early_overflow":
            bus.early *= 2
        if MODE in ("stream_blocked_read", "stream_blocked_stop"):
            bus.read_blocked = True
        if MODE == "stream_blocked_stop":
            bus.stop_blocked = True
        if MODE == "stream_stop_error":
            bus.stop_error = client.Failure("remote_error", "org.bluez.Error.Failed")
        if MODE == "stream_pending_start":
            bus.start_blocked = True
        if MODE == "stream_indicate":
            for item in bus.data.values():
                if client.CHARACTERISTIC in item:
                    item[client.CHARACTERISTIC]["Flags"] = ["read", "indicate"]
    if MODE == "procedure_timeout":
        bus.block = True
    if MODE == "procedure_malformed":
        bus.malformed = True
    if MODE.startswith("procedure_error_"):
        name = "org.bluez.Error." + MODE.removeprefix("procedure_error_")
        bus.error = client.Failure(client.ERRORS.get(name, "remote_error"), name)
    if MODE == "procedure_command_only":
        bus.data["/another/characteristic0"][client.CHARACTERISTIC]["Flags"] = ["write-without-response"]
    if MODE == "pair_pin":
        bus.prompts = [("RequestPinCode", "o", ["/unrelated/device"])]
    if MODE == "pair_passkey":
        bus.prompts = [("RequestPasskey", "o", ["/unrelated/device"])]
    if MODE == "startup_error":
        bus.data = objects(False, False)
    owner = bridge.Bridge(emit, lambda signal: client.Central(signal, lambda _: bus))
    if MODE.startswith("stream"):
        bus.owner = owner.central
    try:
        await owner.run(reader)
    finally:
        transport.close()
        record({"bridge_closed": True})


record({"pid": os.getpid()})
asyncio.run(main())
