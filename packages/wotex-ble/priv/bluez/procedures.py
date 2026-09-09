"""Exact GATT selection and acknowledged procedures; no write command fallback."""

import base64
import binascii
import time

from client import CHARACTERISTIC, Failure, canonical_uuid, integer, path


def bytes_value(value):
    if not isinstance(value, dict) or set(value) != {"type", "base64"} or value["type"] != "bytes" or not isinstance(value["base64"], str) or len(value["base64"]) > 684:
        raise Failure("invalid_value")
    try:
        result = base64.b64decode(value["base64"], validate=True)
    except (binascii.Error, ValueError):
        raise Failure("invalid_value") from None
    if len(result) > 512 or base64.b64encode(result).decode("ascii") != value["base64"]:
        raise Failure("invalid_value")
    return result


def address(value):
    if not isinstance(value, dict) or set(value) != {"service", "characteristic", "object_path", "handle", "generation"}:
        raise Failure("invalid_address")
    result = dict(value, service=canonical_uuid(value["service"]), characteristic=canonical_uuid(value["characteristic"]))
    if value["object_path"] is not None and not path(value["object_path"]):
        raise Failure("invalid_address")
    if value["handle"] is not None and not integer(value["handle"], 1, 65535):
        raise Failure("invalid_address")
    if value["generation"] is not None and not integer(value["generation"], 0, 2**64 - 1):
        raise Failure("invalid_address")
    return result


async def resolve(central, target, deadline):
    if not central.ready or central.closed or central.terminal:
        raise Failure(central.terminal or "disconnected")
    await central.refresh(deadline)
    if target["generation"] is not None and target["generation"] != central.generation:
        raise Failure("stale_discovery")
    matches = [item for item in central.characteristics
               if item["service_uuid"] == target["service"] and item["characteristic_uuid"] == target["characteristic"]
               and (target["object_path"] is None or item["object_path"] == target["object_path"])
               and (target["handle"] is None or item["handle"] == target["handle"])]
    if len(matches) != 1:
        raise Failure("ambiguous_characteristic" if matches else "address_mismatch")
    return matches[0]


async def execute(central, operation, parameters, timeout_ms, request_id):
    required = {"address", "value"} if operation == "write" else {"address"}
    if operation not in ("read", "write") or not isinstance(parameters, dict) or set(parameters) != required:
        raise Failure("invalid_options")
    target = address(parameters["address"])
    value = bytes_value(parameters["value"]) if operation == "write" else None
    deadline = time.monotonic() + timeout_ms / 1000
    item = await resolve(central, target, deadline)
    if operation not in item["flags"]:
        raise Failure("not_permitted")
    if operation == "read":
        response = await central.call(item["object_path"], CHARACTERISTIC, "ReadValue", deadline, "a{sv}", [{}])
        if not isinstance(response, list) or len(response) != 1 or not isinstance(response[0], bytes) or len(response[0]) > 512:
            raise Failure("invalid_response")
        return {"type": "bytes", "base64": base64.b64encode(response[0]).decode("ascii")}
    if time.monotonic() >= deadline:
        raise Failure("timeout")
    # The event is ordered before WriteValue on the dedicated output channel.
    # It proves submission phase, never a peripheral/application effect.
    options = central.bus.write_options()
    central.emit({"version": 1, "id": request_id, "event": "write_submitted"})
    response = await central.call(item["object_path"], CHARACTERISTIC, "WriteValue", deadline, "aya{sv}", [value, options])
    if response != []:
        raise Failure("invalid_response")
    return None
