# Wotex BACnet

Consumer-neutral BACnet library for W3C Web of Things consumers.
Development version: `0.1.0-dev`.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

ReadProperty and WriteProperty use pinned BACstack 0.0.1. `Value` provides
explicit scalar conversion for declared Form types and retains native tags. The adapter accepts only
matching acknowledgments and retains tagged values. Abort, Error, Reject,
missing ACK and wrong object/property/index all fail. `Address` preserves array
index zero and explicit priorities. `IPv4` owns the complete stack with zero APDU
retries; `BACstack` borrows an already supervised Client and never stops it.

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
BACstack retries itself. A wrapper timeout cannot cancel BACstack's internal
pending operation. Use `IPv4` when this library should own that configuration.

COV delivery/renewal, routing/BBMD, MS/TP and BACnet/SC are not implemented here.
The COV cancellation requirements are documented for later graduation.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :bacnet, :request, :stop]`, with bounded status
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

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WBA-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance vectors.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.
