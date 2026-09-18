# Wotex BACnet

**Consumer-neutral BACnet interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_bacnet.svg)](https://hex.pm/packages/wotex_bacnet)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_bacnet)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_bacnet.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-bacnet/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This package is under development and its public API is unstable. The ordered
plan records the accepted software profile and its exact evidence boundary.

Build handoff: [software implementation sequence](../../docs/packages/wotex-bacnet/plans/software-implementation.md).

## Installation

Wotex BACnet 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual; Hex
resolves `wotex` and `wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_bacnet, "~> 0.1"}
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
    {:wotex_bacnet,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-bacnet",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_bacnet, path: "../wotex/packages/wotex-bacnet", override: true}
```

Path dependencies prove nothing about a released artifact.

## Implemented profile

The production client runs in Elixir/OTP using pinned BACstack 0.0.1. It requires
no Python runtime, native executable or NIF. Independent C-stack processes belong
only to explicit software fixtures. ReadProperty and WriteProperty use the same
BEAM transport and codec ownership. `Value` provides
explicit scalar conversion for declared Form types and retains native tags. The adapter accepts only
matching acknowledgments and retains tagged values. Abort, Error, Reject,
missing ACK and wrong object/property/index all fail. `Address` preserves array
index zero and explicit priorities. `IPv4` owns the complete stack with zero APDU
retries; `BACstack` borrows an already supervised Client and never stops it.

The owned UDP transport admits at most eight datagrams across its complete
receive pipeline. Credits return after client consumption; 100 milliseconds of
credit starvation closes the stack with `:slow_consumer`. Borrowed Runtime COV
requires `receive_policy: :wotex_bounded` and a verified live Wotex ingress
transport. Native borrowed read/write defaults to `:consumer_managed` and makes
no claim about the consumer's receive queues.

## Quick start

```elixir
{:ok, address} = Wotex.BACnet.Address.new(%{
  object_type: :analog_output, instance: 0, property: :present_value
})
{:ok, session} = Wotex.BACnet.connect(
  client: Wotex.BACnet.IPv4,
  local_ip: {192, 0, 2, 10}, local_port: 47809,
  destination: {{192, 0, 2, 20}, 47808}, timeout: 3000
)
try do
  Wotex.BACnet.send(session, Map.put(Map.from_struct(address), :type, :read_property))
after
  Wotex.BACnet.disconnect(session)
end
```

Use an IP assigned to a broadcast-capable interface. Upstream BACstack does not
support binding a loopback interface; explicit `local_ip: :none` binds all
interfaces and is provided for isolated fixtures. It is never selected by default.
For borrowed clients, writes require `writes: true`; the consumer must disable
BACstack retries itself. A timeout cannot retract an emitted APDU or cancel a pending request held by
a raw borrowed BACstack Client. The owned `IPv4` adapter checks caller liveness
and the absolute deadline again before transmission.

Native helpers provide typed single-Property access, sequential batches of up
to 64 distinct Properties, and bounded Who-Is discovery with an explicitly
configured destination. Discovery results never replace the configured route.

Object and Property Change of Value (COV) subscriptions support finite leases,
renewal, confirmed and unconfirmed reports, finite receiver queues, and cancellation.
The WBA-S03a owned ingress bound covers suspended stack owners and clients;
the consumption window also bounds packets waiting before the COV receiver.
They require the owned `IPv4` client or a verified Wotex stack wrapper; a raw
borrowed BACstack Client supports read/write operations only. Native and real
Runtime lifecycle tests exercise COV ownership. The independent C fixture tests
object and Property COV, discovery, batch reads, priority release and
acknowledgment loss. Property tests include the public Runtime observation path.
Receiver-death stress covers 100 cycles with another association retained.
The complete WBA-P06 software workflow is accepted for the source, peers and
toolchains recorded in executable evidence. A separate archive lane rebuilds
exact core, Runtime and BACnet archives and exercises an isolated reference
consumer without live-source fallback. Routing/BBMD, MS/TP and BACnet/SC are
unsupported.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :bacnet, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Library-generated errors contain structured, bounded diagnostics; custom clients
are responsible for keeping their Error details bounded and free of secrets.
Unknown Form extension terms survive mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; `receive/2` is unsupported. `health_check/1`
requires a probe, while `health_check/2` performs an explicit validated read.
Subscriptions return an opaque handle bound to the original native session. Callback names alone do not establish consumer behavioral parity.
Consumer integration requires separate differential and interoperability evidence.

`profile/0` returns the native read/write Runtime profile. `profile(:ip_cov)`
adds Property observation through a consumer-owned Runtime subscription. Forms
that omit `contentType` retain that omission; explicit content types are rejected
because this profile supplies native values rather than a serialization codec.
Runtime request tests preserve false, zero, empty values, typed metadata and
request identity, and reject positive replies that arrive after the deadline.

See [implemented profile](../../docs/packages/wotex-bacnet/specs/WBA.03-implemented-profile.md),
[primary sources](../../docs/packages/wotex-bacnet/provenance/primary-sources.md) and
[executable evidence](../../docs/packages/wotex-bacnet/provenance/executable-evidence.md).

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-bacnet test test/wotex/bacnet/value_test.exs  # one test file
mix check.fast --package wotex-bacnet                       # compile, format, Credo, tests
mix pkg wotex-bacnet check --no-retry                       # full gate
mix native.lint --package wotex-bacnet                      # clang-format on changed C/C++ lines
mix native.test --package wotex-bacnet                      # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-bacnet`. It compiles with warnings as errors, checks the lock
and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the coverage floor (`mix coveralls`), Dialyzer and
`git diff --check`, then runs `bin/check_archive.exs` and
`bin/check_application_free.exs`. The archive check builds the exact `wotex`,
`wotex_runtime` and `wotex_bacnet` archives from `packages/` without path
dependencies and exercises an isolated reference consumer against them; the
second check proves that the package defines no Application callback.

The ordinary test run needs a POSIX C11 compiler (`cc`): the software-fixture
command guardian in `test/interop/native/` is compiled and exercised by
`test/software/command_test.exs`. Tests tagged `interop`, `software`,
`hardware` or `peer_shutdown` are excluded; they need the independent peer and
fail if selected without it.

### Software peer lane

The independent BACnet C-stack peer is an explicit lane, outside the gate and
the archive evidence. Pass a disposable absolute directory outside
`packages/wotex-bacnet`:

```console
mix pkg wotex-bacnet wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-bacnet wotex.software.run --workspace /absolute/disposable/dir
```

The build needs Docker, `cc` (or `$CC`), `curl` and network access. It
verifies the locked BACstack Hex archive and the pinned C-stack source archive
from `priv/fixtures/software-sources-v1.json`, builds normal and ASan/UBSan
peers in a Linux image from `test/interop/cstack/Dockerfile.software` and
writes a verified manifest into the workspace. The run needs Docker and that
built workspace; it runs the shared and terminal-shutdown suites against both
peers in owned containers and records cleanup receipts. The fully qualified
task names are `wotex.bacnet.software.build` and `wotex.bacnet.software.run`;
`test/interop/build_software.sh` and `run_software.sh` are thin delegates.
No production native build exists for this BEAM client.

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-bacnet/plans/software-implementation.md)
and [specifications](https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-bacnet/specs) define the accepted software
profile with exact behavior, limits, failure transitions and acceptance scenario
families. Acceptance is limited to the source, dependency, fixture and toolchain
identities in executable evidence. Required software peers are separate from
physical-device tests.

The [WBA.05 standalone client contract](../../docs/packages/wotex-bacnet/specs/WBA.05-standalone-client-and-preservation.md)
records required native APIs, preserved protocol assets and concrete specified
fixtures. The concrete standalone corpus has local executable bindings and the
independent peer matrix is recorded separately in executable evidence.

The [specification catalogue](../../docs/packages/wotex-bacnet/specs/catalogue.yaml) distinguishes implemented
software profiles from separately scoped nonclaims. The [Wotex integration contract](../../docs/packages/wotex-bacnet/specs/WBA.06-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. It does not claim publication, hardware, BTL or
full BACnet conformance, or downstream consumer parity.

## License

Wotex BACnet is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-bacnet/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-bacnet/NOTICE).
