# Wotex BLE

**Consumer-neutral Bluetooth Low Energy interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_ble.svg)](https://hex.pm/packages/wotex_ble)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_ble)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_ble.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-ble/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This package is a 0.1.0 development library. The public API remains
unstable, and the ordered software profile is unfinished. Package metadata
does not establish publication or release readiness.

Build handoff: [software implementation sequence](../../docs/packages/wotex-ble/plans/software-implementation.md).

## Installation

Wotex BLE 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual; Hex
resolves `wotex` and `wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_ble, "~> 0.1"}
  ]
end
```

Until then, depend on one commit of the
[WoTEx repository](https://github.com/wotex-project/wotex) and select each
package directory with `sparse:`. This package's `mix.exs` declares Hex
requirements for `wotex` and `wotex_runtime`, so declare all three packages at
the same `ref` with `override: true`, as the
[consumer guide](https://github.com/wotex-project/wotex/blob/main/docs/guides/consumer.md)
describes:

```elixir
@wotex_ref "<commit>"

def deps do
  [
    {:wotex,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex",
     override: true},
    {:wotex_runtime,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-runtime",
     override: true},
    {:wotex_ble,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-ble",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_ble, path: "../wotex/packages/wotex-ble", override: true}
```

Path dependencies prove nothing about a released artifact.

## Accepted native target

The accepted backend is a first-party C++17 Port using libdbus and the real
BlueZ service. A complete explicit SDK/digest/guardian/digest selector cohort
now verifies both native artifacts under the original connection deadline,
launches the SDK only through the guardian, and opens a fresh report-credit
generation before the peer. Persistent mode requires that cohort; no interpreter
backend remains. Complete public software-peer/stress evidence remains required.

[WBL.13](../../docs/packages/wotex-ble/specs/WBL.13-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. Native value reports are admitted through a
64-frame/1 MiB BEAM ledger and receive cumulative byte-exact credit only after
their stream owner admits final receiver delivery; retirement consumes only the
retired stream's pending records. On Linux, the explicit native build task
(`wotex.ble.native.build`, see [Development](#development)) builds the host,
runtime guardian and pinned shared libdbus, audits their ELF dependencies and
records `native-manifest.json`; see the
[native build receipt](../../docs/packages/wotex-ble/provenance/native-build-v1.json). The explicit
software tasks `wotex.ble.software.build` and `wotex.ble.software.run` build and
boot the BlueZ virtual-controller fixture once per BEAM lane; see the
[software run receipt](../../docs/packages/wotex-ble/provenance/software-run-v3.json). Upstream SDK
Python is build-time only, and the fixture's independent GATT peer uses Python
only as a test peer.

## Implemented profile

The package provides typed peer, UUID, address, characteristic and value APIs,
plus two explicit Linux BlueZ backends. The default one-shot backend invokes a
supplied `busctl` for an already connected characteristic. The persistent backend
launches the verified C++ host through its process guardian and owns one unique
D-Bus sender. It supports
GATT discovery, explicit Agent pairing, live health, typed reads, acknowledged
writes, notification/indication subscriptions and bounded cleanup.

The persistent backend requires the Linux host and runtime guardian built by
the native build task, with their manifest SHA-256 digests, a running BlueZ
service, an explicit local bus address and a selected peer.
It does not install dependencies, start that service or power an adapter.
`connection: :borrowed` leaves ordinary existing device connections intact;
`:owned` explicitly allows connection establishment and owned-link cleanup.
Pending Pair sender loss may separately make BlueZ disconnect a borrowed peer.

The native host passes the 11 public BLE and Runtime tests and the 5 WBL-C09
lifecycle stress tests against real BlueZ 5.85 and two virtual Linux controllers
in both BEAM lanes. The independent
provider uses BlueZ's GATT server API, so the wire endpoints remain the same
stack. See the [virtual-controller fixture](../../docs/packages/wotex-ble/provenance/virtual-controller.md).
The x86_64 guest lane and final package gates remain unfinished in the ordered
plan.

## Quick start

```elixir
{:ok, uuid} = Wotex.BLE.UUID.normalize(0x2A19)
{:ok, wire_uuid} = Wotex.BLE.UUID.encode(uuid)
{:ok, ^uuid} = Wotex.BLE.UUID.decode(wire_uuid)
```

For one-shot access, supply `client: Wotex.BLE.BlueZ`, an absolute `executable`
for `busctl`, BlueZ `object_path`, `service` and `characteristic` to `connect/1`.
Send `%{type: :read, service: 0x180F, characteristic: 0x2A19}` or an explicit
`:write` with binary `value`. UUIDs accept short integers/text or canonical
128-bit text. Handles are 1..65535; values are at most 512 bytes.

For a persistent session, also select `lifecycle: :persistent`; `executable`,
`executable_sha256`, `guardian` and `guardian_sha256` then name the built native
host and runtime guardian. Supply a validated `Wotex.BLE.Peer`, `bus_address` and the
explicit connection mode. `discover/2` returns paginated characteristic values;
`Wotex.BLE.Characteristic.address/1` preserves an exact discovery generation.
`read/3` and `write/4` accept `value_type` and `byte_order` options. `pair/2`
requires a consumer `Wotex.BLE.Agent` decision callback; no default acceptance
or security-level assurance is inferred from a paired flag.

`subscribe/2` delivers `{:wotex_ble, reference, {:ok, value, metadata}}` messages
to the selected receiver. Cancel with `unsubscribe/2` on the same session.
Metadata identifies BlueZ Value changes; it does not infer whether a change
came from an ATT notification or a read. Equal changes remain distinct updates.
BlueZ acknowledges indications. A characteristic supporting both notify and
indicate requires `mode: :auto`, whose effective mode is `:bluez_selected`.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :ble, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Errors are structured and credential-free. Unknown Form extension terms survive
mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. `receive/2` remains unsupported; persistent subscriptions deliver directly
to their receiver. One-shot clients do not provide streaming or live health. Callback names alone do not establish consumer behavioral parity.
Compatibility requires concrete differential scenarios and independently observed
software interactions for each advertised operation.

`profile/0` provides Runtime reads and writes under `:ble`; `profile(:gatt)`
adds Property observation and Event subscriptions under `:ble_gatt` and requires
the persistent first-party backend. Both use omitted Form contentType and the
native value codec selectors. Every explicit contentType and Runtime credential
is rejected before backend I/O. Runtime owns public stream identity; the relay
releases its original session on owner loss or cancellation.

See the [implemented profile](../../docs/packages/wotex-ble/specs/WBL.02-implemented-profile.md),
[primary sources](../../docs/packages/wotex-ble/provenance/primary-sources.md) and
[executable evidence](../../docs/packages/wotex-ble/provenance/executable-evidence.md).

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-ble test test/wotex/ble/mapping_test.exs  # one test file
mix check.fast --package wotex-ble                      # compile, format, Credo, tests
mix pkg wotex-ble check --no-retry                      # full gate
mix native.lint --package wotex-ble                     # clang-format on changed C/C++ lines
mix native.test --package wotex-ble                     # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).
On a host that is not Linux, the D-Bus host's suite runs in the Linux
container of the native checks when Docker is available.

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-ble`. It compiles with warnings as errors, checks the lock and
unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`, Credo,
Doctor, `mix docs --warnings-as-errors` (in the `docs` environment), tests with
the 95% coverage floor (`mix coveralls`, the only ExUnit pass), Dialyzer and
`git diff --check`, then runs `bin/check_archive.exs` and
`bin/check_application_free.exs`. The archive check builds the `wotex_ble`
archive without path dependencies, checks its contents and Hex dependency
declarations and compiles the unpacked package out of tree; the second check
proves that the package defines no Application callback.

The ordinary test run needs a C11 compiler (`cc`) and a C++17 compiler (`c++`):
the native component tests compile the scripted host, the runtime guardian and
the command guardian from `priv/bluez/native/` and `test/native/`. Tests tagged
`interop`, `hardware` or `software` are excluded; they need their peer or
target and fail if selected without it. No test contacts a physical adapter by
default.

### Explicit lanes

None of these runs in the gate. Each takes a disposable absolute workspace
directory; a completed matching workspace is verified read-only, and an
unrelated, locked or failed one is refused.

Native build (Linux only, no cross compilation). It needs `cmake`, `ninja`,
`pkg-config`, `cc`, `c++`, `readelf` and `xz` on `PATH`, the Expat development
files for libdbus, and network access to download the pinned libdbus 1.16.2
archive. It writes the host, runtime guardian, private-bus `dbus-daemon`,
shared libdbus and `native-manifest.json`. `test/native/Dockerfile` defines the
Debian 12 image used for the recorded runs (`BEAM_LANE=lower` or `upper`).

```console
mix wotex.native.build --package wotex-ble --workspace /absolute/disposable/dir
mix pkg wotex-ble wotex.ble.native.build --workspace /absolute/disposable/dir
```

Native component lanes rerun the tests that compile component executables
(`test/wotex/ble/native_{frame,credit,bytes,output,pages,reports,custody,guardian_startup,command}_test.exs`
and the private-bus test) with `WOTEX_BLE_NATIVE_LANE=sanitizers` (ASan/UBSan)
or `leak_audit` (LeakSanitizer, Linux only). The built-host and private-bus
tests (tag `interop`) need a completed native workspace:

```console
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/native_frame_test.exs
WOTEX_BLE_NATIVE_WORKSPACE=/absolute/disposable/dir \
  mix pkg wotex-ble test --only interop test/interop/native_host_test.exs
WOTEX_BLE_DBUS_SOURCE=/absolute/disposable/dir/sources/libdbus/dbus-1.16.2 \
WOTEX_BLE_DBUS_BUILD=/absolute/disposable/dir/build/libdbus \
  mix pkg wotex-ble test --only interop test/interop/native_bus_test.exs
```

BlueZ virtual-controller software lane. It needs Docker able to build and run
`linux/arm64` images, `cc` for the command guardian, and network access for the
pinned BlueZ, Hex and Rebar3 source archives. The build hashes the fixture
assets in `test/interop/virtual/` and the sources of `packages/wotex`,
`packages/wotex-runtime` and this package, builds the `Dockerfile.system`,
`Dockerfile.bluez` and `Dockerfile.public` images and a 6 GiB guest disk. The
run boots one QEMU guest per BEAM lane with two virtual LE controllers and runs
the public BLE, Runtime and stress tests against the Mix-built host.

```console
mix pkg wotex-ble wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-ble wotex.software.run --workspace /absolute/disposable/dir
```

The hardware test (`test/interop/bluez_device_test.exs`, tag `hardware`) reads a
selected Battery Level characteristic and needs `WOTEX_BLE_BUSCTL` and
`WOTEX_BLE_CHARACTERISTIC_PATH`. Inside `packages/wotex-ble`, the task aliases
`wotex.native.build`, `wotex.software.build` and `wotex.software.run` name the
same qualified tasks.

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-ble/plans/software-implementation.md)
and [specification index](../../docs/packages/wotex-ble/specs/WBL-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](../../docs/packages/wotex-ble/specs/WBL.11-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and end-to-end workflows.
Its [concrete corpus](priv/fixtures/contract-v1.json) contains specified
inputs and outcomes. Executable tests cite the cases they implement; the corpus
file and scenario tables alone do not establish acceptance of the whole profile.

The [specification catalogue](../../docs/packages/wotex-ble/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](../../docs/packages/wotex-ble/specs/WBL.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. The implemented mapping and relay cover part of these requirements. A passing
baseline gate does not accept the unfinished software-peer and stress profile.

## License

Wotex BLE is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-ble/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-ble/NOTICE).
