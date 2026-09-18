# Virtual-controller software fixture

`mix wotex.software.build --workspace ABSOLUTE_PATH` builds a disposable Linux
ARM64 guest with two virtual LE controllers, and `mix wotex.software.run
--workspace ABSOLUTE_PATH` boots it once per BEAM lane. The Mix-built native
host connects to real BlueZ through its own D-Bus sender. A separate fixture
implementation of BlueZ's GATT server API supplies private UUIDs and values; it
does not implement or replace the client boundary. Both wire endpoints use
BlueZ, so this is same-stack protocol evidence with an independent GATT
application provider. The exact executed cohort is the
[software run receipt](software-run-v3.json); the earlier
[public-only](software-run-v1.json) and [first stress](software-run-v2.json)
receipts remain historical.

## Explicit invocation

The host needs Docker with Linux ARM64 execution and a C compiler for the
command guardian. The build reads the sibling `packages/wotex` and
`packages/wotex-runtime` sources and records every package source, fixture asset, tool, download and
image identity before creating `software-manifest.json`. The workspace must be
an absolute disposable directory. An unrelated nonempty workspace, a locked or
failed build, changed sources, a changed artifact, a missing tool or a missing
guest facility fails. A completed workspace is verified read-only before every
run, and each run retains a separate result directory.

```sh
mix pkg wotex-ble wotex.software.build --workspace /absolute/disposable/workspace
mix pkg wotex-ble wotex.software.run --workspace /absolute/disposable/workspace
```

Both run from the repository root; inside `packages/wotex-ble` the equivalent is
`WOTEX_PATH_DEPS=1 mix wotex.software.build --workspace ...` and likewise for
`wotex.software.run`.

The build produces three owned images through the command guardian, each within
ten minutes: `test/interop/virtual/Dockerfile.system` (Debian 12 packages, the
pinned kernel and QEMU, both BEAM lanes), `Dockerfile.bluez` (BlueZ, virtual HCI
module and peer environment) and `Dockerfile.public` (pinned Hex and Rebar3,
all three packages compiled in both lanes and `mix wotex.native.build`). The
public image is exported to a 6 GiB ext4 guest disk. `build_manifest.exs`
records BlueZ, QEMU, compiler, BEAM, peer package and kernel/module/binary
hashes inside the image.

The selected guest uses Debian Linux `6.1.0-53-arm64` (`6.1.187-1`), QEMU
`7.2.22` (`1:7.2+dfsg-7+deb12u18+b3`), BlueZ source
`2123ab772fbe97d1369fc9e179ea87c3469cf98f` (5.85), dbus-next 0.2.3 with required
package hashes, Elixir 1.20.2 / OTP 29.0.4 and Elixir 1.18.4 / OTP 27.3.4.15.

The Debian kernel omits `CONFIG_BT_HCIVHCI`. The fixture builds the unmodified
matching `hci_vhci.c` against the exact kernel headers/configuration and
`Module.symvers`, using [Kbuild's external-module interface](https://docs.kernel.org/kbuild/modules.html).
The guest checks `/dev/vhci` and exactly two controller paths under
`/sys/devices/virtual/bluetooth`. It loads no module into the host kernel.
The module's unsigned/external taint is recorded in the guest console.

## Run ownership

Each lane creates a copy-on-write disk overlay and boots QEMU TCG in one owned
container, without a network device or physical Bluetooth controller, within
ten minutes. The guest starts `btvirt -L -l2`, a private D-Bus daemon,
`bluetoothd`, `btmon` and the independent GATT peer, then runs
`test/interop/bluez_test.exs`, `test/interop/bluez_runtime_test.exs` and the
`:software` stress file `test/software/lifecycle_stress_test.exs` with
`WOTEX_REQUIRE_SOFTWARE=1` against the native host and guardian named by the
guest's native build manifest. The host removes and counts owned containers
after every lane, including failures. A lane passes only when the guest reports
zero remaining owned processes and virtual controllers, the console has no
kernel panic, the peer reports clean release and ExUnit records exactly the
literal public and stress test count as passed with no other status.

## Assertions and source boundaries

The public lanes assert exact read `3412`, acknowledged write `7856` and
readback, denied reads and writes with retained effects, duplicate UUID
rejection and explicit instance selection, stale generation rejection before a
write, equal notifications, equal indications and the server's actual
`Confirm()` calls. They exercise an independent second sender surviving the
first sender's cleanup, receiver death releasing the CCC session, explicit
pairing acceptance, rejection and timeout, and real ConsumedThing Property/Event
values, context, media and error projection.

Scenarios ported from the retired adapter lane add an address whose object path
names a different characteristic, which fails `address_mismatch` without a
WriteValue. A wrong Agent challenge ID is injected by replacing the owner's
recorded challenge ID while the policy decides; the host rejects that reply, the
pairing fails and the Agent is unregistered without CancelPairing or RemoveDevice.
A read-caused Value change is the existing stream assertion that a plain read
delivers a `bluez_value_change` report. An owned link is opened after a
peer-side disconnect: explicit close succeeds, submits exactly one Connect and one
Disconnect from the native sender, releases that sender within 1000 ms, and BlueZ
drops the controller link within 3500 ms of close.

A read-only private-bus monitor accounts for successful Agent and notification
control acknowledgements and unique-sender loss. It does not respond to the
observed calls. Native senders may not call `CancelPairing`, `RemoveDevice` or
`RequestDefaultAgent`. The fixture uses `RemoveDevice` and `RequestDefaultAgent`
only for its own disposable peer and Agent. Borrowed native owners may not call
`Disconnect`. Pinned [`device_request_disconnect`](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/device.c)
schedules its kernel disconnect through a two-second timer; the library releases
its sender within the one-second ownership grace and does not claim an
immediate physical disconnect.

BlueZ's pinned [`notify_cb` and `write_characteristic_cb`](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/gatt-client.c)
retain equal values and emit a shared Value property change for each registered
client callback. With two senders, one ATT notification can therefore produce
more than one BlueZ property signal for each listener. The binding retains the
actual `bluez_value_change` source; it does not infer a one-to-one ATT delivery
count.

The private-bus policy is deliberately limited to this disposable guest's root
processes. It is a fixture configuration, not a production D-Bus policy example.
The GATT values and pairing decisions are fixture-owned; no production credentials
or persisted host bonds are used.

## Executed cohorts

The public-only cohort in [software-run-v1.json](software-run-v1.json) passed
three consecutive runs, 10 of 10 tests per lane. The first runs
of this fixture exposed two native host defects during rejected and timed-out
pairing: link loss relabelled a completed explicit close as `cleanup_timeout`,
and a closed private sender stopped the host from reading its input. Both have
native regressions.

The [first stress receipt](software-run-v2.json) records three consecutive
passing runs, 15 of 15 tests per lane. The owned-link scenario then failed with
`cleanup_timeout` in both lanes: the host exited on its cooperative deadline
before writing a completed close, and the BEAM handed cleanup to the guardian at
that same deadline. After both fixes, the current
[software run receipt](software-run-v3.json) records a fresh verified build and
three consecutive runs that pass both lanes, 16 of 16 tests in each (208 to 265 s
per lane), with zero remaining owned containers. The stress file performs 1000
alternating acknowledged writes and correlated reads on one sender; 100
connect/health/disconnect cycles that each return to the BEAM process and port
baseline, zero guardian or host OS processes and released BlueZ senders, Agents
and notification sessions (the fixture resets every 50 cycles because its
monitor bounds unique senders); 100 subscribe/notify/receiver-kill cycles that
release the real CCC session within 1100 ms with no retained stream or credit
record; 32 concurrent callers over 320 correlated reads, plus 65 callers queued
behind a suspended owner, of which exactly 64 are admitted and one is `busy`;
and forced faults. A peer ReadValue delayed 1500 ms against a 200 ms request
deadline, a truncated native frame injected into the connection, SIGKILL of the
host and a peer-side Device1.Disconnect each end the generation and return to
the same baseline. The borrowed link stays connected except after the peer-side
disconnect. Samples of `:erlang.memory(:total)` and the long-lived host VmRSS
are separate `stress.jsonl` evidence: host RSS stayed at 3.9 MB throughout each
session and BEAM totals varied within about 1.4 MB. BEAM timers are not globally
enumerable; their release is covered only through exit of the owning processes.

An earlier Python-orchestrated guest ran the retired Python adapter through 15
cases, including a wrong pairing challenge, read-caused Value changes, stale
targets and BlueZ link-drain timing. Those results apply only to that adapter.
Their scenarios now run in the public ExUnit lanes as described above. An x86_64
guest lane and final package gates remain open.
