# Wotex Matter

Consumer-neutral Matter library for W3C Web of Things consumers.
Development version: `0.1.0-dev`.

The implemented package provides fabric-scoped interaction paths, bounded TLV,
a validated `Client` behaviour, compatibility callbacks and WoT Form/Runtime
mapping. TLV preserves tags, explicit scalar widths, null and containers while
bounding bytes, nodes and nesting. This is a controller integration library;
a bundled CASE/PASE/Interaction Model transport is not yet implemented.

```elixir
{:ok, path} = Wotex.Matter.Address.new(%{
  fabric_id: 1, node_id: 2, endpoint: 1, cluster: 6, member: 0
})
{:ok, bytes} = Wotex.Matter.TLV.encode([
  %{tag: {:context, 1}, type: :u8, value: 42}
])
{:ok, [%{value: 42}]} = Wotex.Matter.TLV.decode(bytes)
```

A consumer explicitly supplies `client: ControllerModule` implementing
`Wotex.Matter.Client`. The driver owns the pinned SDK, secure fabric storage,
commissioning, attestation, sessions and per-path status validation. Missing
transport, crashed driver, invalid return and missing write input all fail.
Failed writes/invokes have unknown effect; the library never retries them.
No real SDK/device parity is claimed by the fake-port contract tests.

Timed interactions, subscription delivery and full cluster-specific reserved
identifier semantics need SDK integration. The current `member` field enforces
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
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this repository.

See [implemented profile](docs/specs/WMA.02-implemented-profile.md),
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
