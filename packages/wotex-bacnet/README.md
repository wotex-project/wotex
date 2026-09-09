# Wotex BACnet

Consumer-neutral BACnet interactions for W3C Web of Things consumers.

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_bacnet.svg)](https://hex.pm/packages/wotex_bacnet)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_bacnet)
[![CI](https://github.com/wotex-project/wotex-bacnet/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-bacnet/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-bacnet/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-bacnet)
[![License](https://img.shields.io/hexpm/l/wotex_bacnet.svg)](https://github.com/wotex-project/wotex-bacnet/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This is a development checkout with an unstable public API. The ordered plan
tracks the remaining software verification and implementation work.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

A local consumer can select this checkout explicitly:

```elixir
def deps do
  [{:wotex_bacnet, path: "../wotex-bacnet"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

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
The complete stress workflow and final source/archive cohorts
remain open in WBA-P06. Routing/BBMD, MS/TP and
BACnet/SC are unsupported.

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

See [implemented profile](docs/specs/WBA.02-implemented-profile.md),
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

The accepted software fixture entry points are
`mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS`. They are specified work; the existing
shell scripts exercise only the current read/write fixture. No production
native executable build task is required for this BEAM client.

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WBA-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenario families.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [WBA.11 standalone client contract](docs/specs/WBA.11-standalone-client-and-preservation.md)
records required native APIs, preserved protocol assets and concrete specified
fixtures. The concrete standalone corpus has local executable bindings; independent
peer evidence and the full software acceptance matrix remain separate.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WBA.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.
