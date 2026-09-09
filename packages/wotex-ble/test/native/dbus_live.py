"""Explicit real D-Bus contract lane; the GATT service is a test fixture.

Run with the pinned SDK interpreter and an absolute dbus-daemon executable:
    python -B test/native/dbus_live.py /absolute/path/to/dbus-daemon
This proves D-Bus ownership/marshalling, not Bluetooth interoperability.
"""

import asyncio
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
from importlib.metadata import version

from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "priv" / "bluez"))
from client import Central, Failure, DEVICE, ADAPTER, SERVICE, CHARACTERISTIC, MANAGER, PROPERTIES
from pairing import AGENT, MANAGER as AGENT_MANAGER
from procedures import execute, bytes_value

PEER = {"adapter": "/org/bluez/hci0", "address": "AA:BB:CC:DD:EE:FF", "address_type": "random"}
DEVICE_PATH = "/fixture/device"
SERVICE_PATH = "/fixture/service"
CHAR_PATH = "/fixture/characteristic"


class GattFixture:
    def __init__(self, bus):
        self.bus = bus
        self.calls = []
        self.connected = True
        self.race = False
        self.handle = 7
        self.agents = {}
        self.pair_tasks = {}
        self.pair_prompts = [("RequestConfirmation", "ou", [DEVICE_PATH, 123456])]
        self.pair_responses = []
        self.hang_pair = False
        self.bonds = {"existing-bond"}
        self.sender_loss_disconnects = 0
        self.pair_ack_signature = ""
        self.value = b"\x2a\x00"
        self.procedure_error = None
        self.procedure_signature = None
        self.flags = ["read", "write", "fixture-extension"]
        self.notify_sessions = set()
        self.notify_early = None
        self.notify_stop_errors = set()
        self.notify_signature = ""
        self.bus.add_message_handler(self.receive)

    def objects(self):
        return {
            PEER["adapter"]: {ADAPTER: {}},
            DEVICE_PATH: {DEVICE: {"Adapter": Variant("o", PEER["adapter"]), "Address": Variant("s", PEER["address"]), "AddressType": Variant("s", "random"), "Connected": Variant("b", self.connected), "ServicesResolved": Variant("b", self.connected)}},
            SERVICE_PATH: {SERVICE: {"Device": Variant("o", DEVICE_PATH), "UUID": Variant("s", "180f")}},
            CHAR_PATH: {CHARACTERISTIC: {"Service": Variant("o", SERVICE_PATH), "UUID": Variant("s", "2a19"), "Handle": Variant("q", self.handle), "Flags": Variant("as", self.flags)}},
        }

    def changed(self, object_path, interface, properties):
        return self.bus.send(Message.new_signal(object_path, PROPERTIES, "PropertiesChanged", "sa{sv}as", [interface, properties, []]))

    async def pair(self, message):
        try:
            for member, signature, body in self.pair_prompts:
                reply = await self.bus.call(Message(destination=message.sender, path=self.agents[message.sender], interface=AGENT, member=member, signature=signature, body=body))
                self.pair_responses.append((reply.message_type.name, reply.signature, reply.body))
                if self.hang_pair:
                    await asyncio.Event().wait()
                if reply.message_type != MessageType.METHOD_RETURN:
                    self.bus.send(Message.new_error(message, "org.bluez.Error.AuthenticationRejected", "Fixture rejected"))
                    return
            self.bus.send(Message.new_method_return(message, self.pair_ack_signature, [True] if self.pair_ack_signature else []))
        finally:
            self.pair_tasks.pop(message.sender, None)

    def receive(self, message):
        if message.message_type == MessageType.SIGNAL and message.sender == "org.freedesktop.DBus" and message.interface == "org.freedesktop.DBus" and message.member == "NameOwnerChanged":
            name, _, current = message.body
            if not current:
                self.agents.pop(name, None)
                self.notify_sessions.difference_update(item for item in list(self.notify_sessions) if item[0] == name)
                pending = self.pair_tasks.pop(name, None)
                if pending is not None:
                    # Pinned BlueZ device.c:create_bond_req_exit owns this side
                    # effect when the unresolved Pair sender disappears.
                    self.connected = False
                    self.sender_loss_disconnects += 1
                    pending.cancel()
                    self.changed(DEVICE_PATH, DEVICE, {"Connected": Variant("b", False), "ServicesResolved": Variant("b", False)})
            return None
        if message.message_type != MessageType.METHOD_CALL:
            return None
        self.calls.append((message.sender, message.interface, message.member))
        if message.path == "/org/bluez" and message.interface == AGENT_MANAGER:
            if message.member == "RegisterAgent":
                assert message.signature == "os"
                assert message.sender not in self.agents
                self.agents[message.sender] = message.body[0]
                return Message.new_method_return(message)
            if message.member == "UnregisterAgent":
                assert message.signature == "o"
                assert self.agents.pop(message.sender) == message.body[0]
                return Message.new_method_return(message)
        if message.interface == DEVICE and message.path == DEVICE_PATH:
            if message.member == "Pair":
                assert message.signature == ""
                assert message.sender in self.agents
                assert message.sender not in self.pair_tasks
                self.pair_tasks[message.sender] = asyncio.create_task(self.pair(message))
                return True
            if message.member in ("CancelPairing", "RemoveDevice"):
                self.bonds.clear()
                return Message.new_method_return(message)
        if message.path == CHAR_PATH and message.interface == CHARACTERISTIC and message.member in ("StartNotify", "StopNotify"):
            assert message.signature == "" and message.body == []
            session = (message.sender, message.path)
            if message.member == "StartNotify":
                assert session not in self.notify_sessions
                self.notify_sessions.add(session)
                if self.notify_early is not None:
                    self.changed(CHAR_PATH, CHARACTERISTIC, {"Value": Variant("ay", self.notify_early)})
            elif message.sender in self.notify_stop_errors:
                return Message.new_error(message, "org.bluez.Error.Failed", "SECRET_NATIVE_MESSAGE")
            else:
                self.notify_sessions.discard(session)
            return Message.new_method_return(message, self.notify_signature, [True] if self.notify_signature else [])
        if message.path == CHAR_PATH and message.interface == CHARACTERISTIC and message.member in ("ReadValue", "WriteValue"):
            if message.member == "WriteValue":
                assert message.signature == "aya{sv}"
                value, options = message.body
                assert set(options) == {"type", "offset"}
                assert options["type"].signature == "s" and options["type"].value == "request"
                assert options["offset"].signature == "q" and options["offset"].value == 0
                self.value = value
            else:
                assert message.signature == "a{sv}" and message.body == [{}]
                if self.notify_sessions:
                    self.changed(CHAR_PATH, CHARACTERISTIC, {"Value": Variant("ay", self.value)})
            if self.procedure_error:
                return Message.new_error(message, self.procedure_error, "SECRET_NATIVE_MESSAGE")
            signature = self.procedure_signature if self.procedure_signature is not None else "ay" if message.member == "ReadValue" else ""
            body = [self.value] if signature == "ay" else [] if signature == "" else [True]
            return Message.new_method_return(message, signature, body)
        if message.interface == MANAGER and message.member == "GetManagedObjects":
            data = self.objects()
            if self.race:
                self.race = False
                self.handle = 8
                self.changed(CHAR_PATH, CHARACTERISTIC, {"Handle": Variant("q", 8)})
            return Message.new_method_return(message, "a{oa{sa{sv}}}", [data])
        if message.interface == DEVICE and message.path == DEVICE_PATH and message.member in ("Connect", "Disconnect"):
            self.connected = message.member == "Connect"
            self.changed(DEVICE_PATH, DEVICE, {"Connected": Variant("b", self.connected), "ServicesResolved": Variant("b", self.connected)})
            return Message.new_method_return(message)
        return None


async def lane(address):
    server = await MessageBus(bus_address=address).connect()
    fixture = GattFixture(server)
    await server.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus", interface="org.freedesktop.DBus", member="AddMatch", signature="s", body=["type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'"]))
    await server.request_name("org.bluez")
    parameters = {"peer": PEER, "connection": "borrowed", "bus_address": address}
    owners = []
    try:
        events = []
        central = Central(events.append)
        owners.append(central)
        fixture.race = True
        opened = await central.open(parameters, 2000)
        page = await central.discover({}, 1000)
        assert page["characteristics"] == [{"service_uuid": "0000180f-0000-1000-8000-00805f9b34fb", "characteristic_uuid": "00002a19-0000-1000-8000-00805f9b34fb", "service_path": SERVICE_PATH, "object_path": CHAR_PATH, "handle": 8, "flags": ["read", "write", "fixture-extension"], "generation": 1}]
        assert len([call for call in fixture.calls if call[2] == "GetManagedObjects"]) == 3
        assert all(call[0] == opened["sender"] for call in fixture.calls)
        await central.close()
        assert fixture.connected is True
        assert not any(call[2] == "Disconnect" for call in fixture.calls)
        assert central.bus.handlers == {}

        procedures = Central(events.append)
        owners.append(procedures)
        procedure_owner = await procedures.open(parameters, 2000)
        submissions = []
        procedures.emit = submissions.append
        target = {"service": "180f", "characteristic": "2a19", "object_path": CHAR_PATH, "handle": 8, "generation": 1}
        assert bytes_value(await execute(procedures, "read", {"address": target}, 1000, "r")) == b"\x2a\x00"
        for encoded in ("", "AQI=", "AA=="):
            value = {"type": "bytes", "base64": encoded}
            assert await execute(procedures, "write", {"address": target, "value": value}, 1000, "w") is None
            assert await execute(procedures, "read", {"address": target}, 1000, "r") == value
        for name in ("NotPermitted", "NotAuthorized", "NotSupported", "InProgress", "InvalidValueLength", "InvalidOffset", "ImproperlyConfigured", "Failed", "FutureCase"):
            fixture.procedure_error = "org.bluez.Error." + name
            try:
                await execute(procedures, "write", {"address": target, "value": {"type": "bytes", "base64": "AQ=="}}, 1000, "w-error")
            except Failure as error:
                assert error.name == fixture.procedure_error
                assert "SECRET_NATIVE_MESSAGE" not in str(error) + json.dumps(error.envelope())
            else:
                raise AssertionError("D-Bus procedure denial reported success")
        fixture.procedure_error = None
        fixture.procedure_signature = "b"
        for operation in ("read", "write"):
            request = {"address": target, **({"value": {"type": "bytes", "base64": "AQ=="}} if operation == "write" else {})}
            try:
                await execute(procedures, operation, request, 1000, "bad-ack")
            except Failure as error:
                assert error.code == "invalid_response"
            else:
                raise AssertionError("wrong D-Bus return signature reported success")
        fixture.procedure_signature = None
        assert len(submissions) == 13
        assert {sender for sender, _, member in fixture.calls if member in ("ReadValue", "WriteValue")} == {procedure_owner["sender"]}
        await procedures.close()
        assert fixture.connected is True

        # Real SDK StartNotify/StopNotify use separate unique client senders;
        # PropertiesChanged comes from the independent BlueZ service sender.
        notification_cases = 0
        signal_sources = set()
        def record_signal(message):
            if message.message_type == MessageType.SIGNAL and message.path == CHAR_PATH and message.interface == PROPERTIES:
                signal_sources.add(message.sender)
        async def settle(predicate):
            for _ in range(200):
                if predicate():
                    return
                await asyncio.sleep(0.001)
            raise AssertionError("notification ownership did not settle")
        for flags, expected in [(["read", "notify"], "notify"), (["read", "indicate"], "indicate"), (["read", "notify", "indicate"], "bluez_selected")]:
            fixture.flags = flags
            fixture.notify_early = b"early"
            notify = Central(events.append)
            owners.append(notify)
            owner = await notify.open(parameters, 2000)
            assert owner["sender"] != server.unique_name
            notify.bus.bus.add_message_handler(record_signal)
            reports = []
            notify.emit = reports.append
            result = await notify.notifications.subscribe({"address": target, "mode": "auto"}, 1000, "notify")
            assert result["effective_mode"] == expected
            assert reports == []
            notify.notifications.activate("notify")
            assert bytes_value(reports[0]["value"]) == b"early"
            await execute(notify, "read", {"address": target}, 1000, "read-caused-change")
            await settle(lambda: len(reports) == 2)
            assert all(report["metadata"]["source"] == "bluez_value_change" for report in reports)
            await notify.notifications.unsubscribe({"subscription_id": "notify"}, 1000)
            assert fixture.notify_sessions == set()
            before = len(reports)
            await fixture.changed(CHAR_PATH, CHARACTERISTIC, {"Value": Variant("ay", b"late")})
            # A following D-Bus reply bounds delivery of the earlier signal.
            await notify.discover({}, 1000)
            assert len(reports) == before
            notify.bus.bus.remove_message_handler(record_signal)
            await notify.close()
            notification_cases += 1
        assert signal_sources == {server.unique_name}

        fixture.flags = ["read", "notify"]
        fixture.notify_early = None
        shared = []
        for identifier in ("shared-a", "shared-b"):
            notify = Central(events.append)
            owners.append(notify)
            owner = await notify.open(parameters, 2000)
            reports = []
            notify.emit = reports.append
            await notify.notifications.subscribe({"address": target, "mode": "auto"}, 1000, identifier)
            notify.notifications.activate(identifier)
            shared.append((notify, owner["sender"], identifier, reports))
        first, second = shared
        assert len({server.unique_name, first[1], second[1]}) == 3
        assert fixture.notify_sessions == {(first[1], CHAR_PATH), (second[1], CHAR_PATH)}
        await first[0].notifications.unsubscribe({"subscription_id": first[2]}, 1000)
        assert fixture.notify_sessions == {(second[1], CHAR_PATH)}
        await fixture.changed(CHAR_PATH, CHARACTERISTIC, {"Value": Variant("ay", b"shared")})
        await settle(lambda: len(second[3]) == 1)
        assert first[3] == []
        await first[0].notifications.subscribe({"address": target, "mode": "auto"}, 1000, "again")
        first[0].notifications.activate("again")
        fixture.notify_stop_errors.add(first[1])
        try:
            await first[0].notifications.unsubscribe({"subscription_id": "again"}, 1000)
        except Failure as error:
            assert error.code == "remote_error" and error.name == "org.bluez.Error.Failed"
        else:
            raise AssertionError("failed StopNotify reported success")
        await settle(lambda: fixture.notify_sessions == {(second[1], CHAR_PATH)})
        assert first[0].closed and fixture.connected
        assert not second[0].closed
        await second[0].notifications.unsubscribe({"subscription_id": second[2]}, 1000)
        await second[0].close()
        assert fixture.notify_sessions == set()
        for notify, sender, _, _ in shared:
            calls = [(source, member) for source, _, member in fixture.calls if source == sender and member in ("StartNotify", "StopNotify")]
            assert calls == [(sender, "StartNotify"), (sender, "StopNotify")] * (2 if notify is first[0] else 1)
        fixture.notify_stop_errors.clear()

        # The real SDK rejects a non-void StartNotify acknowledgement and
        # releases the uncertain acquisition through the same sender.
        malformed = Central(events.append)
        owners.append(malformed)
        await malformed.open(parameters, 2000)
        malformed.emit = lambda _: None
        fixture.notify_signature = "b"
        try:
            await malformed.notifications.subscribe({"address": target, "mode": "auto"}, 1000, "malformed")
        except Failure as error:
            assert error.code == "invalid_response"
        else:
            raise AssertionError("wrong StartNotify acknowledgement reported success")
        await malformed.close()
        fixture.notify_signature = ""
        assert fixture.notify_sessions == set()

        # New sender owns its own connection attempt and releases only that link.
        fixture.connected = False
        owned = Central(events.append)
        owners.append(owned)
        acquired = await owned.open({**parameters, "connection": "owned"}, 2000)
        assert acquired["link_owned"] is True
        assert acquired["sender"] != opened["sender"]
        await owned.close()
        assert fixture.connected is False
        assert [(sender, member) for sender, _, member in fixture.calls if member in ("Connect", "Disconnect")] == [(acquired["sender"], "Connect"), (acquired["sender"], "Disconnect")]

        # Same-sender Agent1 registration and real callback signatures: policy
        # remains explicit, with no default agent or bond removal.
        fixture.connected = True
        pairing = Central(events.append)
        owners.append(pairing)
        paired_owner = await pairing.open(parameters, 2000)
        challenges = []
        def accept(challenge):
            challenges.append(challenge)
            kind = challenge["challenge"]["kind"]
            answer = {"action": "pin", "value": "000042"} if kind == "request_pin" else {"action": "passkey", "value": 42} if kind == "request_passkey" else {"action": "accept"}
            pairing.agent_reply({"challenge_id": challenge["challenge"]["id"], "decision": answer})
        pairing.emit = accept
        fixture.pair_prompts = [("RequestPinCode", "o", [DEVICE_PATH]), ("RequestPasskey", "o", [DEVICE_PATH]), ("RequestConfirmation", "ou", [DEVICE_PATH, 123456])]
        assert await pairing.pair({"capability": "DisplayYesNo"}, 2000, "pair-1") == {"paired": True}
        assert fixture.pair_responses == [("METHOD_RETURN", "s", ["000042"]), ("METHOD_RETURN", "u", [42]), ("METHOD_RETURN", "", [])]
        assert len(challenges) == 3
        assert fixture.agents == {} and fixture.pair_tasks == {}
        fixture.pair_ack_signature = "b"
        fixture.pair_prompts = []
        try:
            await pairing.pair({"capability": "DisplayYesNo"}, 2000, "bad-pair-ack")
        except Failure as error:
            assert error.code == "invalid_response"
        else:
            raise AssertionError("wrong Pair acknowledgement signature reported success")
        fixture.pair_ack_signature = ""
        assert fixture.agents == {} and fixture.pair_tasks == {}
        assert {sender for sender, interface, _ in fixture.calls if interface == AGENT_MANAGER} == {paired_owner["sender"]}
        await pairing.close()
        assert fixture.connected is True

        # Cancelling a still-pending Pair drops only this application sender.
        # BlueZ's documented source behavior may disconnect the borrowed link;
        # it must never erase a completed/pre-existing bond.
        canceled = Central(events.append)
        owners.append(canceled)
        await canceled.open(parameters, 2000)
        prompted = asyncio.Event()
        canceled.emit = lambda _: prompted.set()
        fixture.pair_prompts = [("RequestConfirmation", "ou", [DEVICE_PATH, 123456])]
        fixture.hang_pair = True
        pair_task = asyncio.create_task(canceled.pair({"capability": "DisplayYesNo"}, 2000, "pair-2"))
        await asyncio.wait_for(prompted.wait(), 1)
        pair_task.cancel()
        try:
            await pair_task
        except asyncio.CancelledError:
            pass
        else:
            raise AssertionError("canceled Pair reported success")
        for _ in range(100):
            if fixture.sender_loss_disconnects:
                break
            await asyncio.sleep(0.001)
        assert fixture.sender_loss_disconnects == 1
        assert fixture.connected is False
        assert canceled.closed and canceled.bus.handlers == {}
        assert fixture.agents == {} and fixture.pair_tasks == {}
        assert fixture.bonds == {"existing-bond"}
        assert not any(member in ("CancelPairing", "RemoveDevice", "RequestDefaultAgent") for _, _, member in fixture.calls)

        # The old owner is terminal when the well-known name changes.
        fixture.connected = True
        observed = Central(events.append)
        owners.append(observed)
        await observed.open(parameters, 2000)
        await server.release_name("org.bluez")
        for _ in range(100):
            if observed.terminal:
                break
            await asyncio.sleep(0.001)
        assert events == ["owner_changed"]
        try:
            await observed.discover({}, 1000)
        except Failure as error:
            assert error.code == "owner_changed"
        else:
            raise AssertionError("old bus owner remained usable")
        return {"requirements": ["WBL-C03", "WBL-C07", "WBL-S01", "WBL-S02", "WBL-V03", "WBL-V04", "WBL-S05", "WBL-V06", "WBL-S03", "WBL-V05", "WBL-P05", "WBL-S04", "WBL-V07", "WBL-V08", "WBL-V09"], "dbus_next": version("dbus-next"), "snapshots": sum(call[2] == "GetManagedObjects" for call in fixture.calls), "owned_connects": sum(call[2] == "Connect" for call in fixture.calls), "owned_disconnects": sum(call[2] == "Disconnect" for call in fixture.calls), "borrowed_disconnect_calls": 0, "pending_pair_sender_loss_disconnects": fixture.sender_loss_disconnects, "agents_remaining": len(fixture.agents), "pair_requests_remaining": len(fixture.pair_tasks), "pairing_callbacks": len(fixture.pair_responses), "acknowledged_writes": 3, "named_write_rejections": 9, "malformed_signatures_rejected": 4, "notification_mode_cases": notification_cases, "notification_clients_isolated": 2, "notification_sessions_remaining": len(fixture.notify_sessions), "notification_signal_sources": len(signal_sources), "bonds_preserved": len(fixture.bonds), "status": "passed", "evidence": "real_dbus_injected_gatt"}
    finally:
        for owner in owners:
            await owner.close()
        pending = list(fixture.pair_tasks.values())
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        server.remove_message_handler(fixture.receive)
        server.disconnect()
        await server.wait_for_disconnect()


def main():
    if len(sys.argv) != 2 or not os.path.isabs(sys.argv[1]):
        raise SystemExit("one absolute dbus-daemon executable is required")
    executable = pathlib.Path(sys.argv[1])
    assert executable.is_file(), "required dbus-daemon is missing"
    assert version("dbus-next") == "0.2.3", "the pinned SDK is required"
    with tempfile.TemporaryDirectory(prefix="wbl-bus-", dir="/tmp") as temporary:
        socket = pathlib.Path(temporary) / "bus"
        config = pathlib.Path(temporary) / "bus.conf"
        config.write_text(f'<busconfig><type>session</type><listen>unix:path={socket}</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
        process = subprocess.Popen([str(executable), "--nofork", "--config-file=" + str(config)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(200):
                if socket.exists():
                    break
                assert process.poll() is None, "private daemon exited before readiness"
                time.sleep(0.01)
            assert socket.exists(), "private daemon did not become ready"
            result = asyncio.run(lane("unix:path=" + str(socket)))
            result["dbus_daemon_sha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
            result["dbus_daemon_version"] = subprocess.check_output([str(executable), "--version"], text=True).splitlines()[0]
            result["fixture_sha256"] = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
            print(json.dumps(result, sort_keys=True))
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)
            process.stderr.close()


if __name__ == "__main__":
    main()
