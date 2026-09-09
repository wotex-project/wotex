#!/usr/bin/env python3
"""Run loopback UDP/DTLS acceptance against a verified pinned libcoap executable."""

import argparse
import base64
import hashlib
import json
import os
import re
from pathlib import Path
import socket
import subprocess
import time

REVISION = "7cf7465b784baded4de183290c547d582becfd28"
PKI_PROFILES = ["server", "wrong-san", "expired", "wrong-ku", "wrong-eku", "critical",
                "cn-only", "wildcard", "revoked"]


def pki_material(source, output, profile):
    fixtures = source / "test/fixtures/dtls_pki"
    manifest = json.loads((fixtures / "manifest.json").read_text())
    for name, expected in manifest["files"].items():
        if hashlib.sha256((fixtures / name).read_bytes()).hexdigest() != expected:
            raise RuntimeError("PKI fixture does not match its checked-in manifest")
    for name, label, target in [(profile + ".der", "CERTIFICATE", "server.pem"),
                                (profile + "-key.der", "RSA PRIVATE KEY", "server-key.pem"),
                                ("root.der", "CERTIFICATE", "root.pem")]:
        encoded = base64.b64encode((fixtures / name).read_bytes()).decode("ascii")
        lines = [encoded[index:index + 64] for index in range(0, len(encoded), 64)]
        (output / target).write_text("-----BEGIN " + label + "-----\n" +
                                     "\n".join(lines) + "\n-----END " + label + "-----\n")
    return hashlib.sha256((fixtures / "manifest.json").read_bytes()).hexdigest()


def reserve_ports():
    for _ in range(30):
        first = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        second = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            first.bind(("127.0.0.1", 0))
            port = first.getsockname()[1]
            if port == 65535:
                continue
            second.bind(("127.0.0.1", port + 1))
            return port
        except OSError:
            continue
        finally:
            first.close()
            second.close()
    raise RuntimeError("could not reserve two loopback ports")


def free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def run(options):
    manifest = json.loads(options.manifest.read_text())
    executable = Path(manifest["executable"])
    if (manifest["revision"] != REVISION or
            hashlib.sha256(executable.read_bytes()).hexdigest() != manifest["executable_sha256"]):
        raise RuntimeError("peer executable does not match the pinned manifest")
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parents[3]
    pki_sha = pki_material(source, output, options.pki_profile)
    identities = output / "test-identities.csv"
    identities.write_text("fixture-hint,client,fixture-key-12345\n")
    port = reserve_ports()
    command = [str(executable), "-A", "127.0.0.1", "-p", str(port), "-d", "32", "-e",
               "-h", "fixture-hint", "-k", "fallback-key-4567", "-i", str(identities),
               "-c", str(output / "server.pem"), "-j", str(output / "server-key.pem"),
               "-C", str(output / "root.pem"), "-v", "0", "-V", "0"]
    environment = os.environ.copy()
    environment.update(MIX_ENV="test", WOTEX_COAP_INTEROP_PORT=str(port),
                       WOTEX_COAP_DTLS_INTEROP_PORT=str(port + 1),
                       WOTEX_COAP_PKI_INTEROP_PROFILE=options.pki_profile)
    cases = (["test/interop/libcoap_test.exs", "test/interop/dtls_test.exs",
              "test/interop/dtls_pki_test.exs"] if options.pki_profile == "server" else
             ["test/interop/dtls_pki_rejection_test.exs"])
    tests = ["mix", "test", *cases, "--include", "interop", "--seed", "0"]
    files = sorted({*source.glob("lib/**/*.ex"), *source.glob("test/**/*.exs"),
                    *source.glob("test/interop/**/*.py"), *source.glob("test/fixtures/dtls_pki/*"),
                    source / "mix.exs", source / "mix.lock"})
    source_hash = hashlib.sha256()
    for path in files:
        source_hash.update(str(path.relative_to(source)).encode() + b"\0" + path.read_bytes() + b"\0")
    toolchain = subprocess.check_output(["elixir", "--version"], env=environment, text=True)
    status = None
    started = time.monotonic()
    with (output / "peer.log").open("w") as peer_log:
        peer = subprocess.Popen(command, cwd=output, stdout=peer_log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 5
            while free(port) or free(port + 1):
                if peer.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("DTLS peer failed readiness; inspect peer.log")
                time.sleep(0.01)
            with (output / "tests.log").open("w") as test_log:
                status = subprocess.run(tests, cwd=Path(__file__).resolve().parents[3],
                                        env=environment, stdout=test_log, stderr=subprocess.STDOUT,
                                        timeout=90, check=False).returncode
        finally:
            peer.terminate()
            try:
                peer.wait(timeout=3)
            except subprocess.TimeoutExpired:
                peer.kill()
                peer.wait(timeout=3)
            cleanup = {"peer_alive": int(peer.poll() is None),
                       "udp_ports_retained": int(not free(port)) + int(not free(port + 1))}
            evidence = {"schema": "wotex-coap-libcoap-result-v1", "peer": manifest,
                        "pki_profile": options.pki_profile, "pki_manifest_sha256": pki_sha,
                        "peer_command": command,
                        "source_sha256": source_hash.hexdigest(), "toolchain": toolchain,
                        "test_command": tests, "test_exit_status": status,
                        "elapsed_ms": round((time.monotonic() - started) * 1000),
                        "cleanup": cleanup, "peer_exit_status": peer.returncode,
                        "test_log_sha256": hashlib.sha256((output / "tests.log").read_bytes()).hexdigest()
                        if (output / "tests.log").exists() else None}
            (output / "result.json").write_text(json.dumps(evidence, indent=2) + "\n")
    peer_text = (output / "peer.log").read_text(errors="replace")
    native_failure = bool(re.search(r"AddressSanitizer|LeakSanitizer|runtime error:", peer_text))
    evidence["native_diagnostic_failure"] = native_failure
    (output / "result.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(output / "result.json")
    if status != 0 or any(cleanup.values()) or peer.returncode != 0 or native_failure:
        raise RuntimeError("interoperability or cleanup failed; inspect result.json and tests.log")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pki-profile", choices=PKI_PROFILES, default="server")
    run(parser.parse_args())


if __name__ == "__main__":
    main()
