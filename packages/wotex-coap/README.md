# Wotex CoAP

**Consumer-neutral Constrained Application Protocol interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_coap.svg)](https://hex.pm/packages/wotex_coap)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_coap)
[![CI](https://github.com/wotex-project/wotex-coap/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-coap/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-coap/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-coap)
[![License](https://img.shields.io/hexpm/l/wotex_coap.svg)](https://github.com/wotex-project/wotex-coap/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This is a development checkout. The public API remains unstable, and the
ordered software implementation plan is not complete.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

This development checkout is prepared as the `wotex_coap` Hex package but does
not assert that a release has been published. A sibling-checkout consumer can
select it explicitly:

```elixir
def deps do
  [{:wotex_coap, path: "../wotex-coap"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

## Implemented profile

The UDP client performs bounded confirmable/non-confirmable exchanges, correlates
endpoint/token/Message ID, handles separate responses and retransmits the same
confirmable datagram. Codec, block descriptors and Observe
serial arithmetic are independently usable pure values. Whole-body Block1 uploads
and Block2 downloads run serially under one deadline and enforce representation
identity, acknowledgment and allocation limits. Native Observe owns its initial
representation, renewal, notification freshness, cancellation, and cleanup.
Discovery parses bounded CoRE Link Format results without following the links.

Native `coaps` sessions support explicit DTLS 1.2 PSK and PKI credentials through
OTP SSL. PSK exchanges and Observe have independent pinned libcoap evidence;
PKI currently has real OTP peer tests. Independent PKI evidence, OSCORE,
and the final software matrix remain ordered work.
Multicast and extended tokens are outside the implemented profile.

## Quick start

```elixir
{:ok, session} = Wotex.CoAP.connect(host: "127.0.0.1", port: 5683, timeout: 3000)
try do
  Wotex.CoAP.send(session, %{method: :get, path: "/reading"})
after
  Wotex.CoAP.disconnect(session)
end
```

`Mapping` supports the documented draft `cov:` subset and JSON, UTF-8 text or
opaque binary content. JSON null writes encode as `null`. Runtime unary requests
spend one finite deadline across opening and exchange and close their socket.
Runtime Property observations and Event subscriptions use an owned Observe relay
with complete-body decoding and bounded cleanup. DTLS unary requests accept one
typed immediate or configured Security value; subscriptions require configured
security and a nil immediate credential. UDP routes reject credentials.
`Wotex.CoAP.profile/0` selects unary UDP operations;
`Wotex.CoAP.profile(:udp_observe)` selects unary operations and Observe streams.
`Wotex.CoAP.profile(:dtls)` selects authenticated DTLS unary operations and streams.
All admit JSON, UTF-8 text and opaque bytes. OSCORE remains unsupported.
`Wotex.CoAP.Security.new/1` validates and redacts the fixed-suite OSCORE
credential value without reading its durable store. The planned native owner
must still validate and consume that store before an OSCORE session can open.
Numeric IPv4/IPv6 destinations are required. A session serializes requests;
its owner is monitored. Datagrams are bounded to 1152 bytes; complete bodies to 1 MiB.
Capabilities expose these as `max_datagram_size` and `max_body_size`.
The legacy `max_payload_size` key remains a 1152-byte datagram-limit alias,
not the complete-body ceiling.
See the [blockwise contract](docs/specs/WCO.03-blockwise.md) for configurable
block sizes, aggregate budgets and the atomic upload profile.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :coap, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Errors are structured and credential-free. Unknown Form extension terms survive
mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; `receive/2` fails explicitly. Native subscriptions
return an exact owned handle after validating the initial complete representation.
Callback names alone do not establish consumer behavioral parity.
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this repository.

See [implemented profile](docs/specs/WCO.02-implemented-profile.md),
[primary sources](docs/provenance/primary-sources.md) and
[executable evidence](docs/provenance/executable-evidence.md).

## Development

Use Elixir 1.18 or newer with compatible OTP. Local Wotex core and Runtime
checkouts require explicit `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check --no-retry`. Normal dependency resolution uses Hex versions.
Plain `mix check --no-retry` is the complete library gate: locked dependencies,
formatting, warnings-as-errors compilation, one coverage test run, strict static
checks, dependency audits, documentation, application-boundary checks and an
external archive build/compilation. The coverage floor is 95%. `mix test` is the
fast development loop; no separate release profile enables additional checks.
The archive and its digest remain in the printed system-temporary directory.
Its compilation uses the tested dependency cohort, not released-artifact adoption.
Optional interoperability suites fail if invoked without their required peer.
No remote repository, published package or publication action is implied.

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WCO-index.md) define the remaining software
profile with exact behavior, limits, failure transitions, acceptance scenarios
and concrete fixtures.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](docs/specs/WCO.11-standalone-client-and-preservation.md)
defines native workflows and feature-preservation obligations. Its concrete
fixture corpus contains specified cases; execution results remain in provenance.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WCO.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.

## Native build and software orchestration

[WCO.13](docs/specs/WCO.13-native-build-and-software-evidence.md) defines
the planned `mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS` interfaces. Protocol execution remains
BEAM UDP, OTP DTLS and a planned explicit libcoap OSCORE Port.
`Wotex.CoAP.NativeBackend.verify/1` can validate the content identity of an
explicit native executable and manifest without starting it. Connection
dispatch to that executable remains planned. `Wotex.CoAP.Native.Wire` validates
bounded ready and response frames and constructs complete Messages without
starting a process. `Wotex.CoAP.Native.Command` encodes exact bounded commands
with monotonic identities scoped to a generation. `Wotex.CoAP.Native.Body`
withholds streamed bytes until exact length and hash verification.
`Wotex.CoAP.Native.Report` correlates report/body
envelopes and verifies Message metadata. `Wotex.CoAP.Native.ReportLedger` bounds
the eight-frame credit window and serializes cumulative acknowledgments. Port
ownership and live credit integration remain planned.
Existing Python files perform test/build orchestration only. Their recorded
results do not establish acceptance of the planned Mix tasks.
