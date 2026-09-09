"""Bounded BlueZ discovery and explicit D-Bus connection ownership."""

import asyncio
import re
import secrets
import time
import uuid

REVISION = "0.2.3"
DEVICE = "org.bluez.Device1"
SERVICE = "org.bluez.GattService1"
CHARACTERISTIC = "org.bluez.GattCharacteristic1"
ADAPTER = "org.bluez.Adapter1"
PROPERTIES = "org.freedesktop.DBus.Properties"
MANAGER = "org.freedesktop.DBus.ObjectManager"
PATH = re.compile(r"/(?:[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*)?\Z")
ADDRESS = re.compile(r"[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\Z")
ERRORS = {
    "org.bluez.Error.NotConnected": "disconnected",
    "org.bluez.Error.NotPermitted": "not_permitted",
    "org.bluez.Error.NotAuthorized": "not_authorized",
    "org.bluez.Error.NotSupported": "not_supported",
    "org.bluez.Error.InProgress": "busy",
    "org.bluez.Error.InvalidValueLength": "invalid_value_length",
    "org.bluez.Error.InvalidOffset": "invalid_offset",
    "org.bluez.Error.ImproperlyConfigured": "improperly_configured",
}


class Failure(Exception):
    """Carries only a finite library-owned failure code."""

    def __init__(self, code, name=None):
        self.code = code
        self.name = name if isinstance(name, str) and len(name) <= 128 and re.fullmatch(r"org\.bluez\.Error\.[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*", name) else None
        super().__init__(code)

    def envelope(self):
        return {"code": self.code, **({"name": self.name} if self.name is not None else {})}


def path(value):
    return isinstance(value, str) and len(value.encode("utf-8")) <= 4096 and PATH.fullmatch(value) is not None


def integer(value, minimum, maximum):
    return type(value) is int and minimum <= value <= maximum


def canonical_uuid(value):
    if not isinstance(value, str) or len(value) > 36:
        raise Failure("invalid_characteristic")
    compact = value.replace("-", "")
    if len(value) in (4, 8) and re.fullmatch(r"[0-9a-fA-F]+", value):
        compact = compact.zfill(8) + "00001000800000805f9b34fb"
    elif not (re.fullmatch(r"[0-9a-fA-F]{32}", value) or re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value)):
        raise Failure("invalid_characteristic")
    return str(uuid.UUID(hex=compact))


def peer_options(parameters):
    if not isinstance(parameters, dict) or set(parameters) != {"peer", "connection", "bus_address"}:
        raise Failure("invalid_options")
    peer = parameters["peer"]
    if not isinstance(peer, dict) or set(peer) != {"adapter", "address", "address_type"}:
        raise Failure("invalid_peer")
    if not path(peer["adapter"]) or not isinstance(peer["address"], str) or not ADDRESS.fullmatch(peer["address"]):
        raise Failure("invalid_peer")
    if peer["address_type"] not in ("public", "random"):
        raise Failure("invalid_peer")
    if parameters["connection"] not in ("owned", "borrowed"):
        raise Failure("invalid_options")
    address = parameters["bus_address"]
    # A bus address is explicit local IPC. Network/address fallback lists are not admitted.
    if not isinstance(address, str) or len(address.encode("utf-8")) > 4096 or not re.fullmatch(r"unix:(?:path|abstract)=[^;\x00-\x20]+", address):
        raise Failure("invalid_options")
    return dict(peer, address=peer["address"].upper())


def catalogue(objects, peer, generation):
    if not isinstance(objects, dict) or len(objects) > 4096:
        raise Failure("object_limit")
    if any(not path(key) or not isinstance(value, dict) for key, value in objects.items()):
        raise Failure("invalid_response")
    if not isinstance(objects.get(peer["adapter"], {}).get(ADAPTER), dict):
        raise Failure("peer_not_found")
    matches = []
    for object_path, interfaces in objects.items():
        device = interfaces.get(DEVICE)
        if isinstance(device, dict) and device.get("Adapter") == peer["adapter"] and isinstance(device.get("Address"), str) and device["Address"].upper() == peer["address"] and device.get("AddressType") == peer["address_type"]:
            matches.append((object_path, device))
    if not matches:
        raise Failure("peer_not_found")
    if len(matches) != 1:
        raise Failure("ambiguous_peer")
    device_path, device = matches[0]
    if type(device.get("Connected")) is not bool or type(device.get("ServicesResolved")) is not bool:
        raise Failure("invalid_response")
    services = {}
    for object_path, interfaces in objects.items():
        service = interfaces.get(SERVICE)
        if isinstance(service, dict) and service.get("Device") == device_path:
            services[object_path] = canonical_uuid(service.get("UUID"))
    if len(services) > 1024:
        raise Failure("object_limit")
    characteristics = []
    for object_path, interfaces in objects.items():
        characteristic = interfaces.get(CHARACTERISTIC)
        if not isinstance(characteristic, dict) or not isinstance(characteristic.get("Service"), str) or characteristic["Service"] not in services:
            continue
        handle = characteristic.get("Handle")
        flags = characteristic.get("Flags")
        if handle is not None and not integer(handle, 1, 65535):
            raise Failure("invalid_characteristic")
        if not isinstance(flags, list) or len(flags) > 64 or any(not isinstance(flag, str) or not 1 <= len(flag.encode("utf-8")) <= 64 for flag in flags) or len(set(flags)) != len(flags):
            raise Failure("invalid_characteristic")
        characteristics.append({
            "service_uuid": services[characteristic["Service"]],
            "characteristic_uuid": canonical_uuid(characteristic.get("UUID")),
            "service_path": characteristic["Service"],
            "object_path": object_path,
            "handle": handle,
            "flags": flags,
            "generation": generation,
        })
        if len(services) + len(characteristics) > 1024:
            raise Failure("object_limit")
    characteristics.sort(key=lambda item: (item["service_path"], item["object_path"]))
    return device_path, device, characteristics


class DBusConnection:
    """Uses the pinned dbus-next API without introspection or shell commands."""

    def __init__(self, address):
        self.address = address
        self.bus = None
        self.handlers = {}

    async def connect(self):
        from importlib.metadata import version
        from dbus_next.aio import MessageBus
        if version("dbus-next") != REVISION:
            raise Failure("incompatible_backend")
        self.bus = MessageBus(bus_address=self.address)
        await self.bus.connect()

    async def call(self, destination, object_path, interface, member, signature="", body=None):
        from dbus_next import Message, MessageType
        reply = await self.bus.call(Message(destination=destination, path=object_path, interface=interface, member=member, signature=signature, body=body or []))
        if reply is None or reply.message_type not in (MessageType.METHOD_RETURN, MessageType.ERROR):
            raise Failure("invalid_response")
        if reply.sender != destination:
            raise Failure("invalid_response")
        if reply.message_type == MessageType.ERROR:
            raise Failure(ERRORS.get(reply.error_name, "remote_error"), reply.error_name)
        expected = {
            (MANAGER, "GetManagedObjects"): "a{oa{sa{sv}}}",
            ("org.freedesktop.DBus", "GetNameOwner"): "s",
            ("org.freedesktop.DBus", "AddMatch"): "",
            (DEVICE, "Connect"): "", (DEVICE, "Disconnect"): "", (DEVICE, "Pair"): "",
            ("org.bluez.AgentManager1", "RegisterAgent"): "",
            ("org.bluez.AgentManager1", "UnregisterAgent"): "",
            (CHARACTERISTIC, "ReadValue"): "ay", (CHARACTERISTIC, "WriteValue"): "",
            (CHARACTERISTIC, "StartNotify"): "", (CHARACTERISTIC, "StopNotify"): "",
        }.get((interface, member))
        if expected is None or reply.signature != expected:
            raise Failure("invalid_response")
        return reply.body

    @staticmethod
    def write_options():
        from dbus_next import Variant
        return {"type": Variant("s", "request"), "offset": Variant("q", 0)}

    def listen(self, handler):
        from dbus_next import MessageType
        def receive(message):
            if message.message_type == MessageType.SIGNAL:
                handler(message.sender, message.path, message.interface, message.member, message.body)
        self.handlers[handler] = receive
        self.bus.add_message_handler(receive)

    def listen_calls(self, handler):
        from dbus_next import Message, MessageType
        def receive(message):
            if message.message_type != MessageType.METHOD_CALL:
                return None
            def respond(signature, body, error):
                reply = (Message.new_error(message, error, "Pairing rejected") if error
                         else Message.new_method_return(message, signature, body))
                return self.bus.send(reply)
            return handler(message.sender, message.path, message.interface, message.member,
                           message.signature, message.body, respond)
        self.handlers[handler] = receive
        self.bus.add_message_handler(receive)

    def unlisten(self, handler):
        receive = self.handlers.pop(handler, None)
        if receive is not None:
            self.bus.remove_message_handler(receive)

    def disconnect(self):
        if self.bus is not None:
            self.bus.disconnect()

    async def wait_closed(self):
        await self.bus.wait_for_disconnect()

    @property
    def unique_name(self):
        return self.bus.unique_name

    @staticmethod
    def snapshot(body):
        if not isinstance(body, list) or len(body) != 1 or not isinstance(body[0], dict) or len(body[0]) > 4096:
            raise Failure("object_limit")
        fields = {
            ADAPTER: (),
            DEVICE: ("Adapter", "Address", "AddressType", "Connected", "ServicesResolved"),
            SERVICE: ("Device", "UUID"),
            CHARACTERISTIC: ("Service", "UUID", "Handle", "Flags"),
        }
        result = {}
        for object_path, interfaces in body[0].items():
            if not isinstance(interfaces, dict):
                raise Failure("invalid_response")
            selected = {}
            for interface, keys in fields.items():
                if interface not in interfaces:
                    continue
                properties = interfaces[interface]
                if not isinstance(properties, dict):
                    raise Failure("invalid_response")
                selected[interface] = {key: getattr(properties[key], "value", properties[key]) for key in keys if key in properties}
            result[object_path] = selected
        return result


class Central:
    """Owns one bus sender, one selected peer and bounded discovery snapshots."""

    def __init__(self, signal, bus_factory=DBusConnection):
        self.signal = signal
        self.bus_factory = bus_factory
        self.bus = None
        self.peer = None
        self.device_path = None
        self.bluez_owner = None
        self.link_owned = False
        self.closed = False
        self.ready = False
        self.revision = 0
        self.generation = 1
        self.characteristics = []
        self.cursors = {}
        self.wake = asyncio.Event()
        self.changed = False
        self.terminal = None
        self.listener_installed = False
        self.disconnect_task = None
        self.agent = None
        self.emit = None
        self.cleanup_deadline = None
        from notifications import Notifications
        self.notifications = Notifications(self)

    async def watch_disconnect(self):
        try:
            await self.bus.wait_closed()
        except asyncio.CancelledError:
            return
        except Exception:
            pass
        if not self.closed:
            self.fail("disconnected")

    def on_signal(self, sender, object_path, interface, member, body):
        if self.closed:
            return
        self.notifications.signal(sender, object_path, interface, member, body)
        if sender == "org.freedesktop.DBus" and interface == "org.freedesktop.DBus" and member == "NameOwnerChanged" and isinstance(body, list) and len(body) == 3 and body[0] == "org.bluez":
            self.fail("owner_changed")
            return
        if sender != self.bluez_owner:
            return
        if interface not in (PROPERTIES, MANAGER):
            return
        if member not in ("PropertiesChanged", "InterfacesAdded", "InterfacesRemoved"):
            return
        if member == "PropertiesChanged":
            if not isinstance(body, list) or len(body) != 3 or not isinstance(body[0], str) or not isinstance(body[1], dict) or not isinstance(body[2], list) or any(not isinstance(key, str) for key in [*body[1], *body[2]]):
                self.fail("invalid_response")
                return
            identity_fields = {
                DEVICE: {"Adapter", "Address", "AddressType", "Connected", "ServicesResolved"},
                SERVICE: {"Device", "UUID"},
                CHARACTERISTIC: {"Service", "UUID", "Handle", "Flags"},
            }.get(body[0], set())
            if not identity_fields.intersection(set(body[1]) | set(body[2])):
                return
        self.revision += 1
        self.changed = True
        self.cursors.clear()
        self.wake.set()
        if self.ready and member == "InterfacesRemoved" and isinstance(body, list) and len(body) == 2:
            removed = body[0]
            if removed == self.device_path or any(removed in (item["service_path"], item["object_path"]) for item in self.characteristics):
                self.fail("disconnected")
        if self.ready and object_path == self.device_path and member == "PropertiesChanged" and isinstance(body, list) and len(body) == 3 and body[0] == DEVICE:
            properties = body[1]
            if isinstance(properties, dict) and any(getattr(properties.get(key), "value", properties.get(key)) is False for key in ("Connected", "ServicesResolved")):
                self.fail("disconnected")

    def fail(self, code):
        if self.terminal is None:
            self.terminal = code
            self.wake.set()
            self.signal(code)
            self.notifications.fail_all(code)
            if self.agent is not None:
                self.agent.abort(code)

    async def bounded(self, awaitable, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            awaitable.close()
            raise Failure("timeout")
        try:
            result = await asyncio.wait_for(awaitable, remaining)
        except asyncio.TimeoutError:
            raise Failure("timeout") from None
        if self.terminal:
            raise Failure(self.terminal)
        return result

    async def call(self, object_path, interface, member, deadline, signature="", body=None, destination=None):
        return await self.bounded(self.bus.call(destination or self.bluez_owner, object_path, interface, member, signature, body), deadline)

    async def refresh(self, deadline):
        for _ in range(4):
            revision = self.revision
            body = await self.call("/", MANAGER, "GetManagedObjects", deadline)
            device_path, device, characteristics = catalogue(DBusConnection.snapshot(body), self.peer, self.generation)
            if revision != self.revision:
                continue
            if self.ready and (not device["Connected"] or not device["ServicesResolved"]):
                self.fail("disconnected")
                raise Failure("disconnected")
            if self.device_path is not None and device_path != self.device_path:
                raise Failure("peer_changed")
            if self.ready and (self.changed or characteristics != self.characteristics):
                if self.generation == 2**64 - 1:
                    raise Failure("generation_exhausted")
                self.generation += 1
                self.cursors.clear()
                for item in characteristics:
                    item["generation"] = self.generation
            self.device_path = device_path
            self.characteristics = characteristics
            self.changed = False
            return device
        raise Failure("snapshot_unstable")

    async def open(self, parameters, timeout_ms):
        self.peer = peer_options(parameters)
        deadline = time.monotonic() + timeout_ms / 1000
        self.bus = self.bus_factory(parameters["bus_address"])
        try:
            await self.bounded(self.bus.connect(), deadline)
            self.disconnect_task = asyncio.create_task(self.watch_disconnect())
            self.bus.listen(self.on_signal)
            self.listener_installed = True
            for rule in [
                "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties'",
                "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager'",
                "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'",
            ]:
                await self.call("/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch", deadline, "s", [rule], "org.freedesktop.DBus")
            owner = await self.call("/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", deadline, "s", ["org.bluez"], "org.freedesktop.DBus")
            if not isinstance(owner, list) or len(owner) != 1 or not isinstance(owner[0], str) or not re.fullmatch(r":[0-9]+\.[0-9]+", owner[0]):
                raise Failure("invalid_response")
            self.bluez_owner = owner[0]
            device = await self.refresh(deadline)
            if not device["Connected"]:
                if parameters["connection"] == "borrowed":
                    raise Failure("disconnected")
                # The initial disconnected snapshot and explicit owned mode authorize
                # canceling this connection attempt even if its acknowledgement is lost.
                self.link_owned = True
                try:
                    await self.call(self.device_path, DEVICE, "Connect", deadline)
                except Failure as error:
                    if error.code not in ("timeout", "disconnected", "owner_changed"):
                        self.link_owned = False
                    raise
            while not (device["Connected"] and device["ServicesResolved"]):
                self.wake.clear()
                device = await self.refresh(deadline)
                if device["Connected"] and device["ServicesResolved"]:
                    break
                if parameters["connection"] == "borrowed":
                    raise Failure("services_unresolved")
                await self.bounded(self.wake.wait(), deadline)
            self.ready = True
            return {"generation": self.generation, "device_path": self.device_path, "link_owned": self.link_owned, "sender": self.bus.unique_name}
        except BaseException:
            await self.close()
            raise

    async def discover(self, parameters, timeout_ms):
        if not self.ready or self.closed or self.terminal:
            raise Failure(self.terminal or "disconnected")
        if not isinstance(parameters, dict) or set(parameters) - {"cursor", "limit"}:
            raise Failure("invalid_options")
        limit = parameters.get("limit", 64)
        cursor = parameters.get("cursor")
        if not integer(limit, 1, 64):
            raise Failure("invalid_options")
        if cursor is None:
            await self.refresh(time.monotonic() + timeout_ms / 1000)
            offset = 0
        else:
            if self.changed:
                raise Failure("stale_discovery")
            if not isinstance(cursor, str) or len(cursor) != 32 or cursor not in self.cursors:
                raise Failure("invalid_cursor")
            offset = self.cursors[cursor]
        # Keep ample room for the response envelope under the 128 KiB line ceiling.
        import json
        page = []
        for item in self.characteristics[offset:offset + limit]:
            if len(json.dumps(page + [item], ensure_ascii=False).encode("utf-8")) > 120000:
                break
            page.append(item)
        next_offset = offset + len(page)
        next_cursor = None
        if next_offset < len(self.characteristics):
            next_cursor = secrets.token_hex(16)
            if len(self.cursors) >= 1024:
                raise Failure("cursor_limit")
            self.cursors[next_cursor] = next_offset
        return {"generation": self.generation, "characteristics": page, "cursor": next_cursor}

    async def pair(self, parameters, timeout_ms, request_id):
        if not self.ready or self.closed or self.terminal:
            raise Failure(self.terminal or "disconnected")
        if self.agent is not None:
            raise Failure("busy")
        from pairing import PairingAgent
        self.agent = PairingAgent(self, request_id, timeout_ms)
        try:
            return await self.agent.pair(parameters)
        finally:
            self.agent = None

    def agent_reply(self, parameters):
        if self.agent is None:
            raise Failure("pairing_rejected")
        self.agent.reply(parameters)

    async def close(self):
        if self.closed:
            return
        self.closed = True
        deadline = self.cleanup_deadline or time.monotonic() + 0.8
        if self.bus is not None:
            try:
                await self.notifications.close(deadline)
                if self.agent is not None:
                    await self.agent.close(deadline)
                if self.link_owned and self.device_path is not None and self.bluez_owner is not None:
                    await asyncio.wait_for(self.bus.call(self.bluez_owner, self.device_path, DEVICE, "Disconnect", "", []), max(deadline - time.monotonic(), 0.001))
            except Exception:
                pass
            finally:
                if self.listener_installed:
                    self.bus.unlisten(self.on_signal)
                self.bus.disconnect()
                if self.disconnect_task is not None:
                    self.disconnect_task.cancel()
                    await asyncio.gather(self.disconnect_task, return_exceptions=True)
                self.listener_installed = False
                self.link_owned = False
                self.cursors.clear()
                self.characteristics.clear()
                self.ready = False
