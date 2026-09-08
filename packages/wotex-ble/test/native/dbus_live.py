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
        self.bus.add_message_handler(self.receive)

    def objects(self):
        return {
            PEER["adapter"]: {ADAPTER: {}},
            DEVICE_PATH: {DEVICE: {"Adapter": Variant("o", PEER["adapter"]), "Address": Variant("s", PEER["address"]), "AddressType": Variant("s", "random"), "Connected": Variant("b", self.connected), "ServicesResolved": Variant("b", self.connected)}},
            SERVICE_PATH: {SERVICE: {"Device": Variant("o", DEVICE_PATH), "UUID": Variant("s", "180f")}},
            CHAR_PATH: {CHARACTERISTIC: {"Service": Variant("o", SERVICE_PATH), "UUID": Variant("s", "2a19"), "Handle": Variant("q", self.handle), "Flags": Variant("as", ["read", "write", "fixture-extension"])}},
        }

    def changed(self, object_path, interface, properties):
        return self.bus.send(Message.new_signal(object_path, PROPERTIES, "PropertiesChanged", "sa{sv}as", [interface, properties, []]))

    def receive(self, message):
        if message.message_type != MessageType.METHOD_CALL:
            return None
        self.calls.append((message.sender, message.interface, message.member))
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
        return {"requirements": ["WBL-C03", "WBL-C07", "WBL-S01", "WBL-S02", "WBL-V03", "WBL-V04"], "dbus_next": version("dbus-next"), "snapshots": sum(call[2] == "GetManagedObjects" for call in fixture.calls), "owned_connects": sum(call[2] == "Connect" for call in fixture.calls), "owned_disconnects": sum(call[2] == "Disconnect" for call in fixture.calls), "borrowed_disconnects": 0, "status": "passed", "evidence": "real_dbus_injected_gatt"}
    finally:
        for owner in owners:
            await owner.close()
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
