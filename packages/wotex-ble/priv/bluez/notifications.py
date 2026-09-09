"""Same-sender BlueZ notification sessions with bounded establishment state."""

import asyncio
import base64
import time

from client import CHARACTERISTIC, DEVICE, PROPERTIES, SERVICE, Failure
from procedures import address, resolve


def mode(flags, requested):
    if requested not in ("auto", "notify", "indicate"):
        raise Failure("invalid_options")
    notify, indicate = "notify" in flags, "indicate" in flags
    if notify and indicate:
        if requested == "auto":
            return "bluez_selected"
        raise Failure("unsupported_procedure_selection")
    if notify and requested in ("auto", "notify"):
        return "notify"
    if indicate and requested in ("auto", "indicate"):
        return "indicate"
    raise Failure("not_supported")


class Notifications:
    def __init__(self, central):
        self.central = central
        self.entries = {}
        self.paths = {}
        self.background = set()

    async def subscribe(self, parameters, timeout_ms, identifier):
        if not isinstance(parameters, dict) or set(parameters) != {"address", "mode"} or parameters["mode"] not in ("auto", "notify", "indicate"):
            raise Failure("invalid_options")
        target = address(parameters["address"])
        if len(self.entries) >= 64:
            raise Failure("busy")
        deadline = time.monotonic() + timeout_ms / 1000
        characteristic = await resolve(self.central, target, deadline)
        effective = mode(characteristic["flags"], parameters["mode"])
        if characteristic["object_path"] in self.paths or identifier in self.entries:
            raise Failure("already_subscribed")
        entry = Notification(self, identifier, characteristic, parameters["mode"], effective)
        self.entries[identifier] = entry
        self.paths[characteristic["object_path"]] = identifier
        try:
            await entry.start(deadline)
            return entry.result()
        except BaseException:
            try:
                await entry.stop(self.central.cleanup_deadline or time.monotonic() + 0.4)
            except Exception:
                await self.central.close()
            raise

    def activate(self, identifier):
        entry = self.entries.get(identifier)
        if entry is not None:
            entry.activate()

    async def unsubscribe(self, parameters, timeout_ms):
        if not isinstance(parameters, dict) or set(parameters) != {"subscription_id"} or not isinstance(parameters["subscription_id"], str):
            raise Failure("invalid_options")
        entry = self.entries.get(parameters["subscription_id"])
        if entry is None:
            raise Failure("invalid_subscription")
        deadline = time.monotonic() + timeout_ms / 1000
        try:
            await entry.stop(deadline)
        except Exception:
            self.central.cleanup_deadline = min(self.central.cleanup_deadline or deadline, deadline)
            await self.central.close()
            raise

    def signal(self, sender, object_path, interface, member, body):
        if sender != self.central.bluez_owner or interface != PROPERTIES or member != "PropertiesChanged":
            return
        if not isinstance(body, list) or len(body) != 3 or not isinstance(body[0], str) or not isinstance(body[1], dict) or not isinstance(body[2], list) or any(not isinstance(key, str) for key in [*body[1], *body[2]]):
            return  # Central independently rejects malformed owned signals.
        changed = set(body[1]) | set(body[2])
        for entry in list(self.entries.values()):
            if object_path == entry.characteristic["object_path"] and body[0] == CHARACTERISTIC:
                if changed & {"UUID", "Service", "Handle", "Flags"}:
                    entry.fail("stale_discovery")
                elif "Notifying" in body[1] and type(getattr(body[1]["Notifying"], "value", body[1]["Notifying"])) is not bool:
                    entry.fail("invalid_response")
                elif "Notifying" in body[2] or getattr(body[1].get("Notifying"), "value", body[1].get("Notifying")) is False:
                    entry.fail("subscription_lost")
                elif "Value" in body[2]:
                    entry.fail("invalid_response")
                elif "Value" in body[1]:
                    entry.value(getattr(body[1]["Value"], "value", body[1]["Value"]))
            elif object_path == entry.characteristic["service_path"] and body[0] == SERVICE and changed & {"UUID", "Device"}:
                entry.fail("stale_discovery")
            elif object_path == self.central.device_path and body[0] == DEVICE and changed & {"Adapter", "Address", "AddressType"}:
                entry.fail("peer_changed")

    def fail_all(self, code):
        for entry in list(self.entries.values()):
            entry.fail(code)

    def retire(self, entry):
        self.entries.pop(entry.identifier, None)
        self.paths.pop(entry.characteristic["object_path"], None)

    def finish_later(self, entry):
        task = asyncio.create_task(self.finish(entry))
        self.background.add(task)
        task.add_done_callback(self.finished)

    def finished(self, task):
        self.background.discard(task)
        if not task.cancelled():
            task.exception()

    async def finish(self, entry):
        try:
            await entry.stop(self.central.cleanup_deadline or time.monotonic() + 0.8)
        except Exception:
            await self.central.close()

    async def close(self, deadline):
        entries = list(self.entries.values())
        for entry in entries:
            entry.fail("disconnected", cleanup=False)
        await asyncio.gather(*(entry.stop(deadline) for entry in entries), return_exceptions=True)
        other = [task for task in self.background if task is not asyncio.current_task()]
        await asyncio.gather(*other, return_exceptions=True)


class Notification:
    def __init__(self, manager, identifier, characteristic, requested, effective):
        self.manager = manager
        self.central = manager.central
        self.identifier = identifier
        self.characteristic = characteristic
        self.requested = requested
        self.effective = effective
        self.status = "starting"
        self.early = None
        self.failure = asyncio.get_running_loop().create_future()
        self.attempted = False
        self.call_task = None
        self.stop_task = None

    async def start(self, deadline):
        self.attempted = True
        self.call_task = asyncio.create_task(self.central.call(self.characteristic["object_path"], CHARACTERISTIC, "StartNotify", deadline))
        done, _ = await self.central.bounded(asyncio.wait([self.call_task, self.failure], return_when=asyncio.FIRST_COMPLETED), deadline)
        if self.failure in done:
            raise self.failure.result()
        try:
            result = await self.call_task
        except Failure as error:
            if error.code not in ("timeout", "disconnected", "owner_changed", "invalid_response"):
                self.attempted = False
            raise
        if result != []:
            raise Failure("invalid_response")
        self.status = "established"

    def result(self):
        return {"subscription_id": self.identifier, "generation": 1, "characteristic": self.characteristic,
                "requested_mode": self.requested, "effective_mode": self.effective}

    def metadata(self):
        return {"source": "bluez_value_change", "characteristic": self.characteristic,
                "requested_mode": self.requested, "effective_mode": self.effective}

    def report(self, event, value, metadata):
        self.central.emit({"version": 1, "subscription_id": self.identifier, "generation": 1,
                           "event": event, "value": value, "metadata": metadata})

    def activate(self):
        if self.status != "established":
            return
        self.status = "active"
        if self.early is not None:
            value, self.early = self.early, None
            self.value(value)

    def value(self, value):
        if self.status not in ("starting", "established", "active"):
            return
        if not isinstance(value, bytes) or len(value) > 512:
            self.fail("invalid_response")
        elif self.status == "active":
            self.report("value", {"type": "bytes", "base64": base64.b64encode(value).decode("ascii")}, self.metadata())
        elif self.early is None:
            self.early = value
        else:
            self.fail("response_limit")

    def fail(self, code, cleanup=True):
        if self.status not in ("starting", "established", "active"):
            return
        active = self.status == "active"
        self.status = "failed"
        self.early = None
        if not self.failure.done():
            self.failure.set_result(Failure(code))
        if active:
            self.report("error", None, {"error": {"code": code}})
            if cleanup:
                self.manager.finish_later(self)

    async def stop(self, deadline):
        if self.stop_task is None:
            self.status = "closing"
            self.early = None
            self.stop_task = asyncio.create_task(self.release(deadline))
        remaining = max(deadline - time.monotonic(), 0.001)
        try:
            await asyncio.wait_for(asyncio.shield(self.stop_task), remaining)
        except asyncio.TimeoutError:
            self.stop_task.cancel()
            await asyncio.gather(self.stop_task, return_exceptions=True)
            raise Failure("cleanup_timeout") from None

    async def release(self, deadline):
        try:
            if self.call_task is not None:
                if not self.call_task.done():
                    self.call_task.cancel()
                await asyncio.gather(self.call_task, return_exceptions=True)
            if self.attempted:
                result = await asyncio.wait_for(self.central.bus.call(self.central.bluez_owner, self.characteristic["object_path"], CHARACTERISTIC, "StopNotify", "", []), max(deadline - time.monotonic(), 0.001))
                if result != []:
                    raise Failure("invalid_response")
        finally:
            self.attempted = False
            self.status = "closed"
            self.manager.retire(self)
