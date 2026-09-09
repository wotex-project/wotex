"""Protocol-v1 owner for the packaged persistent BlueZ central."""

import asyncio
import json
import math
import os
import re
import sys
import time

from client import Central, Failure, REVISION, integer

MAX_LINE = 131072
OPERATIONS = {"open", "discover", "read", "write", "subscribe", "unsubscribe", "pair", "agent_reply", "health", "close"}


def object_pairs(pairs):
    result = {}
    if len(pairs) > 1024:
        raise Failure("invalid_frame")
    for key, value in pairs:
        if key in result:
            raise Failure("invalid_frame")
        result[key] = value
    return result


def validate_tree(value, depth=1, budget=None):
    if budget is None:
        budget = [4096]
    budget[0] -= 1
    if depth > 8 or budget[0] < 0:
        raise Failure("invalid_frame")
    if isinstance(value, float) and not math.isfinite(value):
        raise Failure("invalid_frame")
    if isinstance(value, (dict, list)):
        if len(value) > 1024:
            raise Failure("invalid_frame")
        if isinstance(value, dict):
            for key in value:
                key.encode("utf-8")
        for child in value.values() if isinstance(value, dict) else value:
            validate_tree(child, depth + 1, budget)
    elif isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeError:
            raise Failure("invalid_frame") from None


def decode(line):
    if not isinstance(line, bytes) or len(line) > MAX_LINE or not line.endswith(b"\n"):
        raise Failure("invalid_frame")
    try:
        value = json.loads(line.decode("utf-8"), object_pairs_hook=object_pairs)
    except (ValueError, UnicodeError, RecursionError):
        raise Failure("invalid_frame") from None
    try:
        validate_tree(value)
    except UnicodeError:
        raise Failure("invalid_frame") from None
    if not isinstance(value, dict) or set(value) != {"version", "id", "operation", "parameters", "timeout_ms"}:
        raise Failure("invalid_frame")
    if type(value["version"]) is not int or value["version"] != 1 or not isinstance(value["id"], str) or not 1 <= len(value["id"].encode("utf-8")) <= 64:
        raise Failure("invalid_frame")
    if not isinstance(value["operation"], str) or value["operation"] not in OPERATIONS or not isinstance(value["parameters"], dict) or not integer(value["timeout_ms"], 1, 60000):
        raise Failure("invalid_frame")
    return value


class Sequence:
    """Tracks only the greatest accepted uint64 dispatch ID and reserved open."""

    def __init__(self):
        self.last = 0
        self.open_seen = False

    def accept(self, request):
        identifier, operation = request["id"], request["operation"]
        if operation == "open":
            if identifier != "open" or self.open_seen or self.last:
                return False
            self.open_seen = True
            return True
        if operation == "close":
            return identifier == "close" and request["parameters"] == {}
        if not self.open_seen:
            return False
        prefix = "agent-" if operation == "agent_reply" else ""
        if not re.fullmatch(prefix + r"[1-9][0-9]{0,19}", identifier):
            return False
        number = int(identifier[len(prefix):])
        if number <= self.last or number > 2**64 - 1:
            return False
        self.last = number
        return True


class Bridge:
    """Serializes admitted requests while EOF independently cancels active work."""

    def __init__(self, emit, central_factory=Central):
        self.emit = emit
        self.stop = asyncio.Event()
        self.central = central_factory(self.terminal)
        self.central.emit = emit
        self.queue = asyncio.Queue(maxsize=64)
        self.sequence = Sequence()
        self.active = None
        self.opened = False
        self.close_request = None
        self.controls = set()

    def terminal(self, _code):
        self.stop.set()

    def response(self, request, **fields):
        self.emit({"version": 1, "id": request["id"], **fields})

    async def accept(self, reader):
        while not self.stop.is_set():
            try:
                line = await reader.readline()
                if not line:
                    return
                request = decode(line)
            except (ValueError, Failure):
                return
            if not self.sequence.accept(request):
                return
            if request["operation"] == "agent_reply":
                try:
                    self.central.agent_reply(request["parameters"])
                    self.response(request, ok=True, result=None)
                except Failure as error:
                    self.response(request, ok=False, error=error.envelope())
                continue
            if request["operation"] == "unsubscribe":
                if self.queue.qsize() + (self.active is not None) + len(self.controls) >= 64:
                    self.response(request, ok=False, error={"code": "busy"})
                else:
                    task = asyncio.create_task(self.control(request))
                    self.controls.add(task)
                    task.add_done_callback(self.control_done)
                continue
            if request["operation"] == "close" and request["parameters"] == {}:
                self.close_request = request
                return
            if self.queue.qsize() + (self.active is not None) + len(self.controls) >= 64:
                self.response(request, ok=False, error={"code": "busy"})
                continue
            self.queue.put_nowait((request, time.monotonic() + request["timeout_ms"] / 1000))

    def control_done(self, task):
        self.controls.discard(task)
        if not task.cancelled():
            task.exception()

    async def control(self, request):
        try:
            if not self.opened:
                raise Failure("disconnected")
            await self.central.notifications.unsubscribe(request["parameters"], request["timeout_ms"])
            self.response(request, ok=True, result=None)
        except Failure as error:
            self.response(request, ok=False, error=error.envelope())
        except Exception:
            self.response(request, ok=False, error={"code": "transport_error"})
            self.stop.set()
        finally:
            if self.central.closed:
                self.stop.set()

    async def execute(self, request, deadline):
        remaining = int((deadline - time.monotonic()) * 1000)
        if remaining < 1:
            raise Failure("timeout")
        operation = request["operation"]
        if operation == "open" and not self.opened:
            result = await self.central.open(request["parameters"], remaining)
            self.opened = True
            return result
        if not self.opened:
            raise Failure("disconnected")
        if operation == "subscribe":
            return await self.central.notifications.subscribe(request["parameters"], remaining, request["id"])
        if operation == "unsubscribe":
            return await self.central.notifications.unsubscribe(request["parameters"], remaining)
        if operation in ("read", "write"):
            from procedures import execute
            return await execute(self.central, operation, request["parameters"], remaining, request["id"])
        if operation == "pair":
            return await self.central.pair(request["parameters"], remaining, request["id"])
        if operation == "health":
            return await self.central.health(request["parameters"], remaining)
        if operation == "discover":
            return await self.central.discover(request["parameters"], remaining)
        if operation == "close" and request["parameters"] == {}:
            await self.central.close()
            self.stop.set()
            return None
        raise Failure("not_supported")

    async def work(self):
        while not self.stop.is_set():
            request, deadline = await self.queue.get()
            self.active = request
            try:
                result = await self.execute(request, deadline)
                self.response(request, ok=True, result=result)
                if request["operation"] == "subscribe":
                    self.central.notifications.activate(request["id"])
            except Failure as error:
                self.response(request, ok=False, error=error.envelope())
                if error.code in ("timeout", "disconnected", "owner_changed") or request["operation"] == "open":
                    self.stop.set()
            except Exception:
                self.response(request, ok=False, error={"code": "transport_error"})
                self.stop.set()
            finally:
                self.active = None
                if self.central.closed:
                    self.stop.set()

    async def run(self, reader):
        tasks = [asyncio.create_task(self.accept(reader)), asyncio.create_task(self.work()), asyncio.create_task(self.stop.wait())]
        try:
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        finally:
            self.stop.set()
            self.central.cleanup_deadline = self.central.cleanup_deadline or time.monotonic() + 0.8
            pending = tasks + list(self.controls)
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            await self.central.close()
            if self.close_request is not None:
                self.response(self.close_request, ok=True, result=None)


async def serve(emit):
    from importlib.metadata import version
    if version("dbus-next") != REVISION:
        raise Failure("incompatible_backend")
    reader = asyncio.StreamReader(limit=MAX_LINE)
    protocol = asyncio.StreamReaderProtocol(reader)
    transport, _ = await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin.buffer)
    try:
        emit({"version": 1, "event": "ready", "backend": "dbus-next", "revision": REVISION})
        await Bridge(emit).run(reader)
    finally:
        transport.close()


def main():
    # Only this duplicate can write protocol frames. SDK/stdout/stderr logs cannot.
    framed = os.fdopen(os.dup(sys.stdout.fileno()), "wb", buffering=0)
    with open(os.devnull, "wb") as sink:
        os.dup2(sink.fileno(), 1)
        os.dup2(sink.fileno(), 2)

    def emit(value):
        line = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8") + b"\n"
        if len(line) > MAX_LINE:
            raise Failure("response_limit")
        framed.write(line)

    try:
        asyncio.run(serve(emit))
        return 0
    except Exception:
        return 1
    finally:
        framed.close()


if __name__ == "__main__":
    sys.exit(main())
