# Wotex BLE

Consumer-neutral BLE library for W3C Web of Things consumers.
Development version: `0.1.0-dev`.

UUID/address values and a real Linux BlueZ GATT adapter are implemented.
`BlueZ` invokes an explicitly supplied `busctl` executable without a shell,
checks the selected service/characteristic, bounds output and duration, and
performs acknowledged writes. It requires an already connected BlueZ device and
an existing characteristic object path. `connect/1` validates this configuration;
GATT I/O happens on request. No radio, OS service or simulator starts implicitly.

```elixir
{:ok, uuid} = Wotex.BLE.UUID.normalize(0x2A19)
{:ok, wire_uuid} = Wotex.BLE.UUID.encode(uuid)
{:ok, ^uuid} = Wotex.BLE.UUID.decode(wire_uuid)
```

Supply `client: Wotex.BLE.BlueZ`, absolute `executable`, BlueZ `object_path`,
`service` and `characteristic` to `connect/1`. Send
`%{type: :read, service: 0x180F, characteristic: 0x2A19}` or an explicit
`:write` with binary `value`. UUIDs accept short integers/text or canonical
128-bit text. Handles are 1..65535; values are at most 512 bytes.
Discovery, pairing, connection establishment, notifications, indication ACKs,
MTU negotiation and device interoperability are separate gates. BlueZ owns
those device facilities. No BlueHeron peripheral API is represented as a central.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :ble, :request, :stop]`, with bounded status
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

See [implemented profile](docs/specs/WBL.02-implemented-profile.md),
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
