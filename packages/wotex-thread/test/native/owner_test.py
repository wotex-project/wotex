"""WTH-S03/WTH-C07/WTH-V04: real Linux SDK ownership and injected process faults."""
import fcntl
import json
import os
from pathlib import Path
import selectors
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest

REVISION = "5c8c318627954c99cd1a957a290bbd4b1027d04b"
HOST, RCP = map(Path, sys.argv[1:3])
if len(sys.argv) != 3 or not all(p.is_absolute() and p.is_file() for p in (HOST, RCP)):
    raise SystemExit("requires absolute built host and simulated RCP paths")
sys.argv = sys.argv[:1]


def descendants(pid):
    result = set()
    pending = [pid]
    while pending:
        parent = pending.pop()
        try:
            children = Path(f"/proc/{parent}/task/{parent}/children").read_text().split()
        except FileNotFoundError:
            continue
        for child in map(int, children):
            if child not in result:
                result.add(child)
                pending.append(child)
    return result


def eventually(predicate, timeout=2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.005)
    raise AssertionError("bounded condition did not complete")


class Host:
    def __init__(self):
        self.process = subprocess.Popen([str(HOST)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = bytearray()
        self.counter = 0
        self.children = set()
        assert self.receive() == dict(version=1, event="ready", backend="openthread", revision=REVISION)

    def receive(self, timeout=5):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            assert self.selector.select(max(0, deadline-time.monotonic())), "missing framed response"
            data = os.read(self.process.stdout.fileno(), 4096)
            assert data, "truncated/missing framed response"
            self.buffer.extend(data)
            assert len(self.buffer) <= 131072
        line, _, remainder = self.buffer.partition(b"\n")
        self.buffer = bytearray(remainder)
        return json.loads(line)

    def submit(self, operation, parameters=None):
        self.counter += 1
        identifier = f"request-{self.counter}"
        frame = dict(version=1, id=identifier, operation=operation,
                     parameters={} if parameters is None else parameters, timeout_ms=5000)
        self.process.stdin.write(json.dumps(frame).encode() + b"\n")
        return identifier

    def call(self, operation, parameters=None):
        identifier = self.submit(operation, parameters)
        result = self.receive()
        assert result["id"] == identifier and result["version"] == 1
        assert set(result) == {"id", "version", "ok", "result" if result["ok"] else "error"}
        self.children.update(descendants(self.process.pid))
        return result

    def finish(self, expected=None):
        self.children.update(descendants(self.process.pid))
        if not self.process.stdin.closed:
            self.process.stdin.close()
        started = time.monotonic()
        code = self.process.wait(timeout=1)
        assert time.monotonic() - started < 1
        if expected is not None:
            assert code == expected, (code, expected)
        assert self.process.stderr.read() == b""
        eventually(lambda: all(not Path(f"/proc/{pid}").exists() for pid in self.children))
        self.selector.close()
        self.process.stdout.close()
        self.process.stderr.close()
        return code


class Ownership(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="wotex-thread-owner-")
        self.root = Path(self.workspace.name)
        self.hosts = []
        self.node = 1

    def tearDown(self):
        for host in self.hosts:
            if host.process.poll() is None:
                host.finish()
        self.workspace.cleanup()

    def host(self):
        host = Host()
        self.hosts.append(host)
        return host

    def config(self, **changes):
        self.node += 1
        config = dict(radio_url=f"spinel+hdlc+forkpty://{RCP}?forkpty-arg={self.node % 30 + 1}",
                      interface=f"wth{self.node}", storage_path=str(self.root / f"store{self.node}"),
                      storage_mode="create_new", allow_network_creation=False)
        config.update(changes)
        return config

    def open(self, host, config):
        result = host.call("open", config)
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["result"], dict(role="disabled", network_name="OpenThread", rloc16=None,
                                              ipv6_enabled=False, thread_enabled=False, generation=1))
        self.assertGreaterEqual(len(descendants(host.process.pid)), 2)
        return result["result"]

    def test_WTH_S03_V04_real_sdk_reads_close_and_storage_reopen(self):
        host = self.host()
        config = self.config()
        state = self.open(host, config)
        self.assertEqual(host.call("inspect")["result"], state)
        self.assertEqual(host.call("state")["result"], "disabled")
        self.assertEqual(host.call("network_name")["result"], "OpenThread")
        self.assertIsNone(host.call("rloc16")["result"])
        self.assertIn(REVISION, host.call("version")["result"])
        store = Path(config["storage_path"])
        before = {p.name: p.read_bytes() for p in store.iterdir() if p.name != ".wotex-lock"}
        self.assertIn("settings.data", before)
        self.assertTrue(all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in store.iterdir()))
        self.assertIsNone(host.call("close")["result"])
        host.finish(0)
        self.assertNotIn(config["interface"], {name for _, name in socket.if_nameindex()})
        self.assertEqual(before, {p.name: p.read_bytes() for p in store.iterdir() if p.name != ".wotex-lock"})
        config["storage_mode"] = "open_existing"
        reopened = self.host()
        self.open(reopened, config)
        self.assertIsNone(reopened.call("close")["result"])
        reopened.finish(0)

    def test_WTH_S03_V04_competing_storage_and_interface_preserve_original_owner(self):
        first = self.host()
        config = self.config()
        state = self.open(first, config)
        for changes, code in ((dict(interface="wthother", storage_mode="open_existing"), "storage_unavailable"),
                              (dict(storage_path=str(self.root / "other")), "interface_in_use")):
            other = self.host()
            self.assertEqual(other.call("open", dict(config, **changes))["error"], {"code": code})
            other.finish(0)
            self.assertEqual(first.call("inspect")["result"], state)
        first.finish(0)
        self.assertNotIn(config["interface"], {name for _, name in socket.if_nameindex()})

    def test_WTH_C07_invalid_configuration_acquires_no_store(self):
        host = self.host()
        for changes in (dict(radio_url="spinel+hdlc+forkpty:///?forkpty-arg=1"),
                        dict(radio_url="spinel+hdlc+uart:///tmp/radio#fragment"),
                        dict(interface="bad/name"), dict(storage_path="/"),
                        dict(storage_path="/tmp/secret\nvalue"), dict(allow_network_creation=1),
                        dict(storage_mode="default"), dict(extra="canary")):
            config = self.config(**changes)
            self.assertEqual(host.call("open", config)["error"], {"code": "invalid_request"})
        self.assertEqual(list(self.root.iterdir()), [])
        self.assertEqual(host.call("inspect")["error"], {"code": "not_open"})
        self.assertEqual(host.call("unrecognized")["error"], {"code": "not_supported"})
        host.finish(0)

    def test_WTH_S03_existing_settings_permissions_links_rejected_without_mutation(self):
        for filename in ("settings.data", "settings.Swap"):
            for kind in ("symlink", "hardlink", "permissions", "directory"):
                host = self.host()
                config = self.config(storage_mode="open_existing")
                store = Path(config["storage_path"])
                store.mkdir(mode=0o700)
                outside = self.root / f"outside-{self.node}"
                outside.write_bytes(b"canary")
                outside.chmod(0o600)
                entry = store / filename
                if kind == "symlink": entry.symlink_to(outside)
                elif kind == "hardlink": os.link(outside, entry)
                elif kind == "permissions": entry.write_bytes(b"canary"); entry.chmod(0o644)
                else: entry.mkdir(mode=0o700)
                self.assertEqual(host.call("open", config)["error"], {"code": "storage_unavailable"})
                self.assertEqual(outside.read_bytes(), b"canary")
                self.assertEqual(len(descendants(host.process.pid)), 1)
                host.finish(0)

    def test_WTH_C07_eof_malformed_fragment_and_large_frame(self):
        for payload in (b'{"version":', b'{"version":1,"version":1}\n', b'x' * 131073 + b'\n'):
            host = self.host()
            try: host.process.stdin.write(payload)
            except BrokenPipeError: pass
            self.assertNotEqual(host.finish(), 0)

    def test_WTH_S03_V04_worker_and_radio_death_release_resources(self):
        for target in ("worker", "radio"):
            host = self.host()
            config = self.config()
            self.open(host, config)
            # Direct children identify the SDK worker; its sole child is the real simulated RCP.
            worker = int(Path(f"/proc/{host.process.pid}/task/{host.process.pid}/children").read_text().split()[0])
            radio = next(iter(descendants(worker)))
            host.children.update((worker, radio))
            os.kill(worker if target == "worker" else radio, signal.SIGKILL)
            self.assertNotEqual(host.finish(), 0)
            self.assertNotIn(config["interface"], {name for _, name in socket.if_nameindex()})
            with open(Path(config["storage_path"]) / ".wotex-lock", "rb") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_WTH_C07_blocked_sdk_startup_eof_and_term_reap_stubborn_radio(self):
        fake = self.root / "stalled-radio"
        fake.write_text("#!/usr/bin/python3\nimport signal,time\nsignal.signal(signal.SIGHUP,signal.SIG_IGN)\n"
                        "signal.signal(signal.SIGTERM,signal.SIG_IGN)\nwhile True: time.sleep(1)\n")
        fake.chmod(0o700)
        for method in ("eof", "term"):
            host = self.host()
            config = self.config(radio_url=f"spinel+hdlc+forkpty://{fake}")
            host.submit("open", config)
            eventually(lambda: len(descendants(host.process.pid)) >= 2)
            host.children.update(descendants(host.process.pid))
            if method == "term": os.kill(host.process.pid, signal.SIGTERM)
            host.finish()
            with open(Path(config["storage_path"]) / ".wotex-lock", "rb") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_WTH_C07_full_input_and_large_radio_logs_cannot_hide_owner_eof(self):
        fake = self.root / "noisy-radio"
        fake.write_text("#!/usr/bin/python3\nimport os,signal,time\n"
                        "signal.signal(signal.SIGHUP,signal.SIG_IGN)\n"
                        "signal.signal(signal.SIGTERM,signal.SIG_IGN)\n"
                        "os.write(2,b'private-canary-'*20000)\nwhile True: time.sleep(1)\n")
        fake.chmod(0o700)
        host = self.host()
        host.submit("open", self.config(radio_url=f"spinel+hdlc+forkpty://{fake}"))
        eventually(lambda: len(descendants(host.process.pid)) >= 2)
        host.children.update(descendants(host.process.pid))
        os.set_blocking(host.process.stdin.fileno(), False)
        frame = (json.dumps(dict(version=1, id="queued", operation="inspect", parameters={},
                                 timeout_ms=5000)) + "\n").encode()
        pending = frame * 4000
        accepted = 0
        deadline = time.monotonic() + 0.3
        while time.monotonic() < deadline and pending:
            try:
                count = os.write(host.process.stdin.fileno(), pending)
                pending = pending[count:]
                accepted += count
            except BlockingIOError:
                time.sleep(0.002)
            except BrokenPipeError:
                break
        self.assertGreater(accepted, 131072)
        host.finish()

    def test_WTH_S03_V04_one_hundred_owned_sdk_cycles_leave_no_process_or_interface(self):
        original = {name for _, name in socket.if_nameindex()}
        for _ in range(100):
            host = self.host()
            config = self.config()
            self.open(host, config)
            self.assertIsNone(host.call("close")["result"])
            host.finish(0)
        self.assertEqual({name for _, name in socket.if_nameindex()}, original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
