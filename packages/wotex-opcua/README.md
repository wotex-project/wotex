# Wotex OPC UA

Consumer-neutral OPC UA library for W3C Web of Things consumers.
Development version: `0.1.0-dev`.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

The library contains all four NodeId kinds, strict scalar binary codecs, bounded
UA TCP chunk framing, Form mapping and a real `Asyncua` adapter. The adapter uses
asyncua 2.0.1 in an explicitly supplied Python environment. It performs
read/write/browse/call over Basic256Sha256 SignAndEncrypt, with no reconnect or
write retry. Each request opens and closes its own secure channel and session.
`connect/1` validates configuration; network authentication occurs on request.

Install the exact bridge environment explicitly with
`python3 -m venv /chosen/environment` and
`/chosen/environment/bin/pip install -r priv/requirements.txt`.
There is no dependency download or Python startup at package load.

```elixir
{:ok, node} = Wotex.OPCUA.Address.new("ns=2;s=temperature")
{:ok, bytes} = Wotex.OPCUA.Binary.encode_node_id(node)
{:ok, ^node, <<>>} = Wotex.OPCUA.Binary.decode_node_id(bytes)
```

Supply `client: Wotex.OPCUA.Asyncua`, `executable`, `endpoint`, `certificate`,
`private_key`, `client_uri`, `server_uri`, `server_certificate`,
`issuer_certificate`, `trust_certificates` and `crl` to `connect/1`.
All certificate/key/CRL/executable paths are absolute and caller-owned.
`trust_certificates` is a nonempty list of trusted CA certificate paths.
The supported trust profile is a leaf issued directly by a trusted, self-signed
CA: intermediate chains are rejected. The issuer's CRL must be signed, current,
and not revoke the leaf. Server certificate pin, exact DNS/IP SAN, application
URI, validity and key usages are checked; client certificate URI/time/usages
are checked too. Missing checks never enable SecurityPolicy None.
The adapter currently uses anonymous user identity over the authenticated
application channel; the server must grant appropriate permissions.

Native read results retain Variant type and StatusCode. Runtime separates the
Property value from this metadata. Writes require explicit values
such as `%{type: "Double", value: 42.5}`; ByteString input is base64.
Subscriptions, persistent sessions, issuer-chain revocation beyond this profile,
user credentials, additional security policies and certification remain gates.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :opcua, :request, :stop]`, with bounded status
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

See [protocol and graduation contract](docs/specs/WOP.01-protocol.md),
[implemented profile](docs/specs/WOP.02-implemented-profile.md),
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
and [specification index](docs/specs/WOP-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance vectors.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.
