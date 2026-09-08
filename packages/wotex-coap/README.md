# Wotex CoAP

Consumer-neutral CoAP library for W3C Web of Things consumers.
Development version: `0.1.0-dev`.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

The UDP client performs bounded confirmable/non-confirmable exchanges, correlates
endpoint/token/Message ID, handles separate responses and retransmits the same
confirmable datagram. Codec, block descriptors and Observe
serial arithmetic are independently usable pure values. Whole-body Block1 uploads
and Block2 downloads run serially under one deadline and enforce representation
identity, acknowledgment and allocation limits. Network Observe remains pending.
DTLS, OSCORE, multicast, extended tokens and discovery are separate graduation gates.

```elixir
{:ok, session} = Wotex.CoAP.connect(host: "127.0.0.1", port: 5683, timeout: 3000)
try do
  Wotex.CoAP.send(session, %{method: :get, path: "/reading"})
after
  Wotex.CoAP.disconnect(session)
end
```

`Mapping` supports the documented draft `cov:` subset and JSON, UTF-8 text or
opaque binary content. JSON null writes encode as `null`. Runtime spends one
finite deadline across opening and exchange, and always closes its socket.
Numeric IPv4/IPv6 destinations are required. A session serializes requests;
its owner is monitored. Datagrams are bounded to 1152 bytes; complete bodies to 1 MiB.
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
receive queue is fabricated; unsupported receive/subscription calls fail
explicitly. Callback names alone do not establish consumer behavioral parity.
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this repository.

See [implemented profile](docs/specs/WCO.02-implemented-profile.md),
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
and [specification index](docs/specs/WCO-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance vectors.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.
