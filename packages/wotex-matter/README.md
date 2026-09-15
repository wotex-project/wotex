# Wotex Matter

**Consumer-neutral Matter interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_matter.svg)](https://hex.pm/packages/wotex_matter)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_matter)
[![CI](https://github.com/wotex-project/wotex-matter/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-matter/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-matter/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-matter)
[![License](https://img.shields.io/hexpm/l/wotex_matter.svg)](https://github.com/wotex-project/wotex-matter/blob/main/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This checkout is a `0.1.0-dev` development baseline. The public API remains
unstable, and the ordered software profile is unfinished. Package metadata
does not establish publication or release readiness.

Build handoff: [software implementation sequence](docs/plans/software-implementation.md).

## Installation

This development checkout is prepared as the `wotex_matter` Hex package but
does not assert that a release has been published. A sibling-checkout consumer
can select it explicitly:

```elixir
def deps do
  [{:wotex_matter, path: "../wotex-matter"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

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
The current Python factory adapter remains a separate narrow baseline.

[WMA.13](docs/specs/WMA.13-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. `mix run bin/check_p07_native.exs` rebuilds
and tests the P07 host in a disposable pinned Linux environment.
`mix wotex.native.build --workspace /absolute/empty/workspace` builds the normal
and sanitizer controllers. `mix wotex.software.build` uses the same argument
contract and adds the pinned lighting, all-clusters and bridge executables.
The all-clusters and bridge peers include small test-only named-pipe controls
for temperature/null and reachability inputs. The build verifies their exact
upstream source hashes and records the extension and patched-source hashes.
Both tasks run from this source project, verify downloads and advisories, run
native unit tests, and record content-bound build manifests. Reuse requires
matching source, artifacts and logs; a native-only workspace requires a fresh
workspace for a software build. Docker, Git, curl, tar and the `kill` executable
must be available.
The explicit lighting, thermostat and bridge ExUnit workflows have passed in
both Linux BEAM lanes; their exact cohorts are recorded in
[executable evidence](docs/provenance/executable-evidence.md).
`mix wotex.software.run` remains specified implementation work. Upstream SDK
Python is used only while generating and building native SDK sources.

## Implemented profile

The implemented package provides fabric-scoped concrete and batch-read paths,
bounded TLV, typed attribute/event reports, a finite descriptor registry, a
bounded endpoint-catalogue value, a validated `Client` behaviour, an opt-in
Python SDK interaction adapter, compatibility callbacks and WoT Form/Runtime
mapping. TLV preserves tags, explicit scalar widths, null and containers while
bounding bytes, nodes and nesting. `read_paths/3` preserves ordered per-path
successes and errors from a selected client. The `SDK` adapter targets concrete
read/write/invoke calls in the pinned native SDK; an explicitly supplied
controller factory owns SDK startup, credentials and shutdown. The batch API is
not wired to that one-shot adapter. No Python runtime or native SDK binary is
bundled. The packaged first-party controller source is built explicitly outside
the Hex archive.

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
identity, retries, credentials and stream cleanup. P09 owns the pinned
software-peer execution of P07's interop scenarios and the complete controller
workflow.

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

Use `client: Wotex.Matter.SDK` with an absolute Python executable,
`factory: "sdk_host:controller"`, `fabric_id` and a `settings` map. The selected
factory must be a synchronous context manager yielding an initialized SDK
controller. See [SDK contract](docs/specs/WMA.03-sdk-client.md).
Alternatively, supply a module implementing `Wotex.Matter.Client`. The driver
owns the pinned SDK, secure fabric storage,
commissioning, attestation, sessions and per-path status validation. Missing
transport, crashed driver, invalid return and missing write input all fail.
Failed writes/invokes have unknown effect; the library never retries them.
No real SDK/device parity is claimed by the fake-port contract tests.

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
termination. The [one-shot evidence](docs/provenance/executable-evidence.md)
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

See [implemented profile](docs/specs/WMA.02-implemented-profile.md),
[primary sources](docs/provenance/primary-sources.md) and
[executable evidence](docs/provenance/executable-evidence.md).

## Development

Use Elixir 1.18 or newer with compatible OTP. Local Wotex core and Runtime
checkouts require explicit `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Run `mix check` before commits. It checks formatting, compiles with warnings as
errors, and runs the default test suite. Wider checks belong to release readiness.
The separate `elixir bin/check_p01_native.exs` lane compiles and tests the P01
descriptor/value unit on the pinned Linux x86_64 reference toolchain with and
without AddressSanitizer and UndefinedBehaviorSanitizer.
`elixir bin/check_p02_native.exs` separately verifies the pinned SDK source and
gitlink inputs, then exercises the durable store under the same normal and
sanitizer toolchains, including lock and crash-boundary behavior.
`elixir bin/check_p02_advisories.exs` separately queries OSV for advisories
against the four exact P02 source revisions; it is a live release check rather
than a substitute for the content-pinned native lane.
`WOTEX_PATH_DEPS=1 mix run bin/check_p03_native.exs` separately rebuilds the
first-party controller from the exact SDK, gitlink, generator and tool inputs,
then runs normal and sanitizer lifecycle, failure, load and cleanup checks.
`WOTEX_PATH_DEPS=1 mix run bin/check_p04_native.exs` extends that lane with the
generated cluster bindings, Interaction Model implementation and focused
normal/sanitizer interaction tests.
`WOTEX_PATH_DEPS=1 mix run bin/check_p05_native.exs` additionally compiles the
SDK subscription owner and runs focused normal/sanitizer lifecycle, credit,
identity and retirement tests.
`WOTEX_PATH_DEPS=1 mix run bin/check_p06_native.exs` extends that lane with
bounded opt-in subscription recovery and delivery-generation tests.
`WOTEX_PATH_DEPS=1 mix run bin/check_p07_native.exs` compiles the filtered
commissioning, final CASE-probe, enhanced-window and typed ACL paths and runs
their focused normal/sanitizer tests. The separately selected P07 interop test
requires a real fixture file; P09 will build and execute that fixture.
P08 is covered by `test/wotex/matter/runtime_stream_test.exs` in the BEAM matrix.
It exercises typed controller results, capability-backed Runtime frames,
terminal cleanup, original-route cancellation and the explicit read health
probe; it adds no native build surface.
P08a is covered by `test/wotex/matter/runtime_integration_test.exs`. It executes
the checked-in Wotex integration corpus through public TD, ConsumedThing,
Context, Result, Subscription and Retry APIs, plus negative selection and
resource-ownership cases. It also adds no native build surface.
`WOTEX_PATH_DEPS=1 mix run bin/check_p03_advisories.exs` performs the associated
live OSV audit. None of these native commands belongs to routine `mix check`.
Optional interoperability suites fail if invoked without their required peer.
No remote repository, published package or publication action is implied.

The native corpus runs all 17 cases in both BEAM toolchains. Its process-flow
cases suspend the actual connection, stream owner or receiver while a separate
test executable sends 10000 callbacks derived from an SDK report through
production report credits and delivery. The 128-byte input denotes the encoded JSON value;
callback counts, queue reservations, terminal delivery and cleanup are measured.
The ordinary native executable contains no process-flow instrumentation. Exact
results and the remaining software-profile requirements are recorded in
[executable evidence](docs/provenance/executable-evidence.md).

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WMA-index.md) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](docs/specs/WMA.11-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and end-to-end workflows.
Its [concrete corpus](docs/specs/fixtures/contract-v1.json) is partially executed:
the P01 pure cases run in the default suite, the WMA-F07 controller lifecycle
cases run in the separate P03 native lane, WMA-F11 runs with P04, and the WMA-F08
delivery/cancellation projection runs with P05. WMA-F09 default terminal loss and
the explicit recovery transition run with P06. P07 executes local admission,
native protocol, generated-window and ACL schema behavior, and compiles the
production SDK controller path. Its real good/bad PIN, failed-attestation,
expired-window and ACL-denial fixture remains unexecuted; P09 owns that peer
along with the independent subscription peer. P08 executes the WMA-V11 typed
transport and Runtime-stream ownership boundary directly. P08a executes the
public ConsumedThing profiles, all WMA-I-F01–F08 cases, the error/retry table,
deadline/credential rejection, malformed result handling and Runtime-owned
stream cleanup. Scenario tables and an unselected interop test alone are not
executable acceptance evidence.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WMA.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. The local P08a boundary is executed; the
software-peer and isolated-package requirements remain open.
