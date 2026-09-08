import asyncio
import importlib.util
import pathlib
import subprocess
import sys
import json
import types
import unittest

spec = importlib.util.spec_from_file_location("bridge", pathlib.Path(__file__).parents[2] / "priv/matter_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class Attribute:
    def __init__(self, value):
        self.value = value


class Command:
    @classmethod
    def FromDict(cls, value):
        return value


class Failure:
    pass


class Controller:
    fabricId = 1
    def __init__(self):
        self.value = False
        self.status = 0
        self.endpoint = 2
        self.responses = 1
        self.calls = []

    async def ReadAttribute(self, node, paths, **options):
        self.calls.append((node, paths, options))
        return {2: {"cluster": {Attribute: self.value}}}

    async def WriteAttribute(self, node, paths, **options):
        self.calls.append((node, paths, options))
        path = types.SimpleNamespace(EndpointId=self.endpoint, ClusterId=6, AttributeId=0)
        return [types.SimpleNamespace(Path=path, Status=self.status)] * self.responses

    async def SendCommand(self, node, endpoint, payload, **options):
        self.calls.append((node, endpoint, payload, options))
        return {"accepted": True}


class BridgeTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.controller = Controller()
        self.objects = types.SimpleNamespace(ALL_CLUSTERS={6: "cluster"},
            ALL_ATTRIBUTES={6: {0: Attribute}}, ALL_ACCEPTED_COMMANDS={6: {0: Command}})
        self.null = object()
        self.message = dict(type="read", fabric_id=1, node_id=3, endpoint=2, cluster=6, member=0)

    async def perform(self, **changes):
        return await bridge.perform(self.controller, self.objects, self.null, dict(self.message, **changes), 1000, Failure)

    async def test_read_false_is_a_value_and_identity_is_exact(self):
        self.assertIs(await self.perform(), False)
        self.assertTrue(self.controller.calls[-1][2]["fabricFiltered"])
        self.assertTrue(self.controller.calls[-1][2]["keepSubscriptions"])
        self.assertFalse(self.controller.calls[-1][2]["autoResubscribe"])
        self.controller.value = Failure()
        with self.assertRaises(ValueError):
            await self.perform()
        self.controller.value = False
        for change in [dict(timed_request_timeout_ms=1), dict(fabric_id=2), dict(endpoint=3), dict(member=1), dict(type="commission")]:
            with self.assertRaises((ValueError, KeyError)):
                await self.perform(**change)

    async def test_write_requires_one_matching_success_status(self):
        self.assertEqual(await self.perform(type="write", value=None, timed_request_timeout_ms=500), "written")
        self.assertIs(self.controller.calls[-1][1][0][1].value, self.null)
        self.assertEqual(self.controller.calls[-1][2]["timedRequestTimeoutMs"], 500)
        for attribute, bad in [("status", 1), ("endpoint", 9), ("responses", 0), ("responses", 2)]:
            original = getattr(self.controller, attribute)
            setattr(self.controller, attribute, bad)
            with self.assertRaises(ValueError):
                await self.perform(type="write", value=True)
            setattr(self.controller, attribute, original)
        for timeout in [0, 1001, True, "100"]:
            with self.assertRaises(ValueError):
                await self.perform(type="write", value=True, timed_request_timeout_ms=timeout)

    async def test_invoke_requires_fields_and_a_response(self):
        self.assertEqual(await self.perform(type="invoke", value={}), {"accepted": True})
        self.assertFalse(self.controller.calls[-1][3]["suppressResponse"])
        with self.assertRaises(ValueError):
            await self.perform(type="invoke", value=None)

    def test_value_limits_and_null_are_explicit(self):
        self.assertIs(bridge.input_value(None, self.null), self.null)
        self.assertEqual(bridge.input_value({"type": "bytes", "base64": "AP8="}, self.null), b"\x00\xff")
        self.assertEqual(bridge.input_value([1, {"v": False}], self.null), [1, {"v": False}])
        for value in [float("inf"), [0] * 1025, object(), {"type": "bytes", "base64": "invalid"}]:
            with self.assertRaises(Exception):
                bridge.input_value(value, self.null)
        self.assertEqual(bridge.json_value(b"\x00\xff", self.null), {"type": "bytes", "base64": "AP8="})
        self.assertEqual(bridge.json_value([self.null, 42, {"v": True}], self.null), [None, 42, {"v": True}])
        for value in [object(), float("inf"), [0] * 1025, {1: "numeric key"}]:
            with self.assertRaises(ValueError):
                bridge.json_value(value, self.null)
        value = None
        for _ in range(10):
            value = [value]
        with self.assertRaises(ValueError):
            bridge.json_value(value, self.null)


class ProcessTest(unittest.TestCase):
    def test_factory_logs_cannot_corrupt_the_correlated_result_and_owner_exit_cancels(self):
        setup = r"""
import sys, types, contextlib, asyncio
sys.path.insert(0, TEST_PATH)
import matter_bridge_test as fixture
modules = {name: types.ModuleType(name) for name in ["matter", "matter.clusters", "matter.clusters.Objects", "matter.clusters.Types", "matter.clusters.Attribute", "fixture_factory"]}
modules["matter.clusters"].Objects = modules["matter.clusters.Objects"]
modules["matter.clusters"].ClusterObjects = types.SimpleNamespace(ALL_CLUSTERS={6:"cluster"}, ALL_ATTRIBUTES={6:{0:fixture.Attribute}})
modules["matter.clusters.Types"].NullValue = object()
modules["matter.clusters.Attribute"].ValueDecodeFailure = fixture.Failure
@contextlib.contextmanager
def factory(settings):
    print("private native log")
    print("private native error", file=sys.stderr)
    controller = fixture.Controller()
    if settings.get("wait"):
        async def wait(*args, **kwargs):
            await asyncio.sleep(30)
        controller.ReadAttribute = wait
    try:
        yield controller
    finally:
        print("private cleanup log")
modules["fixture_factory"].controller = factory
sys.modules.update(modules)
fixture.bridge.main()
""".replace("TEST_PATH", repr(str(pathlib.Path(__file__).parent)))
        request = {"id": 42, "timeout_ms": 1000,
            "config": {"factory": "fixture_factory:controller", "settings": {}, "fabric_id": 1},
            "message": dict(type="read", fabric_id=1, node_id=3, endpoint=2, cluster=6, member=0)}
        # Keep stdin open until a response so EOF specifically means owner termination.
        process = subprocess.Popen([sys.executable, "-B", "-c", setup], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.stdin.write((json.dumps(request) + "\n").encode())
        process.stdin.flush()
        self.assertEqual(json.loads(process.stdout.readline()), {"id": 42, "ok": False})
        self.assertEqual(process.wait(timeout=2), 0)
        self.assertEqual(process.stderr.read(), b"")
        process.stdin.close(); process.stdout.close(); process.stderr.close()
        request["config"]["settings"] = {"wait": True}
        process = subprocess.Popen([sys.executable, "-B", "-c", setup], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.stdin.write((json.dumps(request) + "\n").encode())
        process.stdin.close()
        process.wait(timeout=2)
        self.assertEqual(process.stdout.read(), b"")
        process.stdout.close(); process.stderr.close()


if __name__ == "__main__":
    unittest.main()
