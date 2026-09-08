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

MODE, RECORD = sys.argv[1:]


def record(value):
    with open(RECORD, "a", encoding="utf-8") as file:
        file.write(json.dumps(value) + "\n")


def emit(value):
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
        record({"bus_closed": True, "listeners": len(self.handlers)})
        super().disconnect()


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
    bus = RecordedBus(objects())
    if MODE == "startup_error":
        bus.data = objects(False, False)
    owner = bridge.Bridge(emit, lambda signal: client.Central(signal, lambda _: bus))
    try:
        await owner.run(reader)
    finally:
        transport.close()
        record({"bridge_closed": True})


record({"pid": os.getpid()})
asyncio.run(main())
