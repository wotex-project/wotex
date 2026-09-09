# Python adapter virtual-controller evidence

`test/interop/virtual_machine.py` builds and runs a disposable ARM64 Linux guest
with two virtual LE controllers. The first-party `priv/bluez` SDK connects to
real BlueZ through its own D-Bus sender. A separate fixture implementation of
BlueZ's GATT server API supplies private UUIDs and values; it does not implement
or replace the SDK's client boundary. Both wire endpoints use BlueZ, so this is
same-stack protocol evidence with an independent GATT application provider.

This is scoped Python adapter evidence for WBL-P07 scenarios. Public BEAM/Runtime interoperability,
the complete software stress/version matrix and final package acceptance remain
separate required proof. This entry point does not accept WBL-P07 or WBL-P08 as
a whole. The accepted native/Mix entry points and source profile are in
[WBL.13](../specs/WBL.13-native-backend.md); this current Python runner is not
the target orchestration implementation.

## Explicit invocation

The host needs Python 3.11 or later and Docker with Linux ARM64 execution. The
build uses pinned base images and downloads the pinned BlueZ archive. The guest
runs QEMU TCG, without an emulated network adapter or physical Bluetooth controller.
The workspace must be an absolute disposable directory outside the repository.
An unrelated nonempty workspace, changed source manifest, changed artifact,
missing tool or missing guest facility fails. Concurrent runners cannot share
the same workspace. Reuse checks the artifact hashes and immutable image ID.

```sh
python3 test/interop/virtual_machine.py build /absolute/disposable/ble-fixture
python3 test/interop/virtual_machine.py run /absolute/disposable/ble-fixture
```

The workspace records the source-input hashes, BlueZ archive hash, image ID,
installed Debian package versions, compiler/SDK versions, kernel/configuration/
module/binary hashes, and root filesystem hashes. Each run has a separate disk
overlay, packet capture, bounded peer and D-Bus traces, assertion result and
host/guest cleanup counters. Failed runs retain their evidence. SDK builds,
images, logs, disposable bonds and controller state stay in this workspace.

The selected guest uses Debian Linux `6.1.0-53-arm64` (`6.1.187-1`), QEMU
`7.2.22` (`1:7.2+dfsg-7+deb12u18+b3`), BlueZ source
`2123ab772fbe97d1369fc9e179ea87c3469cf98f` (5.85), and dbus-next 0.2.3 with
required package hashes. The Dockerfile pins both Elixir/OTP base images; their
presence alone is not a completed BEAM matrix result.

The Debian kernel omits `CONFIG_BT_HCIVHCI`. The fixture builds the unmodified
matching `hci_vhci.c` against the exact kernel headers/configuration and
`Module.symvers`, using [Kbuild's external-module interface](https://docs.kernel.org/kbuild/modules.html).
The guest checks `/dev/vhci` and exactly two controller paths under
`/sys/devices/virtual/bluetooth`. It loads no module into the host kernel.
The module's unsigned/external taint is recorded in the guest console.

## Assertions and source boundaries

The native lane asserts exact read `3412`, acknowledged write `7856` and
readback, denied reads, duplicate UUID rejection and explicit instance selection,
stale/wrong target rejection before a write, equal notifications, equal
indications and the server's actual `Confirm()` calls. It exercises an independent
second sender surviving the first sender's cleanup, read-caused Value changes,
explicit pairing acceptance/rejection/timeout/wrong challenge, and local owner
cleanup within 1000 ms. The separate BlueZ-managed link drain must finish within
3500 ms in this pinned VM.

A read-only private-bus monitor accounts for successful Agent and notification
control acknowledgements and unique-sender loss. It does not respond to the
observed calls. Native senders may not call `CancelPairing`, `RemoveDevice` or
`RequestDefaultAgent`. The fixture uses `RemoveDevice` and
`RequestDefaultAgent` only for its own disposable peer and Agent. Borrowed native owners may not call `Disconnect`.
Pinned [`device_request_disconnect`](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/device.c)
schedules its kernel disconnect through a two-second timer. The library releases
its sender within the one-second ownership grace; it does not wait for or claim
an immediate physical disconnect. The fixture records both durations and still
requires the subsequent BlueZ link drain to complete.
The guest also requires zero owned processes and zero virtual controllers after
cleanup; host cleanup requires zero owned containers.

BlueZ's pinned [`notify_cb` and `write_characteristic_cb`](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/gatt-client.c)
retain equal values and emit a shared Value property change for each registered
client callback. With two senders, one ATT notification can therefore produce
more than one BlueZ property signal for each listener. The fixture counts those
D-Bus reports separately from wire stimuli. The binding retains the actual
`bluez_value_change` source; it does not infer a one-to-one ATT delivery count.

The private-bus policy is deliberately limited to this disposable guest's root
processes. It is a fixture configuration, not a production D-Bus policy example.
The GATT values and pairing decisions are fixture-owned; no production credentials
or persisted host bonds are used.

## Executed Python adapter cohort

The native runner passed all 15 listed cases on the selected ARM64 guest.
Local sender cleanup took 833.2 ms; BlueZ link drain took 2342.3 ms. The result
reported two indication confirmations and zero remaining native senders, Agents,
notification sessions, guest processes, virtual controllers and host containers.

- Image ID: `sha256:a4188f75fe57c2647bbe7a081df614b6880ba1c487d9b7488e18e70b71578605`.
- Assertion report SHA-256: `0cdb3115158fccc2aa7de273525f21a581395c4c9845f4e5fab63d99c3b0fe0a`.
- Ownership report SHA-256: `cfae775b6e8336e22ce47abc96cb6d7a5313d8337f6711b6cad3cd0cf06ab822`.
- Packet capture SHA-256: `5915933ecd8ce8bc3c8f851aa391780d54fdc9afb2d3baf6c6a107c268f3331e`.

These are Python adapter/shared-BlueZ results only; the pending public BEAM/Runtime software-peer
and stress gates above remain required.
