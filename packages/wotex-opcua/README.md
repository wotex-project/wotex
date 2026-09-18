# Wotex OPC UA

**Consumer-neutral OPC Unified Architecture interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_opcua.svg)](https://hex.pm/packages/wotex_opcua)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_opcua)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_opcua.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-opcua/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Native software contract](#native-software-contract) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This package is under development and its public API is unstable. The ordered
plan tracks the remaining software implementation and verification work.

Build handoff: [software implementation sequence](../../docs/packages/wotex-opcua/plans/software-implementation.md).

## Installation

Wotex OPC UA 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual; Hex
resolves `wotex` and `wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_opcua, "~> 0.1"}
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
    {:wotex_opcua,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-opcua",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_opcua, path: "../wotex/packages/wotex-opcua", override: true}
```

Path dependencies prove nothing about a released artifact. The native
executable is not built on dependency load; a consumer builds it explicitly
with the task described under [Development](#development).

## Implemented profile

The current code contains scalar, Variant, DataValue, NodeId, expanded identity, name and reference
codecs, UA TCP framing, Property Form
mapping and an explicitly selected partial `Open62541` client. It opens persistent or one-shot secure
Sessions and performs typed Value Read/Write, Method Call and bounded child
Browse through C without runtime Python. The former Python runtime adapter is
removed; asyncua remains an independent test peer. WOP.02 and executable evidence bound
its actual behavior. One-shot Read/Write/Call successes preserve the recorded
result shapes. A persistent native Session can also return one
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

[WOP.13](../../docs/packages/wotex-opcua/specs/WOP.13-native-executable.md) fixes source digests, security,
credit flow control, process ownership and executable acceptance.
`mix native.build --package wotex-opcua --workspace ABS` from the repository
root (inside the package, `mix wotex.opcua.native.build` or its alias
`mix wotex.native.build`) builds the packaged native bootstrap from verified
static SDK/OpenSSL sources and writes a content-bound receipt. CMake 3.20+,
a C11 compiler, make, Perl, Python 3, archive utilities and curl 8.4.0+ are
explicit build prerequisites. Failed builds retain diagnostic files and require
a fresh workspace.

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

`mix pkg wotex-opcua wotex.software.build --workspace ABS` and
`mix pkg wotex-opcua wotex.software.run --workspace ABS` build and run the software acceptance
lanes; WOP-P08 acceptance of the complete software profile remains open. Bootstrap
build success does not establish a native Session or accept the native protocol profile.
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

See [protocol and graduation contract](../../docs/packages/wotex-opcua/specs/WOP.01-protocol.md),
[implemented profile](../../docs/packages/wotex-opcua/specs/WOP.02-implemented-profile.md),
[primary sources](../../docs/packages/wotex-opcua/provenance/primary-sources.md) and
[executable evidence](../../docs/packages/wotex-opcua/provenance/executable-evidence.md).

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-opcua test test/wotex/opcua/value_test.exs  # one test file
mix check.fast --package wotex-opcua                      # compile, format, Credo, tests
mix pkg wotex-opcua check --no-retry                      # full gate
mix native.lint --package wotex-opcua                     # clang-format on changed C/C++ lines
mix native.test --package wotex-opcua                     # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).

The ordinary test run excludes the `interop`, `software`, `hardware` and
`native_build` tags. It needs a C11 compiler (`cc`): the native client, JSON,
custody, host and command tests compile first-party C from `priv/native/` and
`test/native/`.

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-opcua`. It compiles with warnings as errors, checks the lock
and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the coverage floor (`mix coveralls`), Dialyzer, the native custody
check (`bin/check_native_custody.exs`), `mix hex.build` without path
dependencies, the archive check (`bin/check_archive.exs`), the
Application-free check (`bin/check_application_free.exs`) and
`git diff --check`. Its coverage step sets `WOTEX_REQUIRE_NATIVE_BUILD=1`, so
the gate also runs the `native_build` test: a fresh pinned native build with
receipt reuse and tamper checks under `$TMPDIR/wotex-opcua-check`, which needs
network access and the native build prerequisites below. On Linux the custody
check compiles the process guardian with ASan/UBSan and runs WOP-G01 through
WOP-G09 in strict and LeakSanitizer lanes; on other hosts it reports that those
lanes do not apply. The archive check inspects the built `wotex_opcua` archive,
rejects development and agent state, checks the Hex dependency declarations and
compiles the packaged `lib` out of tree.

### Native build lane

The native executable build is explicit. Pass a disposable absolute directory
that is new, empty or an already verified build workspace:

```console
mix wotex.native.build --package wotex-opcua --workspace /absolute/disposable/dir
mix pkg wotex-opcua wotex.native.build --workspace /absolute/disposable/dir
```

Both run `wotex.opcua.native.build`. It downloads the OpenSSL and open62541
archives pinned in `priv/fixtures/native-sources-v1.json`, verifies their
digests, applies the reviewed SDK patch, builds static libraries, the
`wotex_opcua_native` executable and the `wotex_opcua_custody` guardian, runs the
native CTest step and writes the receipt `wotex-native-build.json`. It needs
network access, `cc`, CMake 3.20+ with `ctest`, `make`, Perl, `python3` (the
SDK code generator), `ar`, `ranlib`, `ld` and curl 8.4.0+, on Linux
x86_64/aarch64 or macOS arm64. A reused workspace is verified again; a failed
build keeps its diagnostic files and needs a new workspace.

### Software acceptance lanes

The independent-peer lanes are explicit and use a new or empty disposable
absolute workspace:

```console
mix pkg wotex-opcua wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-opcua wotex.software.run --workspace /absolute/disposable/dir
```

The build runs the native build under `native/`, a Debug ASan/UBSan tree under
`asan/` and a peer virtual environment under `peer/venv` installed with
`--require-hashes` from `test/interop/requirements.lock` (asyncua), and records
`software-build.json`. It needs the native build prerequisites plus `python3`
with `venv` and access to PyPI. The run verifies that manifest, starts the
independent asyncua secure peer (`test/interop/secure_peer.py`), runs the
`interop` and `software` ExUnit lanes with `WOTEX_REQUIRE_SOFTWARE=1`, native and
sanitizer CTest, `mix deps.audit` and `mix hex.audit`, stops the peer and writes
`software-run.json`; any failed lane fails the task. Both need `python3`,
`cmake`, `ctest` and `mix` on `PATH`. The fully qualified tasks are
`wotex.opcua.software.build` and `wotex.opcua.software.run`. The `interop` and
`software` tests read the `WOTEX_OPCUA_*` peer and executable paths that only
this runner sets, so selecting them without it fails. The peer environment is
test infrastructure; the runtime package runs no Python.

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-opcua/plans/software-implementation.md)
and [specification index](../../docs/packages/wotex-opcua/specs/WOP-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenario families.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [WOP.11 standalone client contract](../../docs/packages/wotex-opcua/specs/WOP.11-standalone-client-and-preservation.md)
records required native APIs, preserved protocol assets and concrete specified
fixtures. These cases are not passing evidence until executable bindings run.

The [specification catalogue](../../docs/packages/wotex-opcua/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](../../docs/packages/wotex-opcua/specs/WOP.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.

## License

Wotex OPC UA is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-opcua/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-opcua/NOTICE).
