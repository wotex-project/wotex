# Wotex Thread

**Consumer-neutral Thread inspection and explicit OpenThread SDK management.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_thread.svg)](https://hex.pm/packages/wotex_thread)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_thread)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_thread.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-thread/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This package is under development. The public API remains unstable, and the
software implementation plan is not complete. Package publication is separate.

Build handoff: [software implementation sequence](../../docs/packages/wotex-thread/plans/software-implementation.md).

## Installation

Wotex Thread 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual; Hex
resolves `wotex` and `wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_thread, "~> 0.1"}
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
    {:wotex_thread,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-thread",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_thread, path: "../wotex/packages/wotex-thread", override: true}
```

Path dependencies prove nothing about a released artifact. The native host is
built only by the explicit Linux task described under
[Development](#development); a package consumer does not receive the software
fixtures.

## Accepted native target

The accepted backend retains the existing first-party C++17 OpenThread
Port. Joiner execution, complete simulated-network workflows and full lifecycle
proof remain required. Python is not a production
runtime dependency. The injected BEAM ownership peer is an Erlang escript; the
native build is a Mix task. Active software tests use ExUnit. Dormant Python
protocol/process drivers have been retired; their unexecuted cells remain open.

[WTH.07](../../docs/packages/wotex-thread/specs/WTH.07-native-backend.md) fixes source/build pins, typed IPC,
flow control and native ownership. On Linux, the native build task builds the
pinned host, the software build adds a sanitizer host, the simulation RCP and
native test executables, and the software run executes the native tests and the
required ExUnit software lanes against that manifest (commands under
[Development](#development)). Generic orchestration and
assertions belong to Mix/ExUnit; upstream SDK Python is build-time only.

## Implemented profile

The implemented package provides bounded Operational Dataset TLVs and a real
read-only `ot-daemon` Unix-socket adapter. Dataset inspection redacts key material;
explicit `encode/1` returns the raw bytes. Unknown TLVs are retained, duplicates
are rejected, and known lengths/network-name encoding are validated.
`complete?/2` checks required field presence, not the SDK's full semantic validity.

## Quick start

```elixir
{:ok, session} = Wotex.Thread.connect(
  client: Wotex.Thread.Daemon, socket_path: "/run/openthread-wpan0.sock", timeout: 3000
)
try do
  Wotex.Thread.send(session, %{type: :state})
after
  Wotex.Thread.disconnect(session)
end
```

The daemon session owns its client socket and must be used from its creating
process. The consumer owns the daemon.
Supported reads are `:state`, `:version`, `:network_name` and `:rloc16`.
Responses are capped at 8192 bytes; remote Error, malformed output, closure and
timeout fail. This adapter neither starts OpenThread nor changes datasets.

`Wotex.Thread.OpenThread` is a separate, explicitly started Linux SDK adapter.
It owns the native host, SDK instance, radio child processes, interface and
settings lock. Its implemented APIs validate and export Datasets, enable IPv6
and Thread, form an explicitly permitted network, submit management updates,
and start/stop the commissioner with exact, finite joiner admissions. Management
acceptance is separate from Dataset activation; commissioner admission is
separate from joining. `Wotex.Thread.subscribe/2` with `%{type: :state}`
delivers one initial non-secret State snapshot and later per-iteration
coalesced snapshots with the SDK changed-flags mask, under bounded native
credit and receiver queues; `unsubscribe/2` waits for native retirement. These
are native control reports, not Runtime application streams. Joiner execution
remains planned. Thread management does not provide generic application Property writes.
Border-router management and physical-radio interoperability remain outside
this target profile.

## Wotex contract

This is an ordinary Mix library, with no Application callback or implicit runtime
work on dependency load. The consumer supplies credentials, routing policy and
supervision. Telemetry uses `[:wotex, :thread, :request, :stop]`, with bounded status
metadata and duration in native monotonic units; no credentials or values.
Errors are structured and credential-free. Unknown Form extension terms survive
mapping. These development APIs are not yet stable or certified.

The compatibility callbacks are `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
`send/2` returns the correlated operation result synchronously. No separate
receive queue is fabricated; unsupported receive/subscription calls fail
explicitly. Callback names alone do not establish consumer behavioral parity.
Compatibility requires concrete differential scenarios and independently observed
software interactions for each advertised operation.

See [protocol and graduation contract](../../docs/packages/wotex-thread/specs/WTH.02-protocol.md),
[implemented profile](../../docs/packages/wotex-thread/specs/WTH.03-implemented-profile.md),
[primary sources](../../docs/packages/wotex-thread/provenance/primary-sources.md) and
[executable evidence](../../docs/packages/wotex-thread/provenance/executable-evidence.md).

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-thread test test/wotex/thread/dataset_test.exs  # one test file
mix check.fast --package wotex-thread                         # compile, format, Credo, tests
mix pkg wotex-thread check --no-retry                         # full gate
mix native.lint --package wotex-thread                        # clang-format on changed C/C++ lines
mix native.test --package wotex-thread                        # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).
On a host that is not Linux, the OpenThread SDK suite runs in the Linux
container of the native checks when Docker is available.

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-thread`. It compiles with warnings as errors, checks the lock
and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the coverage floor (`mix coveralls`), Dialyzer and
`git diff --check`, then runs `bin/check_archive.exs` and
`bin/check_application_free.exs`. The archive check builds the exact `wotex`,
`wotex_runtime` and `wotex_thread` archives from `packages/` without path
dependencies and exercises an isolated reference consumer against them; the
second check proves that the package defines no Application callback.

The ordinary test run excludes the `interop`, `software` and `hardware` tags.
It needs a C compiler at `/usr/bin/cc`, which compiles the build guardian, and
`escript` from the Erlang installation for the injected SDK bridge peer. It
builds no SDK and needs no external network or device.

### Native build and software lanes

The native host and its software fixtures run only when invoked explicitly,
never for a bounded change. Each task takes exactly one `--workspace` argument:
an absolute, non-symlink directory that is empty, or that holds a completed
manifest which is verified and reused without rebuilding. Use a disposable
directory outside `packages/wotex-thread`.

```console
mix pkg wotex-thread wotex.native.build --workspace /absolute/disposable/native
mix pkg wotex-thread wotex.software.build --workspace /absolute/disposable/software
mix pkg wotex-thread wotex.software.run --workspace /absolute/disposable/software
```

The root `mix wotex.native.build --package wotex-thread --workspace /absolute/disposable/native`
dispatches the same native build; inside the package the short aliases
`mix wotex.native.build`, `mix wotex.software.build` and
`mix wotex.software.run` name `wotex.thread.native.build`,
`wotex.thread.software.build` and `wotex.thread.software.run`.

- The native build requires Linux and `cmake`, `ninja`, `cc`, `c++` and
  `readelf` on `PATH`. It downloads the pinned OpenThread, Mbed TLS, Mbed TLS
  framework and nlohmann/json sources from
  `priv/openthread/dependencies.json` over HTTPS, verifies their SHA-256
  digests, applies the reviewed SDK fixes and writes `native-manifest.json`.
  `--sanitizers` adds AddressSanitizer and UndefinedBehaviorSanitizer
  instrumentation.
- The software build requires the same Linux toolchain and the checked-in
  `test/native` sources. It builds a normal and a sanitizer host, the pinned
  simulation RCP and the native test executables, and writes
  `software-manifest.json`.
- The software run requires Linux, `mix` on `PATH` and a completed software
  workspace; it never builds. It runs the sanitizer native tests, then the full
  suite with `--include interop --include software --exclude hardware` against
  the normal host and the software and native-contract tests against the
  sanitizer host, with `WOTEX_REQUIRE_SOFTWARE=1`. It writes
  `software-run/result.json`; a run directory is terminal, so another run
  needs a fresh software workspace.

These lanes do not establish physical-radio interoperability or complete the
remaining software-network and lifecycle requirements. The `hardware` test
needs an existing `ot-daemon` socket:
`WOTEX_THREAD_DAEMON_SOCKET=/run/openthread-wpan0.sock mix pkg wotex-thread test test/interop/daemon_device_test.exs --include hardware`.

The live native source advisory release check queries OSV, NVD and GitHub and
is described in the
[security policy](../../docs/packages/wotex-thread/security.md):
`mix pkg wotex-thread run --no-start bin/check_native_advisories.exs`.

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-thread/plans/software-implementation.md)
and [specifications](https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-thread/specs) define the remaining software
profile with exact behavior, limits, failure transitions and acceptance scenarios.
These target contracts are build instructions, not claims that every feature
already exists. Required software peers are separate from physical-device tests.

The [standalone client contract](../../docs/packages/wotex-thread/specs/WTH.05-standalone-client-and-preservation.md)
defines the supplied backend, exact native APIs and end-to-end workflows.
Its [concrete corpus](priv/fixtures/contract-v1.json) contains specified,
unexecuted cases; the scenario tables alone are not executable acceptance evidence.

The [specification catalogue](../../docs/packages/wotex-thread/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](../../docs/packages/wotex-thread/specs/WTH.06-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. These are target requirements; a passing baseline
gate does not accept the unfinished software profile.

## License

Wotex Thread is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-thread/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-thread/NOTICE).
