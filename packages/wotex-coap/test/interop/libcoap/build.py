#!/usr/bin/env python3
"""Build the pinned independent peer in an explicitly supplied cache directory."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import urllib.request

REVISION = "7cf7465b784baded4de183290c547d582becfd28"
SHA256 = "d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd"
URL = f"https://codeload.github.com/obgm/libcoap/tar.gz/{REVISION}"
MAX_ARCHIVE = 4 * 1024 * 1024


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, directory, environment, log, timeout=180):
    result = subprocess.run(command, cwd=directory, env=environment, stdout=log,
                            stderr=subprocess.STDOUT, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"peer build failed ({result.returncode}); inspect {log.name}")


def build(options):
    cache = options.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f"libcoap-{REVISION}.tar.gz"
    if not archive.exists():
        with urllib.request.urlopen(URL, timeout=30) as response:
            data = response.read(MAX_ARCHIVE + 1)
        if len(data) > MAX_ARCHIVE or hashlib.sha256(data).hexdigest() != SHA256:
            raise RuntimeError("peer archive digest or size mismatch")
        temporary = archive.with_suffix(".download")
        temporary.write_bytes(data)
        temporary.replace(archive)
    if archive.stat().st_size > MAX_ARCHIVE or digest(archive) != SHA256:
        raise RuntimeError("cached peer archive digest or size mismatch")

    source = cache / f"libcoap-{REVISION}"
    output = cache / ("build-sanitized" if options.sanitize else "build")
    # Recreate only these explicitly named generated directories; never reuse edited sources.
    for directory in [source, output]:
        if directory.exists():
            shutil.rmtree(directory)
    with tarfile.open(archive) as data:
        members = data.getmembers()
        if any(member.name != source.name and not member.name.startswith(source.name + "/")
               for member in members):
            raise RuntimeError("unexpected peer archive root")
        data.extractall(cache, members=members, filter="data")

    cmake = shutil.which("cmake")
    compiler = shutil.which(options.compiler)
    if not cmake or not compiler:
        raise RuntimeError("cmake and the selected C compiler are required")
    environment = os.environ.copy()
    environment.pop("GIT_DIR", None)
    environment.pop("GIT_WORK_TREE", None)
    # Upstream git describe inherits cwd. Stop discovery before any containing repository.
    environment["GIT_CEILING_DIRECTORIES"] = str(cache)
    environment["SOURCE_DATE_EPOCH"] = "0"
    flags = "-O1 -g -fno-omit-frame-pointer"
    if options.sanitize:
        flags += " -fsanitize=address,undefined -fno-sanitize-recover=all"
    command = [cmake, "-S", str(source), "-B", str(output),
               "-DENABLE_DTLS=ON", "-DDTLS_BACKEND=openssl", "-DENABLE_OSCORE=ON",
               "-DENABLE_DOCS=OFF", "-DENABLE_TESTS=OFF", "-DENABLE_EXAMPLES=ON",
               "-DBUILD_SHARED_LIBS=OFF", "-DCMAKE_BUILD_TYPE=Debug",
               f"-DCMAKE_C_COMPILER={compiler}", f"-DCMAKE_C_FLAGS={flags}"]
    if options.openssl_root:
        command.append(f"-DOPENSSL_ROOT_DIR={options.openssl_root.resolve()}")
    log_path = cache / (output.name + ".log")
    with log_path.open("w") as log:
        run(command, source, environment, log)
        run([cmake, "--build", str(output), "--parallel", "4"], source, environment, log)
    executable = output / "coap-server"
    version = subprocess.run([str(executable), "-h"], capture_output=True, text=True,
                             timeout=5, check=False)
    version_text = version.stdout + version.stderr
    if "coap-server v4.3.5" not in version_text or "DTLS and TLS support" not in version_text:
        raise RuntimeError("peer version or DTLS feature verification failed")
    manifest = {
        "schema": "wotex-coap-libcoap-peer-v1", "revision": REVISION,
        "archive_url": URL, "archive_sha256": SHA256,
        "lane": "independent-dtls-udp", "oscore_lane": "same-stack-when-selected",
        "platform": platform.platform(), "python": platform.python_version(),
        "compiler": subprocess.check_output([compiler, "--version"], text=True).splitlines()[0],
        "cmake": subprocess.check_output([cmake, "--version"], text=True).splitlines()[0],
        "configure": command, "sanitizers": ["address", "undefined"] if options.sanitize else [],
        "executable": str(executable), "executable_sha256": digest(executable),
        "peer_features": version_text,
        "openssl": subprocess.check_output(
            [str(options.openssl_root / "bin" / "openssl") if options.openssl_root
             else "openssl", "version", "-a"], text=True),
    }
    manifest_path = output / "peer-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(manifest_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--compiler", default="cc")
    parser.add_argument("--openssl-root", type=Path)
    parser.add_argument("--sanitize", action="store_true")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
