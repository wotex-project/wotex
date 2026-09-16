# Wotex Thread

**Consumer-neutral Thread inspection and explicit OpenThread SDK management.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_thread.svg)](https://hex.pm/packages/wotex_thread)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_thread)
[![CI](https://github.com/wotex-project/wotex-thread/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-thread/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-thread/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-thread)
[![License](https://img.shields.io/hexpm/l/wotex_thread.svg)](https://github.com/wotex-project/wotex-thread/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This is a development checkout. The public API remains unstable, and the
software implementation plan is not complete. Package publication is separate.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

This development checkout is prepared as the `wotex_thread` Hex package but
does not assert that a release has been published. A sibling-checkout consumer
can select it explicitly:

```elixir
def deps do
  [{:wotex_thread, path: "../wotex-thread"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

## Accepted native target

The accepted backend retains the existing first-party C++17 OpenThread
Port. Joiner execution, native state subscriptions, complete simulated-network
workflows and full lifecycle proof remain required. Python is not a production
runtime dependency. The injected BEAM ownership peer is an Erlang escript; the
native build is a Mix task. Active software tests use ExUnit. Dormant Python
protocol/process drivers have been retired; their unexecuted cells remain open.

[WTH.13](docs/specs/WTH.13-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. `mix wotex.native.build --workspace ABS` now
builds the pinned Linux host; `mix wotex.software.build` and
`mix wotex.software.run` remain specified work. Generic orchestration and
assertions belong to Mix/ExUnit; upstream SDK Python is build-time only.

## Implemented profile

The implemented package provides bounded Operational Dataset TLVs and a real
read-only `ot-daemon` Unix-socket adapter. Dataset inspection redacts key material;
explicit `encode/1` returns the raw bytes. Unknown TLVs are retained, duplicates
are rejected, and known lengths/network-name encoding are validated.
`complete?/2` checks required field presence, not the SDK's full semantic validity.

## Quick start

```elixir
{:ok, session} = Wotex.Thread.connect(
  client: Wotex.Thread.Daemon, socket_path: "/run/openthread-wpan0.sock", timeout: 3000
)
try do
  Wotex.Thread.send(session, %{type: :state})
after
  Wotex.Thread.disconnect(session)
end
```

The daemon session owns its client socket and must be used from its creating
process. The consumer owns the daemon.
Supported reads are `:state`, `:version`, `:network_name` and `:rloc16`.
Responses are capped at 8192 bytes; remote Error, malformed output, closure and
timeout fail. This adapter neither starts OpenThread nor changes datasets.

`Wotex.Thread.OpenThread` is a separate, explicitly started Linux SDK adapter.
It owns the native host, SDK instance, radio child processes, interface and
settings lock. Its implemented APIs validate and export Datasets, enable IPv6
and Thread, form an explicitly permitted network, submit management updates,
and start/stop the commissioner with exact, finite joiner admissions. Management
acceptance is separate from Dataset activation; commissioner admission is
separate from joining. Joiner execution and native state subscriptions remain
planned. Thread management does not provide generic application Property writes.
Border-router management and physical-radio interoperability remain outside
this target profile.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :thread, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Errors are structured and credential-free. Unknown Form extension terms survive
mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; unsupported receive/subscription calls fail
explicitly. Callback names alone do not establish consumer behavioral parity.
Compatibility requires concrete differential scenarios and independently observed
software interactions for each advertised operation.

See [protocol and graduation contract](docs/specs/WTH.01-protocol.md),
[implemented profile](docs/specs/WTH.02-implemented-profile.md),
[primary sources](docs/provenance/primary-sources.md) and
[executable evidence](docs/provenance/executable-evidence.md).

## Development

Use Elixir 1.18 or newer with compatible OTP. Local Wotex core and Runtime
checkouts require explicit `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Run `mix check` before commits. It checks formatting, compiles with warnings as
errors, and runs the default test suite. Wider checks belong to release readiness.
Optional interoperability suites fail if invoked without their required peer.
The software suite includes native OpenThread simulation tests for Dataset
validation, formation, management callbacks and commissioner admission/cleanup,
plus BEAM-to-SDK tests. These do not establish physical-radio interoperability
or complete the remaining software-network and lifecycle requirements.
No remote repository, published package or publication action is implied.

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WTH-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](docs/specs/WTH.11-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and end-to-end workflows.
Its [concrete corpus](docs/specs/fixtures/contract-v1.json) contains specified,
unexecuted cases; the scenario tables alone are not executable acceptance evidence.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WTH.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.
