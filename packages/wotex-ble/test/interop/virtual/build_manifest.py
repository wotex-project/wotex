"""Record the exact Linux/BlueZ fixture binaries and installed dependency set."""

import hashlib
import json
from pathlib import Path
import subprocess


def command(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


paths = [
    "/boot/vmlinuz-6.1.0-53-arm64",
    "/boot/initrd.img-6.1.0-53-arm64",
    "/boot/config-6.1.0-53-arm64",
    "/module/hci_vhci.c",
    "/lib/modules/6.1.0-53-arm64/kernel/drivers/bluetooth/hci_vhci.ko",
    "/opt/bluez/bin/btvirt",
    "/opt/bluez/bin/btmon",
    "/opt/bluez/libexec/bluetooth/bluetoothd",
    "/usr/bin/dbus-daemon",
    "/usr/bin/qemu-system-aarch64",
    "/usr/bin/qemu-img",
]
print(
    json.dumps(
        {
            "bluez_version": command(
                "/opt/bluez/libexec/bluetooth/bluetoothd", "--version"
            ),
            "qemu_version": command("qemu-system-aarch64", "--version"),
            "compiler": command("cc", "--version"),
            "module": command("modinfo", "-k", "6.1.0-53-arm64", "hci_vhci"),
            "elixir_latest": command("/usr/local/bin/elixir", "--version"),
            "elixir_lower": command(
                "env",
                "PATH=/opt/lower/elixir/bin:/opt/lower/erlang/bin:/usr/local/bin:/usr/bin:/bin",
                "/opt/lower/elixir/bin/elixir",
                "--version",
            ),
            "sdk": command("/opt/sdk/bin/python", "-m", "pip", "freeze", "--all"),
            "packages": command(
                "dpkg-query", "-W", "-f=${Package}=${Version}\n"
            ).splitlines(),
            "sha256": {
                name: hashlib.file_digest(Path(name).open("rb"), "sha256").hexdigest()
                for name in paths
            },
        },
        indent=2,
        sort_keys=True,
    )
)
