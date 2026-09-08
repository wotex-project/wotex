"""Bounded Matter SDK v1.6.0.0 interactions through an explicit controller factory."""
import asyncio
import base64
import dataclasses
import importlib
import json
import logging
import math
import os
import sys

LIMIT = 131072
logging.disable(logging.CRITICAL)


def json_value(value, null_value, depth=0):
    if depth > 8:
        raise ValueError("value_depth")
    if value is null_value or value is None:
        return None
    if isinstance(value, bytes):
        return {"type": "bytes", "base64": base64.b64encode(value).decode("ascii")}
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("non_finite_value")
    if isinstance(value, (str, int, float, bool)):
        return value
    if dataclasses.is_dataclass(value):
        value = {field.name: getattr(value, field.name) for field in dataclasses.fields(value)}
    if isinstance(value, list) and len(value) <= 1024:
        return [json_value(item, null_value, depth+1) for item in value]
    if isinstance(value, dict) and len(value) <= 1024 and all(isinstance(key, str) for key in value):
        return {key: json_value(item, null_value, depth+1) for key, item in value.items()}
    raise ValueError("unsupported_value")


def input_value(value, null_value, depth=0):
    if depth > 8:
        raise ValueError("input_depth")
    if value is None:
        return null_value
    if isinstance(value, dict) and set(value) == {"type", "base64"} and value["type"] == "bytes":
        return base64.b64decode(value["base64"], validate=True)
    if isinstance(value, list) and len(value) <= 1024:
        return [input_value(item, null_value, depth+1) for item in value]
    if isinstance(value, dict) and len(value) <= 1024:
        return {key: input_value(item, null_value, depth+1) for key, item in value.items()}
    if isinstance(value, (str, int, bool)) or isinstance(value, float) and math.isfinite(value):
        return value
    raise ValueError("unsupported_input")


async def perform(controller, objects, null_value, message, timeout_ms, failure_type=()):
    if controller.fabricId != message["fabric_id"]:
        raise ValueError("fabric_mismatch")
    node, endpoint = message["node_id"], message["endpoint"]
    cluster_id, member = message["cluster"], message["member"]
    timed = message.get("timed_request_timeout_ms")
    if timed is not None and (type(timed) is not int or not 1 <= timed <= min(timeout_ms, 65535)):
        raise ValueError("invalid_timed_timeout")
    operation = message["type"]
    if operation == "read" and timed is not None:
        raise ValueError("timed_read_not_supported")
    if operation in ["read", "write"]:
        descriptor = objects.ALL_ATTRIBUTES[cluster_id][member]
        if operation == "read":
            response = await controller.ReadAttribute(node, [(endpoint, descriptor)],
                fabricFiltered=True, keepSubscriptions=True, autoResubscribe=False)
            cluster = objects.ALL_CLUSTERS[cluster_id]
            value = response[endpoint][cluster][descriptor]
            if isinstance(value, failure_type):
                raise ValueError("attribute_status_failed")
            return json_value(value, null_value)
        value = input_value(message["value"], null_value)
        response = await controller.WriteAttribute(node, [(endpoint, descriptor(value))],
            timedRequestTimeoutMs=timed, interactionTimeoutMs=timeout_ms)
        if len(response) != 1:
            raise ValueError("missing_path_status")
        status = response[0]
        path = status.Path
        if ((path.EndpointId, path.ClusterId, path.AttributeId) != (endpoint, cluster_id, member)
                or int(status.Status) != 0):
            raise ValueError("write_status_failed")
        return "written"
    if operation == "invoke":
        descriptor = objects.ALL_ACCEPTED_COMMANDS[cluster_id][member]
        if not isinstance(message["value"], dict):
            raise ValueError("command_fields_required")
        payload = descriptor.FromDict(input_value(message["value"], null_value))
        response = await controller.SendCommand(node, endpoint, payload,
            timedRequestTimeoutMs=timed, interactionTimeoutMs=timeout_ms, suppressResponse=False)
        return json_value(response, null_value)
    raise ValueError("unsupported_operation")


async def exchange(request):
    # The factory owns SDK startup, fabric credentials, policy and orderly shutdown.
    # No implicit factory, test commissioner, attestation bypass or fabric creation exists here.
    from matter.clusters import Objects  # noqa: F401 - registers generated descriptors
    from matter.clusters import ClusterObjects
    from matter.clusters.Types import NullValue
    from matter.clusters.Attribute import ValueDecodeFailure
    module, name = request["config"]["factory"].split(":")
    factory = getattr(importlib.import_module(module), name)
    with factory(request["config"]["settings"]) as controller:
        return await perform(controller, ClusterObjects, NullValue, request["message"], request["timeout_ms"], ValueDecodeFailure)


async def owned_exchange(request):
    loop = asyncio.get_running_loop()
    task = asyncio.create_task(exchange(request))
    def owner_closed():
        os.read(sys.stdin.fileno(), 1)
        task.cancel()
    loop.add_reader(sys.stdin.fileno(), owner_closed)
    try:
        return await asyncio.wait_for(task, request["timeout_ms"] / 1000)
    finally:
        loop.remove_reader(sys.stdin.fileno())


def main():
    response_fd = os.dup(sys.stdout.fileno())
    with open(os.devnull, "wb") as sink:
        os.dup2(sink.fileno(), sys.stdout.fileno())
        os.dup2(sink.fileno(), sys.stderr.fileno())
    request = None
    try:
        line = sys.stdin.buffer.readline(LIMIT + 1)
        if len(line) > LIMIT or not line.endswith(b"\n"):
            raise ValueError("request_limit")
        request = json.loads(line)
        if type(request["timeout_ms"]) is not int or not 0 < request["timeout_ms"] <= 60000:
            raise ValueError("timeout_limit")
        if request["config"]["fabric_id"] != request["message"]["fabric_id"]:
            raise ValueError("fabric_mismatch")
        response = {"id": request["id"], "ok": asyncio.run(owned_exchange(request))}
        output = json.dumps(response, allow_nan=False, separators=(",", ":"))
        if len(output.encode()) >= LIMIT:
            raise ValueError("response_limit")
    except Exception:
        output = json.dumps({"id": request.get("id") if isinstance(request, dict) else None,
                             "error": "exchange_failed"})
    os.write(response_fd, (output + "\n").encode())
    os.close(response_fd)


if __name__ == "__main__":
    main()
