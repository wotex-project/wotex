# Wotex Matter

**Consumer-neutral Matter interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_matter.svg)](https://hex.pm/packages/wotex_matter)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_matter)
[![CI](https://github.com/wotex-project/wotex-matter/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-matter/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-matter/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-matter)
[![License](https://img.shields.io/hexpm/l/wotex_matter.svg)](https://github.com/wotex-project/wotex-matter/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This checkout is a `0.1.0-dev` development baseline. The public API remains
unstable, and the ordered software profile is unfinished. Package metadata
does not establish publication or release readiness.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

This development checkout is prepared as the `wotex_matter` Hex package but
does not assert that a release has been published. A sibling-checkout consumer
can select it explicitly:

```elixir
def deps do
  [{:wotex_matter, path: "../wotex-matter"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

## Accepted native target

The accepted backend is a first-party persistent C++17 connectedhomeip
controller Port, with an owned durable authority/store, attestation, commissioning,
CASE interactions and subscriptions. The current Python factory adapter is a
narrow executable baseline; it does not provide or accept that controller.

[WMA.13](docs/specs/WMA.13-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. The target tooling is `mix wotex.native.build`,
`mix wotex.software.build` and `mix wotex.software.run`, each with an explicit
`--workspace` absolute directory. These tasks are specified implementation work,
not commands claimed to exist in this checkout. Generic orchestration and
assertions belong to Mix/ExUnit; upstream SDK Python is build-time only.

## Implemented profile

The implemented package provides fabric-scoped concrete and batch-read paths,
bounded TLV, typed attribute/event reports, a finite descriptor registry, a
bounded endpoint-catalogue value, a validated `Client` behaviour, an opt-in
Python SDK interaction adapter, compatibility callbacks and WoT Form/Runtime
mapping. TLV preserves tags, explicit scalar widths, null and containers while
bounding bytes, nodes and nesting. `read_paths/3` preserves ordered per-path
successes and errors from a selected client. The `SDK` adapter targets concrete
read/write/invoke calls in the pinned native SDK; an explicitly supplied
controller factory owns SDK startup, credentials and shutdown. The batch API is
not wired to that one-shot adapter. No Python runtime, native SDK binary,
controller factory or commissioning workflow is bundled.

## Quick start

```elixir
{:ok, path} = Wotex.Matter.Address.new(%{
  fabric_id: 1, node_id: 2, endpoint: 1, cluster: 6, member: 0
})
{:ok, bytes} = Wotex.Matter.TLV.encode([
  %{tag: {:context, 1}, type: :u8, value: 42}
])
{:ok, [%{tag: {:context, 1}, type: :u8, value: 42}]} = Wotex.Matter.TLV.decode(bytes)
{:ok, %{type: :i16, value: 2150}} =
  Wotex.Matter.Descriptor.to_element(
    :attribute,
    %{fabric_id: 1, node_id: 2, endpoint: 1, cluster: 0x0201, member: 0},
    :read,
    2150
  )
```

Use `client: Wotex.Matter.SDK` with an absolute Python executable,
`factory: "sdk_host:controller"`, `fabric_id` and a `settings` map. The selected
factory must be a synchronous context manager yielding an initialized SDK
controller. See [SDK contract](docs/specs/WMA.03-sdk-client.md).
Alternatively, supply a module implementing `Wotex.Matter.Client`. The driver
owns the pinned SDK, secure fabric storage,
commissioning, attestation, sessions and per-path status validation. Missing
transport, crashed driver, invalid return and missing write input all fail.
Failed writes/invokes have unknown effect; the library never retries them.
No real SDK/device parity is claimed by the fake-port contract tests.

The SDK adapter forwards explicit `timed_request_timeout_ms` for writes/invokes.
Subscription delivery and full device qualification need further integration.
The current `member` field enforces
width and excludes the wildcard; the driver must validate attribute/command
semantics against its pinned data model. No CSA certification is claimed.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :matter, :request, :stop]`, with bounded status
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

See [implemented profile](docs/specs/WMA.02-implemented-profile.md),
[primary sources](docs/provenance/primary-sources.md) and
[executable evidence](docs/provenance/executable-evidence.md).

## Development

Use Elixir 1.18 or newer with compatible OTP. Local Wotex core and Runtime
checkouts require explicit `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Run `mix check` before commits. It checks formatting, compiles with warnings as
errors, and runs the default test suite. Wider checks belong to release readiness.
The separate `elixir bin/check_p01_native.exs` lane compiles and tests the P01
descriptor/value unit on the pinned Linux x86_64 reference toolchain with and
without AddressSanitizer and UndefinedBehaviorSanitizer.
Optional interoperability suites fail if invoked without their required peer.
No remote repository, published package or publication action is implied.

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WMA-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](docs/specs/WMA.11-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and end-to-end workflows.
Its [concrete corpus](docs/specs/fixtures/contract-v1.json) is partially executed:
the P01 pure cases run in the default suite, while later controller and lifecycle
cases remain unexecuted. The scenario tables alone are not executable acceptance
evidence.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WMA.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.
