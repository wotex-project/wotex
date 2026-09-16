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

The current code contains scalar, Variant, DataValue, NodeId, expanded identity, name and reference
codecs, UA TCP framing, Property Form
mapping, a limited per-request asyncua adapter and an explicitly selected
partial `Open62541` client. The latter opens persistent or one-shot secure
Sessions and performs typed Value Read/Write, Method Call and bounded child
Browse through C without runtime Python. WOP.02 and executable evidence bound
its actual behavior. One-shot Read/Write/Call successes preserve the older
adapter's result shapes. A persistent native Session can also return one
complete page of seven-field typed references. The C owner now has a single
local-token BrowseNext/release path. Persistent typed Browse exposes bound
handles, `next`, `release` and bounded `all`; deterministic fixtures and a
secure same-stack C peer exercise wire pagination. Child-list Browse collects
pages on one persistent or one-shot Session. Independent-peer BrowseNext proof
remains open. Complete compatibility
projection, subscriptions and lifecycle work remain.
The Runtime Form mapper preserves raw ByteString bytes for the explicitly
selected native one-shot client. Runtime reads also decode validated flat
ByteString arrays to BEAM binaries, and explicitly typed flat ByteString arrays
can be written through the same native Form path. The full Runtime profile remains open.

## Native software contract

The accepted architecture is `Wotex.OPCUA.Open62541`: an Elixir API with an
explicitly owned persistent open62541 C executable. Runtime requires no Python.
The pinned SDK owns secure-channel cryptography and service codecs; the package
owns typed values, deadlines, bounded IPC, cancellation and Runtime integration.
asyncua is solely an independent software peer in this target.

[WOP.13](docs/specs/WOP.13-native-executable.md) fixes source digests, security,
credit flow control, process ownership and executable acceptance.
`mix wotex.native.build --workspace ABS` builds the packaged native bootstrap
from verified static SDK/OpenSSL sources and writes a content-bound receipt.
The qualified task is `mix wotex.opcua.native.build`; the shorter name is this
root project's alias. CMake 3.20+, a C11 compiler, make, Perl, Python 3, archive
utilities and curl 8.4.0+ are explicit build prerequisites. Failed builds retain
diagnostic files and require a fresh workspace.

WOP-P00 accepts this source/build/bootstrap and process-custody boundary for the
exact cohorts in executable evidence. The gate compiles and tests the portable
guardian on macOS. Linux also runs strict AddressSanitizer/UndefinedBehaviorSanitizer
and separate LeakSanitizer executions of WOP-G01 through WOP-G09. P00 does not
implement a native Session, service framing, security activation or subscription.

WOP-P01 accepts the pure typed-value, DataValue, identity and reference codecs
and their production open62541 value projection for the exact vectors and
cohorts in executable evidence. The native contract runner binds WOP-X-F01
through WOP-X-F16 without a Session or network peer. Namespace translation is a
pure exact-match primitive; Session-owned NamespaceArray acquisition and all
service, security and subscription behavior remain later packets.

The first P02 slice connects bounded JSON-line framing and outer request
validation to the actual C executable. Its tests exercise split lines, closed
fields, integer limits and expired deadlines. Admitted requests still terminate
with `unsupported_protocol`; native Session, normal output credits and services remain open.
The pure `Native.Frame` encoder translates the ready clock sample into a native
deadline and builds the exact request line used by the real-process build test.
The internal native host now performs one generation-matched terminal-only
exchange through custody. It reports finite errors; no native Session or
successful service response is exposed.
The C ingress also rejects malformed `open` configuration, including insecure
policy or mode selection, before it touches the SDK network stack. The native
credential preflight now checks DER/PKCS#8, RSA keys, direct-CA trust, SAN/URI
identity, certificate usage, signatures and the current issuer CRL. Invalid
credentials return `certificate_invalid` without network access. Valid credentials
still fail closed pending SDK verification integration and Session ownership.
The owner also sends a generation-bound initial credit before the request; normal
output and replenishment are still part of the unfinished native service path.
The SDK build also applies a digest-checked patch to preserve the server's
revised Session timeout. A separate C loopback test verifies fractional and
integer revisions and their lifetime through real SDK Sessions. That isolated
test uses Security None and does not accept the secure production Session path.

`mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS` remain specified work. Bootstrap build
success does not establish a native Session or accept the native protocol profile.
The mandatory `mix check` gate performs a fresh native build and receipt fault
tests in an owned temporary workspace; ordinary `mix test` excludes that lane.

## Quick start

This deterministic value example uses the current public API:

```elixir
{:ok, node} = Wotex.OPCUA.Address.new("ns=2;s=temperature")
{:ok, bytes} = Wotex.OPCUA.Binary.encode_node_id(node)
{:ok, ^node, <<>>} = Wotex.OPCUA.Binary.decode_node_id(bytes)
```

The native target accepts explicit executable identity, endpoint, application
certificate/key, server certificate pin, direct-CA trust and current CRL.
SignAndEncrypt with one of the three S03 policies and an explicit user-token mode
is mandatory. Typed values retain array/null distinctions, DataValue status and
100 ns timestamps. The native target owns bounded continuations; subscriptions
retain revised parameters and complete report metadata. Unsupported security,
malformed values and exhausted budgets fail with structured errors. Acknowledged
writes and method calls do not establish canonical Property state.

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
Consumer parity is a separate differential and interoperability claim.

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
`WOTEX_PATH_DEPS=1 mix check --no-retry`. Normal dependency resolution uses Hex
versions. `mix test` is the fast loop. The default `mix check --no-retry` is the
complete library gate: locked and unused dependencies, warnings-as-errors,
formatting, strict static analysis, coverage as the only ExUnit pass, audits,
documentation, Dialyzer, a fresh pinned native build/CTest, platform-applicable
custody sanitizer lanes, archive inspection and the Application-free check.
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
