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
CASE interactions and subscriptions. P03 implements the controller owner,
durable authority, production attestation verifier and framed Port. Interaction
Model requests, commissioning and subscriptions remain later work packages.
The current Python factory adapter remains a separate narrow baseline.

[WMA.13](docs/specs/WMA.13-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. `mix run bin/check_p03_native.exs` rebuilds
and tests the P03 host in a disposable pinned Linux environment. The later
`mix wotex.native.build`, `mix wotex.software.build` and
`mix wotex.software.run` commands remain specified implementation work. Upstream
SDK Python is used only while generating and building native SDK sources.

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
not wired to that one-shot adapter. No Python runtime or native SDK binary is
bundled. The packaged first-party controller source is built explicitly outside
the Hex archive; commissioning remains unfinished.

The packaged native source includes the P02 `PersistentStorageDelegate`: it
creates or opens an explicitly identified controller store, holds an exclusive
lock, validates bounded versioned state, and commits each opaque SDK value by a
same-directory fsynced rename. P03 connects that store to one first-party
`DeviceCommissioner`, generates or reopens the controller root and Identity
Protection Key with SDK crypto, loads an explicit Product Attestation Authority
trust directory, and runs controller setup and shutdown through a direct BEAM
Port. Loading the library starts no process or native executable. P04–P09 still
own Interaction Model operations, subscriptions, commissioning workflows,
Runtime integration and software-peer proof.

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

To open the P03 controller owner, build `wotex-matter-host` with the separate
native lane and pass its absolute path explicitly:

```elixir
{:ok, session} =
  Wotex.Matter.connect(
    client: Wotex.Matter.Native,
    executable: "/opt/wotex/bin/wotex-matter-host",
    lifecycle: :persistent,
    storage_path: "/var/lib/example-matter/controller-1",
    storage_mode: :open_existing,
    authority: :stored,
    vendor_id: 0xFFF1,
    fabric_id: 1,
    controller_node_id: 2,
    paa_trust_store: "/etc/example-matter/paa"
  )

{:ok, %{"status" => "ready", "fabric_id" => 1}} =
  Wotex.Matter.Native.health(session.handle)

:ok = Wotex.Matter.disconnect(session)
```

Use `storage_mode: :create_new` with `authority: :generate_root` only for an
explicitly authorized new controller directory. P03 health and lifecycle calls
are implemented; data interactions currently return `:not_supported`.

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
`elixir bin/check_p02_native.exs` separately verifies the pinned SDK source and
gitlink inputs, then exercises the durable store under the same normal and
sanitizer toolchains, including lock and crash-boundary behavior.
`elixir bin/check_p02_advisories.exs` separately queries OSV for advisories
against the four exact P02 source revisions; it is a live release check rather
than a substitute for the content-pinned native lane.
`WOTEX_PATH_DEPS=1 mix run bin/check_p03_native.exs` separately rebuilds the
first-party controller from the exact SDK, gitlink, generator and tool inputs,
then runs normal and sanitizer lifecycle, failure, load and cleanup checks.
`WOTEX_PATH_DEPS=1 mix run bin/check_p03_advisories.exs` performs the associated
live OSV audit. Neither P03 command belongs to routine `mix check`.
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
the P01 pure cases run in the default suite and the WMA-F07 controller lifecycle
cases run in the separate P03 native lane. Later Interaction Model,
commissioning and subscription cases remain unexecuted. The scenario tables
alone are not executable acceptance evidence.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WMA.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.
