"""Build/run an owned ARM64 virtual-HCI fixture; no host Bluetooth access.

Explicit entry point: python3 test/interop/virtual_machine.py build|run /absolute/workspace
This native lane does not claim completion of the public BEAM/Runtime matrix.
"""

import contextlib
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request
import uuid

SCHEMA = "wotex_ble_virtual_v1"
BLUEZ_COMMIT = "2123ab772fbe97d1369fc9e179ea87c3469cf98f"
BLUEZ_ARCHIVE = "53a95c3dc9897f617b8bae0121d3f4c55c28a757bd48546c707bd2bbac45af0a"
SOURCE = Path(__file__).resolve().parents[2]
ASSETS = Path(__file__).resolve().parent / "virtual"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path, value):
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    with temporary.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
    temporary.replace(path)


def run(*arguments, **options):
    return subprocess.run(arguments, check=True, **options)


def output(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def inputs():
    selected = [Path(__file__).resolve()]
    selected += sorted(path for path in ASSETS.iterdir() if path.is_file())
    selected += sorted((SOURCE / "priv/bluez").glob("*.py"))
    selected.append(SOURCE / "priv/bluez/requirements.txt")
    if any(path.is_symlink() for path in selected):
        raise ValueError("Fixture inputs must be regular files")
    return {str(path.relative_to(SOURCE)): digest(path) for path in selected}


def workspace(value):
    path = Path(value)
    if not path.is_absolute() or path.is_symlink():
        raise ValueError("Expected one absolute disposable directory, never a symlink")
    path = path.resolve()
    if path == SOURCE or path in SOURCE.parents or SOURCE in path.parents:
        raise ValueError("Fixture workspace must be outside the source repository")
    if path.exists() and not path.is_dir():
        raise ValueError("Fixture workspace is not a directory")
    path.mkdir(parents=True, exist_ok=True)
    return path


@contextlib.contextmanager
def owned_workspace(path, expected):
    manifest_path = path / "manifest.json"
    if manifest_path.exists():
        if manifest_path.is_symlink():
            raise ValueError("Manifest must not be a symlink")
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("schema") != SCHEMA or manifest.get("inputs") != expected:
            raise ValueError(
                "Workspace manifest does not match these fixture/library sources"
            )
    else:
        if any(path.iterdir()):
            raise ValueError("Refusing unrelated nonempty workspace")
        manifest = {
            "schema": SCHEMA,
            "phase": "building",
            "inputs": expected,
            "source": {"bluez_commit": BLUEZ_COMMIT, "archive_sha256": BLUEZ_ARCHIVE},
        }
        save(manifest_path, manifest)
    lock = path / "fixture.lock"
    if lock.is_symlink():
        raise ValueError("Lock must not be a symlink")
    with lock.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield manifest


def verify(path, manifest):
    if manifest.get("phase") != "ready":
        raise ValueError("Fixture build is incomplete")
    if set(manifest["artifacts"]) != {
        "context/bluez.tar.gz",
        "rootfs.tar",
        "rootfs.raw",
        "native-build.json",
    }:
        raise ValueError("Unexpected fixture artifact set")
    for relative, expected in manifest["artifacts"].items():
        target = path / relative
        if (
            target.is_symlink()
            or not target.resolve().is_relative_to(path)
            or not target.is_file()
            or digest(target) != expected
        ):
            raise ValueError("Fixture artifact differs: " + relative)
    identifier = manifest["image_id"]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", identifier):
        raise ValueError("Invalid immutable image identifier")
    inspected = json.loads(output("docker", "image", "inspect", identifier))[0]
    if (
        inspected["Id"] != identifier
        or inspected["Architecture"] != "arm64"
        or inspected["Os"] != "linux"
    ):
        raise ValueError("Wrong virtual-machine image")
    return identifier


def fetch_archive(destination):
    if not destination.exists():
        temporary = destination.with_name("bluez.download-" + uuid.uuid4().hex)
        try:
            url = "https://codeload.github.com/bluez/bluez/tar.gz/" + BLUEZ_COMMIT
            with (
                urllib.request.urlopen(url, timeout=60) as response,
                temporary.open("xb") as stream,
            ):
                total = 0
                while block := response.read(1024 * 1024):
                    total += len(block)
                    if total > 32 * 1024 * 1024:
                        raise ValueError(
                            "BlueZ source archive exceeds the declared bound"
                        )
                    stream.write(block)
            if digest(temporary) != BLUEZ_ARCHIVE:
                raise ValueError("BlueZ source archive hash mismatch")
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    if destination.is_symlink() or digest(destination) != BLUEZ_ARCHIVE:
        raise ValueError("BlueZ source archive hash mismatch")


def build(path, manifest):
    if manifest["phase"] == "ready":
        verify(path, manifest)
        print("Verified existing native virtual-controller fixture")
        return
    context = path / "context"
    if any(
        item.is_symlink() for item in (context, context / "virtual", context / "bluez")
    ):
        raise ValueError("Build context must not contain directory symlinks")
    context.mkdir(exist_ok=True)
    (context / "virtual").mkdir(exist_ok=True)
    (context / "bluez").mkdir(exist_ok=True)
    for relative in manifest["inputs"]:
        original = SOURCE / relative
        if original.parent == ASSETS:
            target = context / "virtual" / original.name
        elif original.parent == SOURCE / "priv/bluez":
            target = context / "bluez" / original.name
        else:
            continue
        if target.exists() and digest(target) != manifest["inputs"][relative]:
            raise ValueError("Existing build input differs: " + relative)
        shutil.copyfile(original, target)
    shutil.copyfile(ASSETS / "Dockerfile", context / "Dockerfile")
    fetch_archive(context / "bluez.tar.gz")
    with (path / "build.log").open("w") as log:
        run(
            "docker",
            "build",
            "--platform",
            "linux/arm64",
            "--iidfile",
            str(path / "image.id"),
            str(context),
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    identifier = (path / "image.id").read_text().strip()
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", identifier):
        raise ValueError("Build did not produce an immutable image identifier")
    inspected = json.loads(output("docker", "image", "inspect", identifier))[0]
    if inspected["Architecture"] != "arm64" or inspected["Os"] != "linux":
        raise ValueError("Build produced the wrong guest platform")
    identifier = inspected["Id"]
    native = json.loads(
        output(
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            identifier,
            "cat",
            "/opt/wbl/build.json",
        )
    )
    save(path / "native-build.json", native)
    name = "wbl-export-" + uuid.uuid4().hex[:16]
    run(
        "docker",
        "create",
        "--name",
        name,
        "--network",
        "none",
        identifier,
        stdout=subprocess.DEVNULL,
    )
    try:
        run("docker", "export", "--output", str(path / "rootfs.tar"), name)
    finally:
        run("docker", "rm", "-f", name, stdout=subprocess.DEVNULL)
    mount = "type=bind,src=" + str(path) + ",target=/work"
    with (path / "filesystem.log").open("w") as log:
        run(
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            "--mount",
            mount,
            identifier,
            "bash",
            "/opt/wbl/fixture/make_filesystem.sh",
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    manifest.update(
        phase="ready",
        image_id=identifier,
        artifacts={
            name: digest(path / name)
            for name in (
                "context/bluez.tar.gz",
                "rootfs.tar",
                "rootfs.raw",
                "native-build.json",
            )
        },
    )
    save(path / "manifest.json", manifest)
    print(
        "Built native virtual-controller fixture; manifest: "
        + str(path / "manifest.json")
    )


def execute(path, manifest):
    identifier = verify(path, manifest)
    return execute_image(path, identifier, manifest["inputs"])


def execute_image(path, identifier, source_inputs, timeout=240):
    """Run an already verified owned image; retain all native guest evidence."""
    result = path / ("run-" + uuid.uuid4().hex)
    result.mkdir()
    name = "wbl-vm-" + uuid.uuid4().hex[:16]
    mount = "type=bind,src=" + str(path) + ",target=/work"
    guest_directory = "/work/" + result.name
    completed = False
    stage = "overlay"
    try:
        run(
            "docker",
            "run",
            "--rm",
            "--name",
            name + "-disk",
            "--network",
            "none",
            "--mount",
            mount,
            identifier,
            "qemu-img",
            "create",
            "-f",
            "qcow2",
            "-F",
            "raw",
            "-b",
            "/work/rootfs.raw",
            guest_directory + "/disk.qcow2",
            stdout=subprocess.DEVNULL,
            timeout=30,
        )
        stage = "guest"
        with (result / "console.log").open("w") as log:
            run(
                "docker",
                "run",
                "--rm",
                "--name",
                name,
                "--network",
                "none",
                "--mount",
                mount,
                identifier,
                "qemu-system-aarch64",
                "-M",
                "virt-7.2",
                "-cpu",
                "cortex-a57",
                "-accel",
                "tcg",
                "-smp",
                "4",
                "-m",
                "2048",
                "-nographic",
                "-no-reboot",
                "-nic",
                "none",
                "-kernel",
                "/boot/vmlinuz-6.1.0-53-arm64",
                "-initrd",
                "/boot/initrd.img-6.1.0-53-arm64",
                "-append",
                "console=ttyAMA0 root=/dev/vda rw noresume init=/bootstrap.sh",
                "-drive",
                "file=" + guest_directory + "/disk.qcow2,format=qcow2,if=virtio",
                "-fsdev",
                "local,id=fixture,path=" + guest_directory + ",security_model=none",
                "-device",
                "virtio-9p-pci,fsdev=fixture,mount_tag=fixture",
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=timeout,
            )
        completed = True
    except BaseException as error:
        save(result / "failure.json", {"stage": stage, "error": type(error).__name__})
        raise
    finally:
        # --rm normally removes it. If timeout/interruption occurred, remove only
        # our unique container, and verify that no matching container survives.
        for owned_name in (name, name + "-disk"):
            matches = output(
                "docker", "ps", "-aq", "--filter", "name=^/" + owned_name + "$"
            )
            if matches:
                run("docker", "rm", "-f", owned_name, stdout=subprocess.DEVNULL)
            if output("docker", "ps", "-aq", "--filter", "name=^/" + owned_name + "$"):
                raise RuntimeError("Owned virtual-machine container survived cleanup")
        save(
            result / "host-cleanup.json",
            {"completed": completed, "containers_remaining": 0},
        )
    console = (result / "console.log").read_text()
    status = json.loads((result / "guest-result.json").read_text())
    if (
        status
        != {
            "result": 0,
            "owned_processes_remaining": 0,
            "virtual_controllers_remaining": 0,
        }
        or "Kernel panic" in console
    ):
        raise RuntimeError("Virtual GATT lane failed; evidence: " + str(result))
    report = json.loads((result / "native-result.json").read_text())
    if report.get("result") != "passed":
        raise RuntimeError("Native GATT assertions did not complete")
    save(
        result / "manifest.json",
        {
            "schema": SCHEMA,
            "image_id": identifier,
            "inputs": source_inputs,
            "artifacts": {
                item.name: digest(item)
                for item in result.iterdir()
                if item.is_file() and item.name != "disk.qcow2"
            },
        },
    )
    print("Native virtual-controller assertions passed; evidence: " + str(result))
    return result


def main(arguments):
    if len(arguments) != 2 or arguments[0] not in ("build", "run"):
        raise ValueError(
            "Usage: virtual_machine.py build|run /absolute/disposable/workspace"
        )
    path = workspace(arguments[1])
    with owned_workspace(path, inputs()) as manifest:
        if arguments[0] == "build":
            build(path, manifest)
        else:
            execute(path, manifest)


if __name__ == "__main__":
    main(sys.argv[1:])
