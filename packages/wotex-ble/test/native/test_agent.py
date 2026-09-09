"""Explicit Agent1 policy and resource tests on an injected D-Bus boundary."""
import asyncio
import unittest
import time

from test_bluez import Bus, OPTIONS, DEVICE_PATH
from client import Central, Failure
from pairing import AGENT, METHODS, decision, prompt


class AgentBus(Bus):
    def __init__(self):
        super().__init__()
        self.methods = []
        self.registered = None
        self.prompts = [("RequestConfirmation", "ou", [DEVICE_PATH, 123456])]
        self.responses = []
        self.bonds = {"existing-bond"}
        self.unregister_failure = False
        self.pair_error = None

    def listen_calls(self, callback):
        self.methods.append(callback)

    def unlisten(self, callback):
        if callback in self.methods:
            self.methods.remove(callback)
        else:
            super().unlisten(callback)

    def disconnect(self):
        self.registered = None
        super().disconnect()

    async def call(self, destination, object_path, interface, member, signature, body):
        if member not in ("RegisterAgent", "UnregisterAgent", "Pair", "CancelPairing", "RemoveDevice"):
            return await super().call(destination, object_path, interface, member, signature, body)
        self.calls.append((destination, object_path, interface, member, signature, body))
        if member == "RegisterAgent":
            assert self.registered is None
            assert signature == "os"
            self.registered = body[0]
        if member == "UnregisterAgent":
            assert body == [self.registered]
            if self.unregister_failure:
                raise Failure("remote_error")
            self.registered = None
        if member in ("CancelPairing", "RemoveDevice"):
            self.bonds.clear()
        if member == "Pair":
            if self.pair_error:
                raise Failure(self.pair_error)
            assert self.registered is not None
            for method, method_signature, parameters in self.prompts:
                result = asyncio.get_running_loop().create_future()
                def respond(signature, body, error):
                    self.responses.append((signature, body, error))
                    if not result.done():
                        result.set_result(error)
                agent_path = self.registered
                if method == "Release":
                    self.registered = None
                accepted = self.methods[0](":1.2", agent_path, AGENT, method, method_signature, parameters, respond)
                assert accepted is True
                if await result:
                    raise Failure("pairing_rejected")
        return []


class AgentTest(unittest.IsolatedAsyncioTestCase):
    async def central(self, policy):
        bus = AgentBus()
        central = Central(lambda _: None, lambda _: bus)
        self.addAsyncCleanup(central.close)
        await central.open(OPTIONS, 1000)
        events = []
        def emit(event):
            events.append(event)
            if policy is not None:
                central.agent_reply({"challenge_id": event["challenge"]["id"], "decision": policy(event["challenge"])})
        central.emit = emit
        return central, bus, events

    def cleaned(self, central, bus):
        self.assertIsNone(central.agent)
        self.assertIsNone(bus.registered)
        self.assertEqual(bus.methods, [])
        self.assertEqual(bus.bonds, {"existing-bond"})
        self.assertEqual(bus.count("CancelPairing"), 0)
        self.assertEqual(bus.count("RemoveDevice"), 0)
        self.assertEqual(bus.count("RequestDefaultAgent"), 0)

    async def test_WBL_P03_S02_V06_explicit_exact_peer_confirmation(self):
        central, bus, events = await self.central(lambda _: {"action": "accept"})
        self.assertEqual(await central.pair({"capability": "DisplayYesNo"}, 1000, "pair-1"), {"paired": True})
        self.assertEqual(bus.responses, [("", [], None)])
        self.assertEqual(events[0]["id"], "pair-1")
        self.assertEqual(events[0]["challenge"]["peer"], OPTIONS["peer"])
        self.assertEqual(events[0]["challenge"]["kind"], "confirm_passkey")
        self.assertEqual(events[0]["challenge"]["value"], 123456)
        self.assertGreater(events[0]["challenge"]["timeout_ms"], 0)
        self.assertEqual(bus.count("RegisterAgent"), 1)
        self.assertEqual(bus.count("UnregisterAgent"), 1)
        self.cleaned(central, bus)

    async def test_WBL_V06_each_prompt_and_response_schema(self):
        central, bus, events = await self.central(lambda challenge: {"action": "pin", "value": "000042"} if challenge["kind"] == "request_pin" else {"action": "passkey", "value": 42} if challenge["kind"] == "request_passkey" else {"action": "accept"})
        bus.prompts = [
            ("RequestPinCode", "o", [DEVICE_PATH]),
            ("RequestPasskey", "o", [DEVICE_PATH]),
            ("DisplayPinCode", "os", [DEVICE_PATH, "000042"]),
            ("DisplayPasskey", "ouq", [DEVICE_PATH, 42, 2]),
            ("RequestAuthorization", "o", [DEVICE_PATH]),
            ("AuthorizeService", "os", [DEVICE_PATH, "180f"]),
        ]
        self.assertEqual(await central.pair({"capability": "KeyboardOnly"}, 1000, "pair-2"), {"paired": True})
        self.assertEqual(bus.responses[:2], [("s", ["000042"], None), ("u", [42], None)])
        self.assertEqual(events[-1]["challenge"]["value"], "0000180f-0000-1000-8000-00805f9b34fb")
        self.assertEqual(len({event["challenge"]["id"] for event in events}), 6)
        self.cleaned(central, bus)

    async def test_WBL_V06_rejection_and_missing_callback_close_without_unpairing(self):
        for policy in [lambda _: {"action": "reject"}, lambda _: {"action": "passkey", "value": 999999}, None]:
            central, bus, _ = await self.central(policy)
            with self.assertRaisesRegex(Failure, "pairing_rejected"):
                await central.pair({"capability": "NoInputNoOutput"}, 20, "pair-3")
            self.cleaned(central, bus)
            await central.close()

    async def test_WBL_V06_wrong_peer_signature_and_method_never_reach_policy(self):
        for method, signature, body in [("RequestConfirmation", "ou", ["/foreign", 42]), ("RequestConfirmation", "os", [DEVICE_PATH, "42"]), ("AutomaticAccept", "o", [DEVICE_PATH]), ("DisplayPasskey", "ouq", [DEVICE_PATH, 42, 7]), ("Cancel", "", []), ("Release", "", [])]:
            central, bus, events = await self.central(lambda _: {"action": "accept"})
            bus.prompts = [(method, signature, body)]
            with self.assertRaisesRegex(Failure, "pairing_rejected"):
                await central.pair({"capability": "DisplayYesNo"}, 1000, "pair-4")
            self.assertEqual(events, [])
            self.cleaned(central, bus)
            await central.close()

    async def test_WBL_V06_wrong_challenge_id_and_late_decision_fail(self):
        central, bus, events = await self.central(None)
        task = asyncio.create_task(central.pair({"capability": "DisplayYesNo"}, 1000, "pair-5"))
        while not events:
            await asyncio.sleep(0)
        with self.assertRaisesRegex(Failure, "pairing_rejected"):
            central.agent_reply({"challenge_id": "foreign", "decision": {"action": "accept"}})
        with self.assertRaisesRegex(Failure, "pairing_rejected"):
            await task
        with self.assertRaisesRegex(Failure, "pairing_rejected"):
            central.agent_reply({"challenge_id": events[0]["challenge"]["id"], "decision": {"action": "accept"}})
        self.cleaned(central, bus)

    async def test_WBL_C03_owner_cancellation_and_unregister_failure_release_sender(self):
        central, bus, events = await self.central(None)
        task = asyncio.create_task(central.pair({"capability": "DisplayYesNo"}, 60000, "pair-6"))
        while not events:
            await asyncio.sleep(0)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.cleaned(central, bus)
        self.assertTrue(bus.closed.is_set())
        central, bus, _ = await self.central(lambda _: {"action": "accept"})
        bus.unregister_failure = True
        with self.assertRaisesRegex(Failure, "disconnected"):
            await central.pair({"capability": "DisplayYesNo"}, 1000, "pair-7")
        self.cleaned(central, bus)
        self.assertTrue(bus.closed.is_set())

    async def test_WBL_C03_late_policy_and_callback_send_failure_release_resources(self):
        central, bus, events = await self.central(None)
        task = asyncio.create_task(central.pair({"capability": "DisplayYesNo"}, 1000, "pair-late"))
        while not events:
            await asyncio.sleep(0)
        central.agent.deadline = time.monotonic() - 1
        with self.assertRaisesRegex(Failure, "pairing_rejected"):
            central.agent_reply({"challenge_id": events[0]["challenge"]["id"], "decision": {"action": "accept"}})
        with self.assertRaisesRegex(Failure, "pairing_rejected"):
            await task
        self.assertEqual(bus.responses[-1], ("", [], "org.bluez.Error.Rejected"))
        self.cleaned(central, bus)
        for asynchronous in (False, True):
            central, bus, events = await self.central(None)
            task = asyncio.create_task(central.pair({"capability": "DisplayYesNo"}, 1000, "pair-send"))
            while not events:
                await asyncio.sleep(0)
            def broken(*_):
                if not asynchronous:
                    raise OSError("secret-native-error")
                future = asyncio.get_running_loop().create_future()
                future.set_exception(OSError("secret-native-error"))
                return future
            central.agent.pending["respond"] = broken
            central.agent_reply({"challenge_id": events[0]["challenge"]["id"], "decision": {"action": "accept"}})
            with self.assertRaisesRegex(Failure, "disconnected"):
                await task
            self.cleaned(central, bus)
            self.assertTrue(central.closed)

    async def test_WBL_V06_foreign_sender_and_overlapping_prompts_never_accept(self):
        central, bus, events = await self.central(None)
        task = asyncio.create_task(central.pair({"capability": "DisplayYesNo"}, 1000, "pair-overlap"))
        while not events:
            await asyncio.sleep(0)
        replies = []
        respond = lambda *reply: replies.append(reply)
        agent = central.agent
        self.assertIsNone(agent.receive(":1.2", "/foreign", AGENT, "RequestAuthorization", "o", [DEVICE_PATH], respond))
        self.assertTrue(agent.receive(":9.9", agent.object_path, AGENT, "RequestAuthorization", "o", [DEVICE_PATH], respond))
        self.assertFalse(agent.failure.done())
        self.assertTrue(agent.receive(":1.2", agent.object_path, AGENT, "RequestAuthorization", "o", [DEVICE_PATH], respond))
        with self.assertRaisesRegex(Failure, "pairing_rejected"):
            await task
        self.assertEqual(len(events), 1)
        self.assertEqual(replies, [("", [], "org.bluez.Error.Rejected")] * 2)
        self.assertEqual(bus.responses, [("", [], "org.bluez.Error.Rejected")])
        self.cleaned(central, bus)

    async def test_WBL_C02_invalid_options_acquire_no_agent(self):
        central, bus, _ = await self.central(None)
        for parameters in [None, {}, {"capability": []}, {"capability": "KeyboardDisplay"}, {"capability": "KeyboardOnly", "extra": 1}]:
            with self.assertRaisesRegex(Failure, "invalid_options"):
                await central.pair(parameters, 1000, "pair-8")
        self.assertEqual(bus.count("RegisterAgent"), 0)
        self.cleaned(central, bus)
        bus.pair_error = "busy"
        with self.assertRaisesRegex(Failure, "busy"):
            await central.pair({"capability": "KeyboardOnly"}, 1000, "pair-9")
        self.assertFalse(bus.closed.is_set())
        self.cleaned(central, bus)


class PromptTest(unittest.TestCase):
    def test_WBL_C02_decisions_and_prompts_are_finite(self):
        for kind, value in [("unknown", {"action": "accept"}), ("request_pin", {"action": "accept"}), ("request_pin", {"action": "pin", "value": "\x00"}), ("request_pin", {"action": "pin", "value": "x" * 17}), ("request_passkey", {"action": "passkey", "value": True}), ("request_passkey", {"action": "passkey", "value": 1000000}), ("request_passkey", [])]:
            with self.assertRaisesRegex(Failure, "pairing_rejected"):
                decision(kind, value)
        for method, signature, body in [(None, "o", []), ([], "o", []), ("RequestPinCode", "o", []), ("RequestConfirmation", "ou", [DEVICE_PATH, True])]:
            with self.assertRaises(Failure):
                prompt(method, signature, body, DEVICE_PATH)


if __name__ == "__main__":
    unittest.main()
