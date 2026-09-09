"""Public BLE/Runtime virtual GATT runner; stress completion is a separate gate."""

import contextlib
import fcntl
import json
import re
import shutil
import subprocess
import sys
import urllib.request
import uuid

import virtual_machine as native

SCHEMA = "wotex_ble_public_gatt_v1"
PACKAGES = ("wotex", "wotex-runtime", "wotex-ble")
TOOLS = {
    "hex-source.tar.gz": (
        "https://codeload.github.com/hexpm/hex/tar.gz/refs/tags/v2.5.1",
        "bdd6ef2015aa6e50a1c21212e098e8cbe7317da65f067955d154d890532742ae",
    ),
    "rebar-source.tar.gz": (
        "https://codeload.github.com/erlang/rebar3/tar.gz/refs/tags/3.27.0",
        "985cae6e957334cfa549190b9f5efb9185c184a18fc181c87b8dde096ba79f38",
    ),
}
ARTIFACTS = {
    "rootfs.tar",
    "rootfs.raw",
    "native-build.json",
    "context/hex-source.tar.gz",
    "context/rebar-source.tar.gz",
}


def sources():
    result = {}
    for package in PACKAGES:
        root = native.SOURCE.parent / package
        if not (root / "mix.exs").is_file() or not (root / "mix.lock").is_file():
            raise ValueError("Required sibling package source is missing: " + package)
        selected = [root / "mix.exs", root / "mix.lock"]
        for directory in ("config", "lib", "priv", "test"):
            selected += [
                path
                for path in (root / directory).rglob("*")
                if path.is_file()
                and not {"__pycache__", "plts", "_build", "deps"}.intersection(
                    path.parts
                )
            ]
        for path in sorted(selected):
            if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
                raise ValueError("Software fixture sources must be regular owned files")
            result[package + "/" + str(path.relative_to(root))] = {
                "sha256": native.digest(path),
                "mode": path.stat().st_mode & 0o777,
            }
    return result


@contextlib.contextmanager
def owned(path, expected):
    file = path / "manifest.json"
    if file.exists():
        if file.is_symlink():
            raise ValueError("Manifest must not be a symlink")
        manifest = json.loads(file.read_text())
        if manifest.get("schema") != SCHEMA or manifest.get("inputs") != expected:
            raise ValueError(
                "Workspace does not match the current software source hashes"
            )
    else:
        if any(path.iterdir()):
            raise ValueError("Refusing unrelated nonempty workspace")
        manifest = {"schema": SCHEMA, "inputs": expected, "phase": "building"}
        native.save(file, manifest)
    lock = path / "fixture.lock"
    if lock.is_symlink():
        raise ValueError("Lock must not be a symlink")
    with lock.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield manifest


def fetch(path, url, expected):
    if path.exists():
        if path.is_symlink() or native.digest(path) != expected:
            raise ValueError("Build tool archive differs from its source pin")
        return
    temporary = path.with_name(path.name + ".download-" + uuid.uuid4().hex)
    try:
        with (
            urllib.request.urlopen(url, timeout=60) as response,
            temporary.open("xb") as out,
        ):
            total = 0
            while block := response.read(1024 * 1024):
                total += len(block)
                if total > 32 * 1024 * 1024:
                    raise ValueError("Build tool archive exceeds 32 MiB")
                out.write(block)
        if native.digest(temporary) != expected:
            raise ValueError("Build tool source hash mismatch")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def verify(path, manifest):
    if manifest.get("phase") != "ready" or set(manifest["artifacts"]) != ARTIFACTS:
        raise ValueError("Public fixture build is incomplete")
    for relative, expected in manifest["artifacts"].items():
        artifact = path / relative
        if (
            artifact.is_symlink()
            or not artifact.resolve().is_relative_to(path)
            or not artifact.is_file()
            or native.digest(artifact) != expected
        ):
            raise ValueError("Public fixture artifact differs: " + relative)
    identifier = manifest["image_id"]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", identifier):
        raise ValueError("Invalid immutable image identifier")
    image = json.loads(native.output("docker", "image", "inspect", identifier))[0]
    if (image["Id"], image["Architecture"], image["Os"]) != (
        identifier,
        "arm64",
        "linux",
    ):
        raise ValueError("Unexpected guest image identity or platform")
    return identifier


def preserve_base_alias(path, manifest, identifier):
    alias = manifest.get("native_base_alias")
    if alias is None:
        alias = "wotex-ble-owned-native-base:" + uuid.uuid4().hex
        native.run("docker", "tag", identifier, alias)
        manifest["native_base_alias"] = alias
        manifest["native_base_image_id"] = identifier
        native.save(path / "manifest.json", manifest)
    if (
        not isinstance(alias, str)
        or not re.fullmatch(r"wotex-ble-owned-native-base:[0-9a-f]{32}", alias)
        or manifest.get("native_base_image_id") != identifier
        or native.output("docker", "image", "inspect", alias, "--format", "{{.Id}}")
        != identifier
    ):
        raise ValueError("Owned native build alias has changed identity")
    # Keep this owned build artifact: deleting an image's last tag can remove
    # the immutable native base required by the persisted source manifest.
    return alias


def build(path, manifest):
    if manifest.get("phase") == "ready":
        verify(path, manifest)
        return
    native_path = native.workspace(str(path / "native"))
    with native.owned_workspace(native_path, native.inputs()) as base:
        native.build(native_path, base)
        base_identifier = native.verify(native_path, base)
    context = path / "context"
    context.mkdir(exist_ok=True)
    for name, (url, sha256) in TOOLS.items():
        fetch(context / name, url, sha256)
    for relative, metadata in manifest["inputs"].items():
        source = native.SOURCE.parent / relative
        destination = context / "source" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        destination.chmod(metadata["mode"])
        if native.digest(destination) != metadata["sha256"]:
            raise ValueError("Package source changed while copying: " + relative)
    shutil.copyfile(native.ASSETS / "Public.Dockerfile", context / "Dockerfile")
    alias = preserve_base_alias(path, manifest, base_identifier)
    with (path / "build.log").open("w") as log:
        native.run(
            "docker",
            "build",
            "--platform",
            "linux/arm64",
            "--build-arg",
            "FIXTURE_IMAGE=" + alias,
            "--iidfile",
            str(path / "image.id"),
            str(context),
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=1800,
        )
    identifier = native.output(
        "docker",
        "image",
        "inspect",
        (path / "image.id").read_text().strip(),
        "--format",
        "{{.Id}}",
    )
    shutil.copyfile(native_path / "native-build.json", path / "native-build.json")
    name = "wbl-public-export-" + uuid.uuid4().hex[:16]
    native.run(
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
        native.run("docker", "export", "--output", str(path / "rootfs.tar"), name)
    finally:
        native.run("docker", "rm", "-f", name, stdout=subprocess.DEVNULL)
    with (path / "filesystem.log").open("w") as log:
        native.run(
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            "--mount",
            "type=bind,src=" + str(path) + ",target=/work",
            identifier,
            "bash",
            "/opt/wbl/fixture/make_filesystem.sh",
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
    if sources() != manifest["inputs"]:
        raise ValueError("Package sources changed during the fixture build")
    manifest.update(
        phase="ready",
        image_id=identifier,
        artifacts={name: native.digest(path / name) for name in sorted(ARTIFACTS)},
    )
    native.save(path / "manifest.json", manifest)
    print("Built public GATT fixture: " + str(path / "manifest.json"))


def execute(path, manifest):
    identifier = verify(path, manifest)
    result = native.execute_image(path, identifier, manifest["inputs"], timeout=600)
    for lane in ("latest", "lower"):
        report = json.loads((result / ("public-peer-" + lane + ".json")).read_text())
        if report.get("clean") is not True:
            raise RuntimeError("Public GATT fixture cleanup did not pass: " + lane)
        cases = json.loads((result / ("public-exunit-" + lane + ".json")).read_text())
        if cases.get("counts") != {"passed": 10} or len(cases.get("cases", [])) != 10:
            raise RuntimeError(
                "Required public GATT cases are absent or failed: " + lane
            )
    print("Public native and Runtime GATT assertions passed: " + str(result))


def main(arguments):
    if len(arguments) != 2 or arguments[0] not in ("build", "run"):
        raise ValueError(
            "Expected build|run and exactly one absolute disposable workspace"
        )
    path = native.workspace(arguments[1])
    expected = sources()
    with owned(path, expected) as manifest:
        if arguments[0] == "build":
            build(path, manifest)
        else:
            execute(path, manifest)


if __name__ == "__main__":
    main(sys.argv[1:])
