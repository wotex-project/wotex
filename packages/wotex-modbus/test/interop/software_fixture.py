"""Build and run the explicitly owned Linux software peer; no ambient target fallback."""

import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PIN = "9af6c16074df566551bca0a7c37443e48f216289"
ARCHIVE_SHA = "5d0f56cdd9f4f4bc6863dcac6bc9bdc7ea862566aefa29eef2f1bf649cc1ea3a"
FORMAT = "wotex.modbus.software@1"
INPUTS = ["test/interop/libmodbus/server.c", "test/interop/libmodbus/Dockerfile"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, text=True, **kwargs)


def capture(argv):
    return run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()


def write_json(path, value):
    temporary = path.with_suffix(".temporary")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def fetch(url, destination):
    with urllib.request.urlopen(url, timeout=30) as source, destination.open("wb") as output:
        shutil.copyfileobj(source, output)


def subject():
    identity = source_identity(ROOT)
    identity["inputs"] = {name: digest(ROOT / name) for name in INPUTS}
    identity["dependencies"] = {
        name: source_identity(ROOT.parent / name)
        for name in ["wotex", "wotex-runtime"] if (ROOT.parent / name).is_dir()
    } if os.environ.get("WOTEX_PATH_DEPS") == "1" else {}
    return identity


def source_identity(root):
    names = {p.relative_to(root).as_posix(): digest(p)
             for pattern in ["lib/**/*.ex", "test/**/*.ex", "test/**/*.exs", "test/**/*.py",
                             "test/**/*.sh", "test/**/*.c", "test/**/Dockerfile", "bin/*",
                             "docs/specs/fixtures/*.json", "mix.exs", "mix.lock"]
             for p in root.glob(pattern) if p.is_file()}
    canonical = json.dumps(names, sort_keys=True, separators=(",", ":")).encode()
    commit = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                            check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return {"commit": commit.stdout.strip() if commit.returncode == 0 else None,
            "source_sha256": hashlib.sha256(canonical).hexdigest(), "source_files_sha256": names}


def verify(workspace, manifest):
    if manifest.get("format") != FORMAT or manifest.get("source_commit") != PIN:
        raise ValueError("workspace is not a matching Modbus software manifest")
    if manifest.get("inputs") != subject()["inputs"]:
        raise ValueError("fixture inputs changed; build in a new disposable workspace")
    if digest(workspace / "source.tar.gz") != ARCHIVE_SHA:
        raise ValueError("pinned source archive hash mismatch")
    for name, expected in manifest.get("files", {}).items():
        if digest(workspace / name) != expected:
            raise ValueError("workspace file hash mismatch: " + name)
    if manifest.get("status") == "ready":
        identity = capture(["docker", "image", "inspect", manifest["image_id"], "--format", "{{.Id}}"])
        if identity != manifest["image_id"]:
            raise ValueError("peer image identity mismatch")


def audit(workspace):
    findings = {
        843: "Windows receive-timeout path; the isolated peer runs Linux and the library uses BEAM TCP.",
        848: "Test-server request framing; only validated native-client requests enter this peer. Malformed responses use a separate owned BEAM fixture.",
        867: "Test-server MBAP/trailing-request handling; library response framing is independently asserted and closes on mismatch.",
        868: "FC22 client confirmation; FC22 is outside the eight-function profile and libmodbus is used only as a server.",
    }
    records = []
    for number, scope in findings.items():
        url = f"https://api.github.com/repos/stephane/libmodbus/issues/{number}"
        path = workspace / f"upstream-issue-{number}.json"
        fetch(url, path)
        data = json.loads(path.read_text())
        if data.get("number") != number:
            raise ValueError("upstream audit response identity mismatch")
        records.append({"url": data["html_url"], "title": data["title"], "state": data["state"],
                        "response_sha256": digest(path), "scope": scope})
    result = {"checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "production_dependency": False, "source_commit": PIN, "version": "3.1.12",
              "findings": records,
              "containment": ["loopback-only published port", "owned disposable Linux container",
                              "finite indication and byte timeouts", "strict independent malformed-response tests"],
              "claim": "Scoped fixture audit; no assertion that upstream libmodbus is vulnerability-free."}
    write_json(workspace / "native-audit.json", result)


def build(workspace):
    manifest_path = workspace / "manifest.json"
    if workspace.exists() and any(workspace.iterdir()):
        if not manifest_path.is_file():
            raise ValueError("refusing unrelated nonempty workspace")
        manifest = json.loads(manifest_path.read_text())
        verify(workspace, manifest)
        if manifest["status"] == "ready":
            print("verified existing peer", manifest["image_id"], flush=True)
            return
    else:
        workspace.mkdir(parents=True, exist_ok=True)
        fetch(f"https://codeload.github.com/stephane/libmodbus/tar.gz/{PIN}", workspace / "source.tar.gz")
        if digest(workspace / "source.tar.gz") != ARCHIVE_SHA:
            raise ValueError("pinned source archive hash mismatch")
        manifest = {"format": FORMAT, "status": "building", "source_commit": PIN,
                    "source_archive_sha256": ARCHIVE_SHA, "inputs": subject()["inputs"]}
        write_json(manifest_path, manifest)
    context = workspace / "context"
    context.mkdir(exist_ok=True)
    shutil.copyfile(workspace / "source.tar.gz", context / "source.tar.gz")
    for name in INPUTS:
        shutil.copyfile(ROOT / name, context / Path(name).name)
    audit(workspace)
    image_file = workspace / "image.id"
    image_file.unlink(missing_ok=True)
    with (workspace / "build.log").open("w") as output:
        run(["docker", "build", "--progress=plain", "--iidfile", str(image_file), str(context)],
            stdout=output, stderr=subprocess.STDOUT)
    image_id = image_file.read_text().strip()
    native = capture(["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/sh", image_id,
                      "-c", "cc --version; dpkg-query -W; cat /build/binaries.sha256; /usr/local/bin/fixture --version"])
    (workspace / "native-toolchain.txt").write_text(native + "\n")
    inspected = json.loads(capture(["docker", "image", "inspect", image_id]))[0]
    manifest.update(status="ready", image_id=image_id, architecture=inspected["Architecture"],
                    operating_system=inspected["Os"], compiler_flags="-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer",
                    base_image="debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171",
                    files={name: digest(workspace / name) for name in
                           ["native-toolchain.txt", "native-audit.json", "source.tar.gz"]})
    write_json(manifest_path, manifest)
    print("built verified software peer", image_id, flush=True)


def wait_ready(container):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        status = json.loads(capture(["docker", "inspect", container]))[0]["State"]
        if not status["Running"]:
            raise RuntimeError("peer exited before readiness: " + capture(["docker", "logs", container]))
        output = capture(["docker", "logs", container])
        if '{"event":"ready","port":1502}' in output:
            return
        time.sleep(0.1)
    raise TimeoutError("peer readiness timeout")


def cleanup_peer(container, lane, evidence):
    errors = []
    try:
        run(["docker", "stop", "--time", "2", container], stdout=subprocess.PIPE)
        state = json.loads(capture(["docker", "inspect", container]))[0]["State"]
        logs = subprocess.run(["docker", "logs", container], text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, check=True).stdout
        (lane / "peer.log").write_text(logs)
        events = [json.loads(line) for line in logs.splitlines() if line.startswith("{")]
        cleanup = [event for event in events if event.get("event") == "cleanup"]
        evidence["peer_cleanup"] = cleanup
        evidence["peer_exit_code"] = state["ExitCode"]
        sanitizer_clean = not any(text in logs for text in
                                  ["ERROR: AddressSanitizer", "runtime error:", "LeakSanitizer", "DEADLYSIGNAL"])
        evidence["native_sanitizers"] = {"address": sanitizer_clean, "undefined": sanitizer_clean, "leak": sanitizer_clean}
        if (state["ExitCode"] != 0 or not sanitizer_clean or len(cleanup) != 1 or
                any(cleanup[0][key] for key in ["open_sockets", "contexts", "mappings", "result"])):
            errors.append("peer exit, sanitizer, or resource cleanup assertion failed")
    except Exception as error:
        errors.append(type(error).__name__ + ": " + str(error))
    finally:
        try:
            run(["docker", "rm", "--force", container], stdout=subprocess.PIPE)
            remaining = capture(["docker", "ps", "--all", "--quiet", "--no-trunc", "--filter", "id=" + container])
            if remaining:
                raise RuntimeError("owned peer container remains after removal")
            evidence["owned_containers_after"] = 0
        except Exception as error:
            errors.append(type(error).__name__ + ": " + str(error))
    if errors:
        evidence["cleanup_errors"] = errors
        evidence["status"] = "failed"


def execute(workspace):
    manifest = json.loads((workspace / "manifest.json").read_text())
    verify(workspace, manifest)
    if manifest["status"] != "ready":
        raise ValueError("peer build is incomplete")
    token = str(time.time_ns())
    lane = workspace / ("run-" + token)
    lane.mkdir()
    container = None
    test_process = None
    evidence = {"format": FORMAT, "subject": subject(), "status": "failed", "fixture_image": manifest["image_id"],
                "manifest_sha256": digest(workspace / "manifest.json"), "dependency_mode": "path" if os.environ.get("WOTEX_PATH_DEPS") == "1" else "released",
                "fixture_sha256": {str(p.relative_to(ROOT)): digest(p) for p in (ROOT / "docs/specs/fixtures").glob("*.json")},
                "lanes": ["independent-stack", "malformed-peer", "injected-contract"],
                "subscription_cycles": {"status": "inapplicable", "reason": "profile declares no subscriptions"}}
    try:
        container = capture(["docker", "run", "-d", "--cidfile", str(lane / "owned-container.id"),
                             "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges",
                             "--pids-limit=32", "--memory=256m", "-p", "127.0.0.1::1502", manifest["image_id"]])
        wait_ready(container)
        evidence["native_memory_before"] = json.loads(capture(["docker", "stats", "--no-stream", "--format", "{{json .}}", container]))
        port = capture(["docker", "port", container, "1502/tcp"])
        if not port.startswith("127.0.0.1:") or "\n" in port:
            raise ValueError("peer port is not a unique loopback endpoint")
        env = os.environ.copy()
        env.update(WOTEX_REQUIRE_SOFTWARE="1", WOTEX_MODBUS_INTEROP_HOST="127.0.0.1",
                   WOTEX_MODBUS_INTEROP_PORT=port.split(":")[1], WOTEX_MODBUS_SOFTWARE_EVIDENCE=str(lane))
        evidence["toolchain"] = capture(["elixir", "--version"])
        evidence["toolchain_paths"] = {name: str(Path(shutil.which(name)).resolve()) for name in ["elixir", "erl", "mix", "docker"]}
        evidence["command"] = ["mix", "test", "--include", "interop", "--include", "software", "--exclude", "hardware", "--seed", "731942"]
        with (lane / "tests.log").open("w") as output:
            test_process = subprocess.Popen(evidence["command"], cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            test_exit = test_process.wait(timeout=180)
        if test_exit != 0:
            raise RuntimeError("software tests failed; inspect " + str(lane / "tests.log"))
        evidence["native_memory_after"] = json.loads(capture(["docker", "stats", "--no-stream", "--format", "{{json .}}", container]))
        for name in ["sequential", "cycles", "concurrency", "failures"]:
            evidence[name] = json.loads((lane / (name + ".json")).read_text())
        evidence["status"] = "passed"
    except BaseException as error:
        evidence["failure"] = {"type": type(error).__name__, "message": str(error)}
        raise
    finally:
        try:
            if test_process and test_process.poll() is None:
                os.killpg(test_process.pid, signal.SIGTERM)
                try:
                    test_process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(test_process.pid, signal.SIGKILL)
                    test_process.wait(timeout=2)
        except Exception as error:
            evidence["test_cleanup_error"] = type(error).__name__ + ": " + str(error)
            evidence["status"] = "failed"
        if not container and (lane / "owned-container.id").is_file():
            container = (lane / "owned-container.id").read_text().strip()
        if container:
            cleanup_peer(container, lane, evidence)
        evidence["logs_sha256"] = {p.name: digest(p) for p in lane.glob("*.log")}
        write_json(lane / "result.json", evidence)
        print("software evidence", lane / "result.json", flush=True)
    if evidence["status"] != "passed":
        raise RuntimeError("software peer or sanitizer cleanup failed")


def main():
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt("software fixture interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    if len(sys.argv) != 3 or sys.argv[1] not in ["build", "run"]:
        raise ValueError("usage: software_fixture.py build|run /absolute/disposable/workspace")
    raw = Path(sys.argv[2])
    if not raw.is_absolute() or raw.is_symlink():
        raise ValueError("workspace must be an absolute non-symlink path")
    workspace = raw.resolve()
    if workspace == ROOT or ROOT in workspace.parents:
        raise ValueError("workspace must be outside the source package")
    for tool in ["docker", "git"] + (["mix", "elixir"] if sys.argv[1] == "run" else []):
        if not shutil.which(tool):
            raise RuntimeError("required software tool missing: " + tool)
    lock = workspace.parent / (workspace.name + ".lock")
    lock.mkdir()
    try:
        (build if sys.argv[1] == "build" else execute)(workspace)
    finally:
        lock.rmdir()


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print("software fixture failed:", error, file=sys.stderr)
        sys.exit(1)
