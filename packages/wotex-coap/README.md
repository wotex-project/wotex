# Wotex CoAP

**Consumer-neutral Constrained Application Protocol interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_coap.svg)](https://hex.pm/packages/wotex_coap)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_coap)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_coap.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-coap/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

## Installation

Wotex CoAP 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
Add it to your dependencies; Hex resolves `wotex` and
`wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_coap, "~> 0.1"}
  ]
end
```

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
PKI currently has real OTP peer tests. The explicit OSCORE Runtime profile
dispatches through the manifest-verified native owner. The native worker
consumes the durable context, assembles uploads, executes protected unary
exchanges with inline or streamed results and closes through that same-binary
custody path. Its libcoap exchange loop also registers one protected Observe,
holds inline or streamed reports behind cumulative credit, applies 24-bit serial freshness
and renews or cancels with the original token. Max-Age expiry renews at no less
than one-second intervals when enabled; otherwise it sends best-effort
cancellation and reports stale state. Independent OSCORE interoperability and
the full software matrix execute through pinned, manifest-bound peers. Renewal
faults retain their finite status/code, Property overload keeps one latest
complete report and Event overlap terminates with owned cleanup. Native freshness checks ignore stale
metadata before representation identity and accept the protected FFFFFF-to-zero
serial wrap. If libcoap cannot submit tracked cancellation during renewal, the
worker sends an explicit original-route/token Observe=1 request, returns the
peer's confirmation and still closes at the caller's finite deadline when none
arrives. A notification that arrives between a renewal or cancellation and its
response is neither a report nor cancellation success. Abrupt owner EOF after establishment, or while registration or renewal
awaits the peer, sends one best-effort cancellation before the worker releases
its protected session and custody reaps the process. The same cleanup
remains bounded while the actual owner output pipe is full and report output is
backpressured across custody.
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
`Wotex.CoAP.profile(:oscore)` selects explicit OSCORE unary operations and streams.
All admit JSON, UTF-8 text and opaque bytes. OSCORE unary calls accept one typed
immediate or configured Security value; subscriptions require configured
security and a nil immediate credential. Both require `native_backend`.
`Wotex.CoAP.Security.new/1` validates and redacts the fixed-suite OSCORE
credential value without reading its durable store. The internal native owner
can complete the verified process ready/open/close handshake. The public
`connect/1`, `send/2`, method-helper and `disconnect/1` boundaries select that
owner for an explicit `coap` OSCORE credential and verified `native_backend`.
The native worker validates and consumes the durable store before reporting a
successful open. Its production adapter completes one protected unary request
at a time, returning responses up to 32 KiB inline and larger responses through
correlated begin/chunk/end frames up to the 1 MiB body ceiling. The adapter also
completes protected Observe registration, inline or streamed reports, cumulative
report credit, Max-Age renewal and token-matched cancellation. A disabled
renewal policy emits the initial report before stale cleanup.
Numeric IPv4/IPv6 destinations are required. A session serializes requests;
its owner is monitored. Datagrams are bounded to 1152 bytes; complete bodies to 1 MiB.
Capabilities expose these as `max_datagram_size` and `max_body_size`.
The legacy `max_payload_size` key remains a 1152-byte datagram-limit alias,
not the complete-body ceiling.
See the [blockwise contract](../../docs/packages/wotex-coap/specs/WCO.04-blockwise.md) for configurable
block sizes, aggregate budgets and the atomic upload profile.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :coap, :request, :stop]`, with bounded status
metadata and duration in native monotonic units. Observations emit
`[:wotex, :coap, :subscription, :open | :deliver | :close]` with a count and
closed kind/result dimensions. Neither family includes credentials, values,
hosts, URIs or caller-selected names.
Errors are structured and credential-free. Unknown Form extension terms survive
mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; `receive/2` fails explicitly. Native subscriptions
return an exact owned handle after validating the initial complete representation.
Callback names alone do not establish consumer behavioral parity.
The consumer retains its implementation until differential scenarios and
interoperability gates pass; migration is outside this package.

See [implemented profile](../../docs/packages/wotex-coap/specs/WCO.03-implemented-profile.md),
[primary sources](../../docs/packages/wotex-coap/provenance/primary-sources.md) and
[executable evidence](../../docs/packages/wotex-coap/provenance/executable-evidence.md).

## Development

Run commands from the repository root; the
[contributing guide](https://github.com/wotex-project/wotex/blob/main/CONTRIBUTING.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-coap test test/wotex/coap/codec_test.exs  # one test file
mix check.fast --package wotex-coap                     # compile, format, Credo, tests
mix pkg wotex-coap check --no-retry                     # full gate
mix native.lint --package wotex-coap                    # clang-format on changed C/C++ lines
mix native.test --package wotex-coap                    # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-coap`. It compiles with warnings as errors, checks the lock and
unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`, Credo,
Doctor, `mix docs --warnings-as-errors` (in the `docs` environment), runs the
default suite once with the 95% coverage floor (`mix coveralls`), Dialyzer and
`git diff --check`, then runs `bin/check_archive.exs` and
`bin/check_application_free.exs`. The archive check builds exact `wotex`,
`wotex_runtime` and `wotex_coap` candidate archives once, rejects mutable
dependency metadata and development machinery, and compiles an isolated
consumer whose only Wotex paths are the extracted candidates. That consumer
runs the packaged integration corpus through public core, Runtime and CoAP APIs
against a real UDP peer, records content identities and verifies complete
temporary-workspace cleanup. Candidate archives do not claim publication.
The application-free check proves that the package has no Application callback
and that starting it and validating DTLS credentials start no OTP SSL
supervisor.

The default suite excludes the `interop` and `hardware` tags; every
software-lane file is also tagged `interop`. It still needs a supported
native-build host with the complete native toolchain described below:
`test/wotex/coap/native_toolchain_test.exs` resolves it, and
`native_worker_test.exs`, `native/custody_test.exs` and
`native_build_command_test.exs` compile first-party native test executables
with `cc` and `pkg-config` against OpenSSL development files. Interop suites
fail rather than skip when selected without their peer.

### Native build lane

The OSCORE helper `wotex-coap-oscore` is built only on explicit request, in a
disposable absolute workspace that is absent or empty (a completed workspace
is re-verified read-only, never repaired):

```console
mix wotex.native.build --package wotex-coap --workspace /absolute/disposable/dir
mix pkg wotex-coap wotex.native.build --workspace /absolute/disposable/dir
```

Both forms dispatch `wotex.coap.native.build`. Supported hosts are Linux
x86-64/AArch64 and macOS AArch64. The build resolves and fingerprints a C11
compiler (`cc` or `$CC`), CMake (`cmake` or `$CMAKE`), OpenSSL 3 (`openssl` on
the `PATH` or `$OPENSSL_ROOT_DIR`), `curl`, `patch`, `pkg-config` and `ldd`
(Linux) or `otool` (macOS). It downloads the pinned libcoap 4.3.5 archive,
verifies it against `native/oscore/source.json`, applies the ordered patches in
`native/oscore/patches/`, builds a static libcoap and the worker from
`native/oscore/`, probes them and publishes `native-manifest.json` within a
ten-minute deadline.

### Software lane

```console
mix pkg wotex-coap wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-coap wotex.software.run --workspace /absolute/disposable/dir
```

The build needs the native-build tools plus a Java runtime (`java` or
`$WOTEX_COAP_JAVA`) and network access. It builds the nested native helper, the
libcoap `coap-server` peer and the native fault/vector executables (with
ASan/UBSan on Linux), admits the pinned Eclipse Californium 3.14.0 plugtest
server JAR by SHA-256, runs every vector and only then writes the manifest.
The run verifies that workspace and runs the `interop`/`software` suites
(libcoap UDP, PSK and PKI; same-stack OSCORE; Californium OSCORE; lifecycle
stress; native corpus and Port saturation) with seed 0 under a five-minute
deadline, and always writes a bounded `result.json`. Use the same
`OPENSSL_ROOT_DIR` for build and run. A workspace is terminal after a run; use
a fresh build for another run. `test/software/Dockerfile.linux` is the Linux
environment for both commands, built once per supported runtime.

### Sanitizer images

`test/native/Dockerfile` (pinned libcoap with its patches, the store,
sequence, protection, block-limit and worker-exchange harnesses),
`test/native/Dockerfile.json` (JSON, frame, body, credit, command and a worker
trace) and `test/native/Dockerfile.custody` (process custody) build Linux
ASan/UBSan images with Docker. The JSON and custody images use
`packages/wotex-coap` as their build context; `test/native/Dockerfile` needs a
context assembled from `native/oscore/` sources and patches, the `test/native/`
sources and the verified archive as `source.tar.gz`. The recorded invocations
are in [executable evidence](../../docs/packages/wotex-coap/provenance/executable-evidence.md).

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-coap/plans/software-implementation.md)
and [specifications](https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-coap/specs) define the implemented software
profile with exact behavior, limits, failure transitions, acceptance scenarios
and concrete fixtures. Required software peers are separate from physical-device
tests and publication.

The [standalone client contract](../../docs/packages/wotex-coap/specs/WCO.06-standalone-client-and-preservation.md)
defines native workflows and feature-preservation obligations. Its concrete
fixture corpus contains specified cases; execution results remain in provenance.

The [specification catalogue](../../docs/packages/wotex-coap/specs/catalogue.yaml)
records implementation status and exact evidence. The
[Wotex integration contract](../../docs/packages/wotex-coap/specs/WCO.07-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. The immutable archive consumer repeats the
packaged public boundary on the minimum and current runtime lanes.

## Native build and software orchestration

[WCO.08](../../docs/packages/wotex-coap/specs/WCO.08-native-build-and-software-evidence.md) defines
the implemented package tasks `wotex.native.build`, `wotex.software.build` and
`wotex.software.run`, each taking `--workspace ABS`; from the repository root
run `mix native.build --package wotex-coap --workspace ABS` and
`mix pkg wotex-coap wotex.software.build|wotex.software.run --workspace ABS`.
The run task verifies an
existing build and executes the current independent libcoap UDP, PSK and PKI
interop suite, same-stack OSCORE sessions through the Mix-built helper and an
independent upstream-stack OSCORE cohort against a pinned Eclipse Californium
peer, with ExUnit-owned peers and bounded cleanup. Protocol execution uses
BEAM UDP, OTP DTLS and an explicit libcoap OSCORE Port.
`Wotex.CoAP.NativeBackend.verify/1` can validate the content identity of an
explicit native executable and manifest without starting it.
`Wotex.CoAP.Native.Connection`
owns the verified executable for its bounded ready/open/close lifecycle and
monitors the caller without exposing credentials. `Wotex.CoAP.Native.Admission`
atomically reserves exactly 64 ordinary call slots plus separate close-control
capacity before messages enter an owner mailbox. The connection owns this table
and consumes its close capability. Normalized native requests use the 64-slot
FIFO admission path, spend queue time from their deadline and return complete
inline or correlated streamed-body Messages. Streamed responses remain private
until exact body length/hash validation and one-time reference resolution.
Explicit outbound payloads use correlated begin/chunk/end commands before the
request; upload failures occur before mutation submission. The root API preserves
its two-field session value while dispatching explicit OSCORE unary requests to
this owner. Native discovery uses the same owner with its 64 KiB response ceiling
checked before streamed-body assembly. Dedicated native Observe sessions admit
one receiver, open bounded report credit, validate inline or streamed reports,
deliver the first complete representation before returning the handle and
cancel the exact subscription even while credit is in flight. The Runtime
adapter verifies the native route and subscription generation, maps unary calls
and Observe through the same owner, and releases exact handles on cancellation.
Production unary execution uses these same response-body envelopes; production
Observe execution now covers protected registration, inline or streamed reports,
credit, Max-Age renewal, stale cleanup, bounded Property/Event overload,
renewal faults, 24-bit freshness, confirmed in-flight renewal cancellation and
owner-EOF cleanup for established or pending observations, including a full
owner output pipe.
`Wotex.CoAP.Native.Wire` validates bounded ready and response frames and
constructs complete Messages without starting a process.
`Wotex.CoAP.Native.Command` encodes exact bounded commands with monotonic
identities scoped to a generation. `Wotex.CoAP.Native.Body`
withholds streamed bytes until exact length and hash verification.
`Wotex.CoAP.Native.Report` correlates report/body
envelopes and verifies Message metadata. `Wotex.CoAP.Native.ReportLedger` bounds
the eight-frame credit window and serializes cumulative acknowledgments. The
native owner dispatches unary body commands and the Observe/credit/cancel
lifecycle through those boundaries.
Mix and ExUnit own first-party build and test orchestration; the tracked source
and package contain no Python. The current run receipt covers 15 independent UDP,
PSK and PKI tests, 12 same-stack OSCORE tests, including a 1 MiB protected body,
5 independent upstream-stack OSCORE tests against Eclipse Californium 3.14.0, an
8-test lifecycle stress lane across all four transports, 2 Port-mailbox
saturation tests, 13 native-v1 corpus tests through the Mix-built helper and 2
tests that kill a peer's owner and find no surviving peer. All 57 pass on macOS
arm64 and in Linux containers on Elixir 1.20.2 / OTP 29 and Elixir 1.18.4 / OTP
27 with sanitizer-built native vectors. The Californium archive is admitted by
exact digest and run by a recorded Java runtime as a test peer only. The package gate,
including the Hex archive and out-of-tree compilation gate, passes from a clean
clone of the committed repository in Linux containers on both runtimes.
Group OSCORE, automatic context re-derivation and additional independent stacks
are outside this accepted profile and belong to separately versioned future work.

## License

Wotex CoAP is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-coap/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-coap/NOTICE).
