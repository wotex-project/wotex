# Wotex Matter

**Consumer-neutral Matter interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_matter.svg)](https://hex.pm/packages/wotex_matter)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_matter)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_matter.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-matter/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This package is a `0.1.0` development baseline. The ordered software
profile is implemented and accepted against the pinned SDK example peers. The
public API remains unstable, and package metadata does not establish publication
or release readiness. The Python factory adapter has since been removed;
source-bound software and archive receipts for this exact revision must be
renewed before a current-source release claim.

Build handoff: [software implementation sequence](../../docs/packages/wotex-matter/plans/software-implementation.md).

## Installation

Wotex Matter 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet, and package metadata does not assert that a
release exists. Once one is, depend on it as usual; Hex resolves `wotex` and
`wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_matter, "~> 0.1"}
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
    {:wotex_matter,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-matter",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_matter, path: "../wotex/packages/wotex-matter", override: true}
```

Path dependencies prove nothing about a released artifact. Dependency
compilation never builds the native controller; build it with the explicit
[native lane](#native-and-software-lanes).

## Accepted native target

The accepted backend is a first-party persistent C++17 connectedhomeip
controller Port, with an owned durable authority/store, attestation, commissioning,
CASE interactions and subscriptions. P03 implements the controller owner,
durable authority, production attestation verifier and framed Port. P04 adds
finite reads, event reads, writes and invokes through the generated SDK bindings.
P05 adds attribute/event subscriptions, bounded report credit, monitored
receivers and callback-safe cancellation. P06 adds explicitly selected,
bounded recovery with observable continuity loss. P07 adds explicit filtered
on-network commissioning, final CASE confirmation, generated enhanced-window
onboarding material and typed operational ACL values.
The earlier Python factory adapter is removed; runtime controllers use the
first-party native host.

[WMA.08](../../docs/packages/wotex-matter/specs/WMA.08-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. The explicit
[native and software lanes](#native-and-software-lanes) build the controller
and the pinned SDK example peers. The lighting, thermostat and bridge ExUnit
workflows have passed in both Linux BEAM lanes; their exact cohorts are
recorded in
[executable evidence](../../docs/packages/wotex-matter/provenance/executable-evidence.md).
Upstream SDK Python is used only while generating and building native SDK
sources.

## Implemented profile

The implemented package provides fabric-scoped concrete and batch-read paths,
bounded TLV, typed attribute/event reports, a finite descriptor registry, a
bounded endpoint-catalogue value, a validated `Client` behaviour, a first-party
native SDK controller, compatibility callbacks and WoT Form/Runtime
mapping. TLV preserves tags, explicit scalar widths, null and containers while
bounding bytes, nodes and nesting. `read_paths/3` preserves ordered per-path
successes and errors from a selected client. The `Native` client executes the
pinned SDK through an explicitly built C++ host. Its one-shot mode opens an
existing controller store for each concrete read, write or invoke. No Python
runtime or native SDK binary is bundled. The packaged first-party controller
source is built explicitly outside the Hex archive.

The packaged native source includes the P02 `PersistentStorageDelegate`: it
creates or opens an explicitly identified controller store, holds an exclusive
lock, validates bounded versioned state, and commits each opaque SDK value by a
same-directory fsynced rename. P03 connects that store to one first-party
`DeviceCommissioner`, generates or reopens the controller root and Identity
Protection Key with SDK crypto, loads an explicit Product Attestation Authority
trust directory, and runs controller setup and shutdown through a direct BEAM
Port. P04 uses that controller for bounded Interaction Model operations and
Descriptor discovery. P05 uses a subscription `ReadClient` for concrete
attribute/event paths, retains revised intervals and report identity, bounds
native/BEAM delivery, and retires callbacks on cancel, receiver death or
overflow. P06 uses SDK automatic resubscription only when requested, limits a
recovery window to five attempts and 60 seconds, advances delivery generation,
and reports that continuity was lost before a fresh initial snapshot. P07 uses
exact long-discriminator discovery, SDK pairing and final commissioning
callbacks, then requires a CASE probe before success. Enhanced windows use
SDK-generated PIN and salt; returned onboarding material has redacted Inspect.
AccessControl ACL values are typed and exclude PASE as operational authority.
P08 maps controller-profile Property, Action and Event operations to those typed
services. Runtime streams use an explicitly started private relay, retain
DataVersion and Event identity, terminate on session loss, and cancel through
the session and subscription that established the stream. Loading the library
starts no process or native executable. P08a adds pure one-shot and controller
Runtime profile factories, classified failures, pre-acquisition selector/input
validation, and public ConsumedThing coverage for values, deadlines, result
identity, retries, credentials and stream cleanup. P09 executes the pinned
software-peer execution of P07's interop scenarios and the complete controller
workflow; both required Linux BEAM lanes pass with all 36 required software
cases executed.

## Quick start

```elixir
{:ok, path} = Wotex.Matter.Address.new(%{
  fabric_id: 1, node_id: 2, endpoint: 1, cluster: 6, member: 0
})
{:ok, bytes} = Wotex.Matter.TLV.encode([
  %{tag: {:context, 1}, type: :u8, value: 42}
])
{:ok, [%{tag: {:context, 1}, type: :u8, value: 42}]} = Wotex.Matter.TLV.decode(bytes)
{:ok, %{type: :i16, value: 2150}} =
  Wotex.Matter.Descriptor.to_element(
    :attribute,
    %{fabric_id: 1, node_id: 2, endpoint: 1, cluster: 0x0201, member: 0},
    :read,
    2150
  )

oneshot_profile = Wotex.Matter.profile()
{:ok, controller_profile} = Wotex.Matter.profile(:controller)
```

Use `client: Wotex.Matter.Native` with the explicit native controller options
below. Its C++ host owns SDK startup, secure fabric storage, attestation,
sessions and per-path status validation. See the [client contract](../../docs/packages/wotex-matter/specs/WMA.04-sdk-client.md).
Alternatively, supply a module implementing `Wotex.Matter.Client`; injected
contract tests alone do not establish SDK or device interoperability. Failed
writes/invokes retain unknown effect and are never retried by the library.

To open the P03 controller owner, build `wotex-matter-host` with the separate
native lane and pass its absolute path explicitly:

```elixir
{:ok, session} =
  Wotex.Matter.connect(
    client: Wotex.Matter.Native,
    executable: "/opt/wotex/bin/wotex-matter-host",
    lifecycle: :persistent,
    storage_path: "/var/lib/example-matter/controller-1",
    storage_mode: :open_existing,
    authority: :stored,
    vendor_id: 0xFFF1,
    fabric_id: 1,
    controller_node_id: 2,
    paa_trust_store: "/etc/example-matter/paa"
  )

{:ok, %{"status" => "ready", "fabric_id" => 1}} =
  Wotex.Matter.Native.health(session.handle)

:ok = Wotex.Matter.disconnect(session)
```

Set `lifecycle: :oneshot` with `storage_mode: :open_existing` and `authority: :stored`
to obtain a passive native handle. Each concrete read, write or invoke opens
and closes its own controller within the operation budget. The named API retains
typed results. A Runtime `:oneshot` transport uses the same options and returns
schema values, the string `"written"` for writes, and nil for status-only commands.
Native `:controller` transports require `lifecycle: :persistent`. Both modes use
an explicitly built first-party executable and POSIX `/bin/kill` for owned-child
termination. The [one-shot evidence](../../docs/packages/wotex-matter/provenance/executable-evidence.md)
records actual peer checks on both required Linux toolchains.

Use `storage_mode: :create_new` with `authority: :generate_root` only for an
explicitly authorized new controller directory. P04 provides named operations
on the persistent controller:

```elixir
address = %{
  fabric_id: 1,
  node_id: 3,
  endpoint: 1,
  cluster: 0x0201,
  member: 0
}

{:ok, %Wotex.Matter.AttributeReport{}} =
  Wotex.Matter.read_attribute(session, address)

setpoint = %{address | member: 0x0012}
value = %{tag: :anonymous, type: :i16, value: 2000}

{:ok, %{status: 0}} =
  Wotex.Matter.write_attribute(session, setpoint, value,
    expected_data_version: 7,
    timed_request_timeout_ms: 500
  )
```

P05 subscriptions bind delivery to an explicit receiver and opaque handle:

```elixir
{:ok, subscription} = Wotex.Matter.subscribe(session, %{
  kind: :attribute,
  paths: [address],
  receiver: self(),
  min_interval_s: 1,
  max_interval_s: 60,
  max_queue_length: 1000,
  resubscribe: false
})

receive do
  {:wotex_matter, reference, {:ok, value, metadata}}
      when reference == subscription.reference ->
    {value, metadata}
end

:ok = Wotex.Matter.unsubscribe(session, subscription)
```

With `resubscribe: true`, the receiver first gets
`{:status, :resubscribing, %{continuity: :lost, generation: generation, attempt: attempt}}`.
A successful retry then sends `{:status, :resubscribed, %{continuity: :unknown, ...}}`
before the new initial snapshot. The original opaque handle remains valid for
cancellation. Recovery does not claim event replay or gap-free continuity.

Commissioning and enhanced-window creation are explicit operations on the same
owned controller. The setup PIN is required only for initial on-network
commissioning; window PIN and salt are generated by the SDK:

```elixir
{:ok, %{case: :established}} =
  Wotex.Matter.commission_on_network(session, %{
    node_id: 3,
    setup_pin: setup_pin,
    discriminator: 3840,
    timeout: 60_000
  })

{:ok, %Wotex.Matter.OnboardingMaterial{} = material} =
  Wotex.Matter.open_commissioning_window(session, %{
    node_id: 3,
    timeout_s: 300,
    iteration_count: 1_000,
    discriminator: 1234
  })
```

Treat `material.setup_pin`, `material.manual_code` and `material.qr_code` as
secrets. Commissioning failures retain the numeric SDK status and report an
unknown effect once fabric mutation may have started. The library never resets
the peer, removes its fabric or retries commissioning automatically.

The SDK adapter forwards explicit `timed_request_timeout_ms` for writes/invokes.
Full device qualification needs further integration.
The current `member` field enforces
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
receive queue is fabricated. Clients without optional subscription callbacks
fail explicitly. Callback names alone do not establish consumer behavioral parity.
Compatibility requires concrete differential scenarios and independently observed
software interactions for each advertised operation.

See [implemented profile](../../docs/packages/wotex-matter/specs/WMA.03-implemented-profile.md),
[primary sources](../../docs/packages/wotex-matter/provenance/primary-sources.md) and
[executable evidence](../../docs/packages/wotex-matter/provenance/executable-evidence.md).

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-matter test test/wotex/matter/tlv_test.exs  # one test file
mix check.fast --package wotex-matter                     # compile, format, Credo, tests
mix pkg wotex-matter check --no-retry                     # full gate
mix native.lint --package wotex-matter                    # clang-format on changed C/C++ lines
mix native.test --package wotex-matter                    # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).
The SDK-bound sources are built, tested and analysed in Docker, in the
image the SDK build uses.

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-matter`. It compiles with warnings as errors, checks the lock
and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the 95% coverage floor (`mix coveralls`), Dialyzer and
`git diff --check`, then runs `bin/check_archive.exs` and
`bin/check_application_free.exs`. The archive check builds the exact
`wotex_matter` archive with its Hex dependency identities, verifies that it
ships the native sources, fixtures and software-case inventory but no
documentation, governance or development files, and compiles the extracted
package out of tree. The second check proves that the package defines no
Application callback.

The ordinary test run needs only a POSIX system (`/bin/sh`, `/bin/kill`); it
builds no native code and needs no SDK or Docker. Tests tagged `interop`,
`software` or `hardware` are excluded; they need the software fixture and fail
if selected without it. P08 (`test/wotex/matter/runtime_stream_test.exs`) and
P08a (`test/wotex/matter/runtime_integration_test.exs`) run in this ordinary
suite. P08 exercises typed controller results, capability-backed Runtime
frames, terminal cleanup, original-route cancellation and the explicit read
health probe. P08a executes the checked-in Wotex integration corpus through
public TD, ConsumedThing, Context, Result, Subscription and Retry APIs, plus
negative selection and resource-ownership cases. Neither adds a native build
surface.

### Native and software lanes

Native builds, the software-peer profile and the per-packet native checks run
only when invoked explicitly; none belongs to the gate or to a bounded change.
They need Docker able to run `linux/amd64` containers, `git`, `curl`, `tar` and
`kill` on the host, and network access for the pinned connectedhomeip sources
and OSV advisory queries. Every build runs inside a pinned Linux x86_64 image.

The workspace tasks take one disposable absolute directory outside
`packages/wotex-matter`, without `.` or `..` segments. It must be empty or hold
a matching `workspace-manifest.json`; a `<workspace>.lock` directory beside it
serialises use.

```console
mix wotex.native.build --package wotex-matter --workspace /absolute/disposable/dir
mix pkg wotex-matter wotex.native.build --workspace /absolute/disposable/dir
mix pkg wotex-matter wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-matter wotex.software.run --workspace /absolute/disposable/dir
```

The first two lines are equivalent. The native build verifies the pinned
source archives and native advisories, builds the normal and sanitizer
`wotex-matter-host` controllers, runs the native unit tests and records a
content-bound build manifest. The software build uses the same argument
contract and adds the pinned lighting, all-clusters and bridge executables. The
all-clusters and bridge peers include small test-only named-pipe controls for
temperature/null and reachability inputs; the build verifies their exact
upstream source hashes and records the extension and patched-source hashes.
Reuse requires matching source, artifacts and logs; a native-only workspace
needs a fresh workspace for a software build.

The run verifies that build and executes the required suite
(`mix test --include interop --include software --exclude hardware` with
`WOTEX_REQUIRE_SOFTWARE=1`) in separate current (Elixir 1.20.2/OTP 29.0.4) and
minimum sanitizer (Elixir 1.18.4/OTP 27.3.4.15) BEAM containers with owned
fixture state, networks and cleanup. Under `mix pkg` it mounts
`packages/wotex` and `packages/wotex-runtime` and records the path-dependency
mode. Passing command tests alone does not establish P09 acceptance. The
accepted profile has complete two-lane peer, stress, resource-census and matrix
receipts plus clean-source coverage, documentation, package-content and
out-of-tree archive-compilation evidence; exact receipts are recorded in
executable evidence. The fully qualified task names are
`wotex.matter.native.build`, `wotex.matter.software.build` and
`wotex.matter.software.run`.

The per-packet native checks create their own temporary work directory, run in
Docker and resolve sources from `packages/wotex-matter`:

```console
(cd packages/wotex-matter && elixir bin/check_p01_native.exs)
(cd packages/wotex-matter && elixir bin/check_p02_native.exs)
mix pkg wotex-matter run bin/check_p03_native.exs
mix pkg wotex-matter run bin/check_p07_native.exs
mix pkg wotex-matter run bin/check_p02_advisories.exs
mix pkg wotex-matter run bin/check_p03_advisories.exs
```

`check_p01_native.exs` compiles and tests the P01 descriptor/value unit on the
pinned Linux x86_64 reference toolchain with and without AddressSanitizer and
UndefinedBehaviorSanitizer. `check_p02_native.exs` verifies the pinned SDK
source and gitlink inputs, then exercises the durable store under the same
normal and sanitizer toolchains, including lock and crash-boundary behavior.
`check_p03_native.exs` rebuilds the first-party controller from the exact SDK,
gitlink, generator and tool inputs, then runs normal and sanitizer lifecycle,
failure, load and cleanup checks. `check_p04_native.exs` through
`check_p07_native.exs` run the same lane for later packets: P04 adds the
generated cluster bindings, Interaction Model implementation and focused
interaction tests; P05 the SDK subscription owner with lifecycle, credit,
identity and retirement tests; P06 bounded opt-in subscription recovery and
delivery-generation tests; P07 filtered commissioning, the final CASE probe,
enhanced windows and typed ACL paths. The separately selected P07 interop test
requires a real fixture file; the P09 runner builds and executes that fixture.
The two advisory scripts are live OSV queries against the exact P02 and P03
source revisions. They are release checks, not substitutes for the
content-pinned native lanes.

The native corpus runs all 17 cases in both BEAM toolchains. Its process-flow
cases suspend the actual connection, stream owner or receiver while a separate
test executable sends 10000 callbacks derived from an SDK report through
production report credits and delivery. The 128-byte input denotes the encoded JSON value;
callback counts, queue reservations, terminal delivery and cleanup are measured.
The ordinary native executable contains no process-flow instrumentation. Exact
results and the software-profile acceptance receipts are recorded in
[executable evidence](../../docs/packages/wotex-matter/provenance/executable-evidence.md).

The native input owner services report acknowledgements, cancellation and health
while an SDK interaction, subscription or commissioning operation waits. It uses
one bounded nonblocking parser and retains the operation deadline across control dispatch. Close interrupts the wait,
suppresses its late reply and releases SDK contexts before destroying the
controller. The software tests exercise this behavior with pending reads,
subscriptions and commissioning windows.

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-matter/plans/software-implementation.md)
and [specifications](https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-matter/specs) define the implemented software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
Required software peers are separate from physical-device tests.

The [standalone client contract](../../docs/packages/wotex-matter/specs/WMA.06-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and end-to-end workflows.
Its [concrete corpus](priv/fixtures/contract-v1.json) is fully executed:
the P01 pure cases run in the default suite, the WMA-F07 controller lifecycle
cases run in the P03 native lane, WMA-F11 runs with P04, and the WMA-F08
delivery/cancellation projection runs with P05. WMA-F09 default terminal loss and
the explicit recovery transition run with P06. P07 executes local admission,
native protocol, generated-window and ACL schema behavior and compiles the
production SDK controller path. P09 passes the complete two-lane run of real
good/bad PIN, failed-attestation, expired-window and ACL-denial fixtures together
with interaction, subscription, stress and resource evidence. P08 executes the WMA-V11 typed
transport and Runtime-stream ownership boundary directly. P08a executes the
public ConsumedThing profiles, all WMA-I-F01–F08 cases, the error/retry table,
deadline/credential rejection, malformed result handling and Runtime-owned
stream cleanup. Scenario tables and an unselected interop test alone are not
executable acceptance evidence.

The [specification catalogue](../../docs/packages/wotex-matter/specs/catalogue.yaml) distinguishes implemented
profiles and their evidence. The [Wotex integration contract](../../docs/packages/wotex-matter/specs/WMA.07-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. The P08a boundary, pinned software-peer matrix
and isolated immutable-source package checks are executed.

## License

Wotex Matter is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-matter/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-matter/NOTICE).
