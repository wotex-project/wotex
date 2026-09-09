# Wotex BLE

**Consumer-neutral Bluetooth Low Energy interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_ble.svg)](https://hex.pm/packages/wotex_ble)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_ble)
[![CI](https://github.com/wotex-project/wotex-ble/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-ble/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-ble/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-ble)
[![License](https://img.shields.io/hexpm/l/wotex_ble.svg)](https://github.com/wotex-project/wotex-ble/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This checkout is a `0.1.0-dev` development library. The public API remains
unstable, and the ordered software profile is unfinished. Package metadata
does not establish publication or release readiness.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

This development checkout is prepared as the `wotex_ble` Hex package but does
not assert that a release has been published. A sibling-checkout consumer can
select it explicitly:

```elixir
def deps do
  [{:wotex_ble, path: "../wotex-ble"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

## Implemented profile

The package provides typed peer, UUID, address, characteristic and value APIs,
plus two explicit Linux BlueZ backends. The default one-shot backend invokes a
supplied `busctl` for an already connected characteristic. The persistent backend
owns a packaged Python/dbus-next bridge and one unique D-Bus sender. It supports
GATT discovery, explicit Agent pairing, live health, typed reads, acknowledged
writes, notification/indication subscriptions and bounded cleanup.

The persistent backend requires an installed Python interpreter with dbus-next
0.2.3, a running BlueZ service, an explicit local bus address and a selected peer.
It does not install dependencies, start that service or power an adapter.
`connection: :borrowed` leaves ordinary existing device connections intact;
`:owned` explicitly allows connection establishment and owned-link cleanup.
Pending Pair sender loss may separately make BlueZ disconnect a borrowed peer.

The native SDK has passed 15 cases against real BlueZ 5.85 and virtual Linux
controllers. The independent provider uses BlueZ's GATT server API, so the wire
endpoints remain the same stack. See the exact [native fixture evidence](docs/provenance/virtual-controller.md).
Public BEAM/Runtime virtual-peer acceptance and the complete stress/matrix gate
remain unfinished in the ordered plan.

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

For a persistent session, also select `lifecycle: :persistent`; `executable`
then names Python. Supply a validated `Wotex.BLE.Peer`, `bus_address` and the
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
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this repository.

`profile/0` provides Runtime reads and writes under `:ble`; `profile(:gatt)`
adds Property observation and Event subscriptions under `:ble_gatt` and requires
the persistent first-party backend. Both use omitted Form contentType and the
native value codec selectors. Every explicit contentType and Runtime credential
is rejected before backend I/O. Runtime owns public stream identity; the relay
releases its original session on owner loss or cancellation.

See the original [one-shot baseline profile](docs/specs/WBL.02-implemented-profile.md),
[primary sources](docs/provenance/primary-sources.md) and
[executable evidence](docs/provenance/executable-evidence.md).

## Development

Use Elixir 1.18 or newer with compatible OTP. Local Wotex core and Runtime
checkouts require explicit `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Run `mix check` before commits. It includes package compilation outside the
checkout, tests/coverage, static checks, docs and dependency audit.
Optional interoperability suites fail if invoked without their required peer.
No remote repository, published package or publication action is implied.

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WBL-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](docs/specs/WBL.11-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and retained end-to-end workflows.
Its [concrete corpus](docs/specs/fixtures/contract-v1.json) contains specified
inputs and outcomes. Executable tests cite the cases they implement; the corpus
file and scenario tables alone do not establish acceptance of the whole profile.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WBL.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. The implemented mapping and relay cover part of these requirements. A passing
baseline gate does not accept the unfinished software-peer and stress profile.
