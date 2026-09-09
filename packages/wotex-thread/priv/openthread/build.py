#!/usr/bin/env python3
"""Build the pinned Linux SDK host explicitly: build.py [--sanitizers] /empty/workspace."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import urllib.request


SOURCE = Path(__file__).resolve().parent


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def tree_digest(path):
    value = hashlib.sha256()
    for entry in sorted(path.rglob("*")):
        relative = entry.relative_to(path).as_posix().encode()
        if entry.is_symlink():
            value.update(b"link\0" + relative + b"\0" + os.readlink(entry).encode() + b"\0")
        elif entry.is_file():
            value.update(b"file\0" + relative + b"\0" + digest(entry).encode() + b"\0")
    return value.hexdigest()


def save(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def download(url, target, expected):
    if not target.exists():
        temporary = target.with_suffix(".download")
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open("wb") as output:
            remaining = 128 * 1024 * 1024
            while chunk := response.read(min(1024 * 1024, remaining + 1)):
                remaining -= len(chunk)
                if remaining < 0:
                    raise ValueError("source archive exceeds the download limit")
                output.write(chunk)
        if digest(temporary) != expected:
            raise ValueError("download digest mismatch")
        temporary.replace(target)
    if digest(target) != expected:
        raise ValueError("cached archive digest mismatch")


def extract(stream, destination, expected_root):
    remaining = 512 * 1024 * 1024
    for count, member in enumerate(stream, 1):
        path = PurePosixPath(member.name)
        remaining -= member.size
        if (count > 100000 or remaining < 0 or path.is_absolute() or ".." in path.parts
                or not path.parts or path.parts[0] != expected_root
                or not (member.isdir() or member.isfile())):
            raise ValueError("unsupported source archive entry")
        target = destination.joinpath(*path.parts)
        if member.isdir():
            target.mkdir(mode=0o700, parents=True, exist_ok=True)
        else:
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with stream.extractfile(member) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o755 if member.mode & 0o111 else 0o644)


def apply_spinel_fix(sdk, pin):
    """Fix integer promotion in the exact pinned Spinel source; never patch an unknown revision."""
    path = sdk / "src/lib/spinel/spinel.c"
    if digest(path) != pin["before_sha256"]:
        raise ValueError("unexpected Spinel source before unsigned-shift fix")
    content = path.read_bytes()
    for index, count in ((3, 2), (7, 1)):
        before = f"(data_in[{index}] << 24)".encode()
        after = f"((uint32_t)data_in[{index}] << 24)".encode()
        if content.count(before) != count:
            raise ValueError("unexpected Spinel shift count")
        content = content.replace(before, after)
    if hashlib.sha256(content).hexdigest() != pin["after_sha256"]:
        raise ValueError("unexpected Spinel source after unsigned-shift fix")
    path.write_bytes(content)


def sources(workspace, pins):
    archives = workspace / "archives"
    archives.mkdir(exist_ok=True)
    source = workspace / "sources"
    if source.exists():
        raise ValueError("incomplete build has extracted sources; use a new empty workspace")
    source.mkdir()
    roots = {}
    for name, pin in pins["sources"].items():
        archive = archives / f"{name}-{pin['commit']}.tar.gz"
        download(f"https://codeload.github.com/{pin['repository']}/tar.gz/{pin['commit']}",
                 archive, pin["archive_sha256"])
        with tarfile.open(archive) as stream:
            extract(stream, source, f"{name}-{pin['commit']}")
        roots[name] = source / f"{name}-{pin['commit']}"
        if not roots[name].is_dir():
            raise ValueError("unexpected archive root")
    sdk = roots["openthread"]
    apply_spinel_fix(sdk, pins["spinel_unsigned_shift_fix"])
    shutil.copytree(roots["mbedtls-framework"], roots["mbedtls"] / "framework", dirs_exist_ok=True)
    shutil.copytree(roots["mbedtls"], sdk / "third_party/mbedtls/repo", dirs_exist_ok=True)
    return sdk


def run(command, log):
    subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=1800)


def build(workspace, sanitizers):
    if sys.platform != "linux":
        raise ValueError("SDK builds require Linux; use an explicit Linux build environment")
    if not workspace.is_absolute() or workspace == Path("/") or workspace.is_symlink():
        raise ValueError("workspace must be an absolute disposable directory")
    for program in ("cmake", "cc", "c++"):
        if shutil.which(program) is None:
            raise ValueError(f"missing required tool: {program}")
    configuration = dict(version=1, bridge_source_sha256=tree_digest(SOURCE),
                         pins_sha256=digest(SOURCE / "dependencies.json"), sanitizers=sanitizers)
    marker = workspace / ".wotex-native-workspace.json"
    if workspace.exists() and any(workspace.iterdir()):
        if not marker.is_file() or json.loads(marker.read_text()) != configuration:
            raise ValueError("workspace is not an empty or matching native build")
    else:
        workspace.mkdir(mode=0o700, parents=True, exist_ok=True)
        save(marker, configuration)
    manifest_path = workspace / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest["configuration"] != configuration or tree_digest(workspace / "sources") != manifest["sources_sha256"]:
            raise ValueError("cached source mismatch")
        for relative, expected in manifest["artifacts"].items():
            if digest(workspace / relative) != expected:
                raise ValueError("cached artifact mismatch")
        print(str(workspace / "build/wotex-thread-host"))
        return
    pins = json.loads((SOURCE / "dependencies.json").read_text())
    sdk = sources(workspace, pins)
    build_dir = workspace / "build"
    command = ["cmake", "-S", str(SOURCE), "-B", str(build_dir),
               "-DCMAKE_BUILD_TYPE=RelWithDebInfo", f"-DWOTEX_OPENTHREAD_SOURCE={sdk}",
               f"-DWOTEX_NATIVE_SANITIZERS={'ON' if sanitizers else 'OFF'}"]
    with (workspace / "build.log").open("w") as log:
        run(command, log)
        run(["cmake", "--build", str(build_dir), "--target", "wotex-thread-host", "-j4"], log)
    executable = build_dir / "wotex-thread-host"
    manifest = dict(configuration=configuration, pins=pins, sources_sha256=tree_digest(workspace / "sources"),
                    artifacts={"build/wotex-thread-host": digest(executable),
                               "build/include/nlohmann/json.hpp": digest(build_dir / "include/nlohmann/json.hpp")},
                    compiler=subprocess.check_output(["c++", "--version"], text=True).splitlines()[0],
                    cmake=subprocess.check_output(["cmake", "--version"], text=True).splitlines()[0],
                    configure_command=command, sdk_override="Mbed TLS 3.6.7; unsigned Spinel integer shifts", networking_started=False)
    if manifest["artifacts"]["build/include/nlohmann/json.hpp"] != pins["json"]["sha256"]:
        raise ValueError("JSON dependency digest mismatch")
    save(manifest_path, manifest)
    print(str(executable))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitizers", action="store_true")
    parser.add_argument("workspace", type=Path)
    arguments = parser.parse_args()
    try:
        build(arguments.workspace, arguments.sanitizers)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"native build failed ({type(error).__name__}); inspect the workspace build.log", file=sys.stderr)
        raise SystemExit(1)
