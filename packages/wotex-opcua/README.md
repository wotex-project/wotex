# Wotex OPC UA

Consumer-neutral OPC Unified Architecture interactions for W3C Web of Things consumers.

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_opcua.svg)](https://hex.pm/packages/wotex_opcua)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_opcua)
[![CI](https://github.com/wotex-project/wotex-opcua/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-opcua/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-opcua/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-opcua)
[![License](https://img.shields.io/hexpm/l/wotex_opcua.svg)](https://github.com/wotex-project/wotex-opcua/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This is a development checkout with an unstable public API. The ordered plan
tracks the remaining software implementation and verification work.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

A local consumer can select this checkout explicitly:

```elixir
def deps do
  [{:wotex_opcua, path: "../wotex-opcua"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

## Implemented profile

The library contains all four NodeId kinds, strict scalar binary codecs, bounded
UA TCP chunk framing, Form mapping and a real `Asyncua` adapter. The adapter uses
asyncua 2.0.1 in an explicitly supplied Python environment. It performs
native read/write/browse/call over Basic256Sha256 SignAndEncrypt, with no
reconnect or write retry. Browse returns child NodeId strings; bounded
BrowseNext ownership and typed ReferenceDescription results remain target work. Each request opens and closes its own secure channel and session.
`connect/1` validates configuration; network authentication occurs on request.

## Quick start

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
such as `%{type: "Double", value: 42.5}`. Native bridge requests carry ByteString
values as Base64; `Wotex.OPCUA.Value.encode/2` accepts a BEAM binary and creates
that bridge representation.
Subscriptions, persistent sessions, issuer-chain revocation beyond this profile,
user credentials, additional security policies and certification remain gates.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :opcua, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Library-generated failures contain structured diagnostics. Custom clients must
keep their supplied Error details bounded and free of secrets. Unknown Form
extension terms survive mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; unsupported receive/subscription calls fail
explicitly. Callback names alone do not establish consumer behavioral parity.
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this repository.

Runtime Form mapping currently supports Property reads and writes only. Native
Browse and Call do not provide Runtime Action or aggregate operations. Explicit
profile factories, typed arrays and DataValue metadata, persistent secure
sessions, subscriptions, and complete Runtime validation remain specified work.
Current result projection checks StatusCode envelopes and ByteString decoding;
it does not validate every returned Variant type or payload. The strict media
selector rejection required by WOP.12 has not yet been implemented.

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
profile with exact behavior, limits, failure transitions and acceptance scenario families.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [WOP.11 standalone client contract](docs/specs/WOP.11-standalone-client-and-preservation.md)
records required native APIs, preserved protocol assets and concrete specified
fixtures. These cases are not passing evidence until executable bindings run.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WOP.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.
