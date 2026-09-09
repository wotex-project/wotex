"""One explicit same-sender BlueZ Agent1 registration and pairing attempt."""

import asyncio
import secrets
import time

from client import Failure, DEVICE, canonical_uuid, integer

AGENT = "org.bluez.Agent1"
MANAGER = "org.bluez.AgentManager1"
CAPABILITIES = {"NoInputNoOutput", "DisplayYesNo", "KeyboardOnly"}
METHODS = {
    "RequestPinCode": ("o", "request_pin"),
    "DisplayPinCode": ("os", "display_pin"),
    "RequestPasskey": ("o", "request_passkey"),
    "DisplayPasskey": ("ouq", "display_passkey"),
    "RequestConfirmation": ("ou", "confirm_passkey"),
    "RequestAuthorization": ("o", "authorize_pairing"),
    "AuthorizeService": ("os", "authorize_service"),
}


def pin(value):
    return isinstance(value, str) and 1 <= len(value) <= 16 and all(32 <= ord(char) <= 126 for char in value)


def prompt(member, signature, body, device_path):
    if not isinstance(member, str) or member not in METHODS or signature != METHODS[member][0] or not isinstance(body, list) or not body or body[0] != device_path:
        raise Failure("pairing_rejected")
    kind = METHODS[member][1]
    if kind in ("request_pin", "request_passkey", "authorize_pairing") and len(body) == 1:
        return kind, None
    if kind == "confirm_passkey" and len(body) == 2 and integer(body[1], 0, 999999):
        return kind, body[1]
    if kind == "display_pin" and len(body) == 2 and pin(body[1]):
        return kind, body[1]
    if kind == "display_passkey" and len(body) == 3 and integer(body[1], 0, 999999) and integer(body[2], 0, 6):
        return kind, {"passkey": body[1], "entered": body[2]}
    if kind == "authorize_service" and len(body) == 2:
        return kind, canonical_uuid(body[1])
    raise Failure("pairing_rejected")


def decision(kind, value):
    if not isinstance(value, dict):
        raise Failure("pairing_rejected")
    if value == {"action": "reject"}:
        return None
    if value == {"action": "accept"} and kind in ("confirm_passkey", "authorize_pairing", "authorize_service", "display_pin", "display_passkey"):
        return "", []
    if set(value) == {"action", "value"}:
        if kind == "request_passkey" and value["action"] == "passkey" and integer(value["value"], 0, 999999):
            return "u", [value["value"]]
        if kind == "request_pin" and value["action"] == "pin" and pin(value["value"]):
            return "s", [value["value"]]
    raise Failure("pairing_rejected")


class PairingAgent:
    def __init__(self, central, request_id, timeout_ms):
        self.central = central
        self.request_id = request_id
        self.deadline = time.monotonic() + timeout_ms / 1000
        self.object_path = "/org/wotex/ble/agent_" + secrets.token_hex(16)
        self.pending = None
        self.registered = False
        self.listening = False
        self.attempted = False
        self.closed = False
        self.failure = asyncio.get_running_loop().create_future()
        self.call_task = None
        self.must_close_sender = False
        self.completed = False

    def abort(self, code="pairing_rejected"):
        if not self.failure.done():
            self.failure.set_result(code)
        if self.pending is not None:
            pending, self.pending = self.pending, None
            self.respond(pending["respond"], "", [], "org.bluez.Error.Rejected")

    def respond(self, callback, signature, body, error):
        try:
            result = callback(signature, body, error)
            if isinstance(result, asyncio.Future):
                result.add_done_callback(self.sent)
        except Exception:
            self.must_close_sender = True
            if not self.failure.done():
                self.failure.set_result("disconnected")

    def sent(self, future):
        if future.cancelled() or future.exception() is not None:
            self.must_close_sender = True
            self.abort("disconnected")

    def receive(self, sender, object_path, interface, member, signature, body, respond):
        if object_path != self.object_path or interface != AGENT:
            return None
        if self.closed or sender != self.central.bluez_owner:
            self.respond(respond, "", [], "org.bluez.Error.Rejected")
            return True
        if member in ("Cancel", "Release") and signature == "" and body == []:
            if member == "Release":
                self.registered = False
            self.abort()
            self.respond(respond, "", [], None)
            return True
        try:
            kind, value = prompt(member, signature, body, self.central.device_path)
            remaining = int((self.deadline - time.monotonic()) * 1000)
            if self.pending is not None or self.failure.done() or remaining <= 0:
                raise Failure("pairing_rejected")
            identifier = secrets.token_hex(16)
            self.pending = {"id": identifier, "kind": kind, "respond": respond}
            self.central.emit({"version": 1, "id": self.request_id, "event": "agent_challenge", "challenge": {"id": identifier, "peer": self.central.peer, "kind": kind, "value": value, "timeout_ms": remaining}})
        except Exception:
            if self.pending is None or self.pending["respond"] is not respond:
                self.respond(respond, "", [], "org.bluez.Error.Rejected")
            self.abort()
        return True

    def reply(self, parameters):
        if not isinstance(parameters, dict) or set(parameters) != {"challenge_id", "decision"} or self.pending is None or self.pending["id"] != parameters["challenge_id"] or time.monotonic() >= self.deadline:
            self.abort()
            raise Failure("pairing_rejected")
        pending, self.pending = self.pending, None
        try:
            result = decision(pending["kind"], parameters["decision"])
        except Failure:
            result = None
        if result is None:
            self.respond(pending["respond"], "", [], "org.bluez.Error.Rejected")
            self.abort()
        else:
            signature, body = result
            self.respond(pending["respond"], signature, body, None)

    async def pair(self, parameters):
        if not isinstance(parameters, dict) or set(parameters) != {"capability"} or not isinstance(parameters["capability"], str) or parameters["capability"] not in CAPABILITIES:
            raise Failure("invalid_options")
        try:
            self.central.bus.listen_calls(self.receive)
            self.listening = True
            # This registration belongs to our newly minted path and bus sender,
            # including when its acknowledgement is lost.
            self.registered = True
            await self.central.call("/org/bluez", MANAGER, "RegisterAgent", self.deadline, "os", [self.object_path, parameters["capability"]])
            self.attempted = True
            self.call_task = asyncio.create_task(self.central.call(self.central.device_path, DEVICE, "Pair", self.deadline))
            completed, _ = await self.central.bounded(asyncio.wait([self.call_task, self.failure], return_when=asyncio.FIRST_COMPLETED), self.deadline)
            if self.failure in completed:
                raise Failure(self.failure.result())
            try:
                await self.call_task
            except Failure as error:
                if error.code not in ("timeout", "disconnected", "owner_changed"):
                    self.attempted = False
                raise
            self.attempted = False
            if self.pending is not None:
                raise Failure("pairing_rejected")
            self.completed = True
            return {"paired": True}
        except Failure as error:
            if error.code == "timeout":
                raise Failure("pairing_rejected") from None
            raise
        finally:
            await self.close()
            if self.must_close_sender and not self.central.closed:
                await self.central.close()
                if self.completed:
                    raise Failure("disconnected")

    async def cleanup_call(self, member, deadline, path=None, interface=None, signature="", body=None):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        try:
            await asyncio.wait_for(self.central.bus.call(self.central.bluez_owner, path or self.central.device_path, interface or DEVICE, member, signature, body or []), remaining)
            return True
        except Exception:
            return False

    async def close(self, deadline=None):
        if self.closed:
            return
        self.closed = True
        self.abort()
        if self.call_task is not None:
            was_done = self.call_task.done()
            if not was_done:
                self.call_task.cancel()
            results = await asyncio.gather(self.call_task, return_exceptions=True)
            if was_done and not (isinstance(results[0], Failure) and results[0].code in ("timeout", "disconnected", "owner_changed")):
                self.attempted = False
        deadline = deadline or self.central.cleanup_deadline or time.monotonic() + 0.4
        try:
            # BlueZ CancelPairing can unpair a device when the request has already
            # completed. Closing our unique sender instead releases only the
            # request whose sender BlueZ watches; never call CancelPairing.
            self.must_close_sender = self.must_close_sender or self.attempted
            if self.registered:
                unregistered = await self.cleanup_call("UnregisterAgent", deadline, "/org/bluez", MANAGER, "o", [self.object_path])
                self.must_close_sender = self.must_close_sender or not unregistered
        finally:
            if self.listening:
                self.central.bus.unlisten(self.receive)
            self.listening = False
            self.registered = False
            self.attempted = False
