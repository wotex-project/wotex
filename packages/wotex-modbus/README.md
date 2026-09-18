# Wotex Modbus

**Consumer-neutral Modbus interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_modbus.svg)](https://hex.pm/packages/wotex_modbus)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_modbus)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_modbus.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-modbus/LICENSE)

[Installation](#installation) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Wotex contract](#wotex-contract) ·
[Development](#development) ·
[Software contract](#software-implementation-contract)

---

This package is under development and its public API is unstable; software
interoperability does not establish certification or a published release.

## Installation

Wotex Modbus 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual; Hex
resolves `wotex` and `wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_modbus, "~> 0.1"}
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
    {:wotex_modbus,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-modbus",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_modbus, path: "../wotex/packages/wotex-modbus", override: true}
```

Path dependencies prove nothing about a released artifact. The
[release-candidate dossier](../../docs/packages/wotex-modbus/specs/WMB.08-release-candidate-dossier.md)
maps the reviewed API, dependencies, standards scope, legal/security boundary,
verification commands and explicit nonclaims.

## Implemented profile

Classic Modbus TCP functions 1, 2, 3, 4, 5, 6, 15 and 16; strict MBAP/response
validation; integer/float register conversion; explicit socket ownership;
WoT Forms and Runtime requests; neutral compatibility callbacks.

`Wotex.Modbus.profile/0` supplies the native TCP Runtime profile. Admission is
bounded to 64 requests per connection, with one active exchange and a deadline
that includes queue time. An unsent rejected request has no write effect;
a transmitted write with an uncertain outcome reports `effect: :unknown` and
cannot be classified as retryable.

## Quick start

```elixir
{:ok, session} = Wotex.Modbus.connect(host: "127.0.0.1", port: 1502, unit_id: 1)
try do
  Wotex.Modbus.read_holding_registers(session, 0, 2)
after
  Wotex.Modbus.disconnect(session)
end
```

No RTU/serial, Modbus Security, built-in polling or physical certification is
claimed. See [protocol contract](../../docs/packages/wotex-modbus/specs/WMB.02-protocol.md),
[Form profile](../../docs/packages/wotex-modbus/specs/WMB.03-form-profile.md) and
[independent interoperability](test/interop/README.md).

## Wotex contract

Values, validation and Form mapping belong here. The consumer owns credentials,
policy, supervision and the interpretation of protocol acknowledgements.
Loading the package does not start a transport. No simulator is selected implicitly.

Each connection is linked to its caller and serializes requests over one
numeric Internet Protocol endpoint. The library validates Modbus Application
Protocol headers, transaction correlation, Unit Identifiers, function-specific
limits, and response shapes. It does not silently retry writes; a transport
failure can therefore leave the physical effect unknown to the caller.

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-modbus test test/wotex/modbus/codec_test.exs  # one test file
mix check.fast --package wotex-modbus                       # compile, format, Credo, tests
mix pkg wotex-modbus check --no-retry                       # full gate
mix native.lint --package wotex-modbus                      # clang-format on changed C/C++ lines
mix native.test --package wotex-modbus                      # native tests
```

The full gate also checks the first-party C and C++ code: clang-format on the
changed lines, clang-tidy and the native tests, built in a cached workspace
outside the repository; see [Native code](https://github.com/wotex-project/wotex/blob/main/docs/guides/development.md#native-code).

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-modbus`. It compiles with warnings as errors, checks the lock
and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the coverage floor (`mix coveralls`), Dialyzer and
`git diff --check`, then runs `bin/check_archive.exs` and
`bin/check_application_free.exs`. The archive check builds the exact `wotex`,
`wotex_runtime` and `wotex_modbus` candidate archives from `packages/` without
path dependencies, serves them with the locked public dependencies from an
OS-temporary signed Hex registry, installs them into an isolated consumer that
must lock only Hex entries, and exercises direct and Runtime Modbus exchanges
against consumer-owned loopback peers. It prints the three archive digests and
the consumer-lock digest; it does not publish anything. The second check proves
that the package defines no Application callback.

The ordinary test run needs a POSIX C11 compiler (`cc`): the software-fixture
command guardian in `test/interop/native/` is compiled and exercised by
`test/software/command_test.exs`. Tests tagged `interop`, `software` or
`hardware` are excluded; they need the independent peer and fail if selected
without it. See the [delivery contract](../../docs/packages/wotex-modbus/plans/wotex-modbus-completion.md).

### Software peer lane

The independent libmodbus peer is an explicit lane, outside the gate. Pass a
disposable absolute directory outside `packages/wotex-modbus`, and run the lane
once per supported toolchain:

```console
mix pkg wotex-modbus wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-modbus wotex.software.run --workspace /absolute/disposable/dir
```

The build needs Docker, `cc` (or `$CC`), `curl` and network access. It
compiles the command guardian with the host compiler, downloads the pinned
libmodbus 3.1.12 archive and verifies its SHA-256, builds an ASan/UBSan
libmodbus peer in a pinned Linux image from `test/interop/libmodbus/Dockerfile`
and writes a verified `peer-manifest.json`. The workspace must be empty or hold
a matching manifest. The run needs Docker and that built workspace: it starts
the peer in an owned read-only container on a loopback port, runs
`mix test --include interop --include software --exclude hardware` against it
and writes `result.json` with outcomes and cleanup results under a new
`run-*` directory in the workspace. The fully qualified task names are
`wotex.modbus.software.build` and `wotex.modbus.software.run`;
`test/interop/build_software.sh` and `run_software.sh` are thin delegates.
There is no production native build: protocol execution is BEAM TCP.

The command guardian also has a Linux ASan/UBSan lane. From
`packages/wotex-modbus`, with Docker:

```console
docker build --tag wotex-modbus-guardian test/interop/native
docker run --rm wotex-modbus-guardian
```

## Software implementation contract

The [ordered implementation sequence](../../docs/packages/wotex-modbus/plans/software-implementation.md)
and [specifications](https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-modbus/specs) define the software profile's
behavior, limits, failure transitions, acceptance scenarios and concrete fixtures.
Executable tests cover the contract corpus, real Runtime interactions, strict
stream correlation, bounded admission, and owner cleanup. The software fixture
builds a pinned libmodbus peer and records commands, hashes, failures, cleanup,
and the active toolchain. It requires Docker and runs once per selected toolchain
through the [software peer lane](#software-peer-lane).

Required software peers are separate from physical-device tests. A specification
or catalogue status alone is not execution evidence.

The [standalone client contract](../../docs/packages/wotex-modbus/specs/WMB.05-standalone-client-and-preservation.md)
defines native workflows and feature-preservation obligations. Its concrete
fixture corpus contains specified cases; execution results remain in provenance.

The [specification catalogue](../../docs/packages/wotex-modbus/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](../../docs/packages/wotex-modbus/specs/WMB.06-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. Re-run the checked-in software harness for the
source revision under review; earlier results do not validate later changes.

## Native build and software orchestration

[WMB.07](../../docs/packages/wotex-modbus/specs/WMB.07-native-build-and-software-evidence.md) defines
the explicit `mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS` interfaces (package aliases; from the
repository root run them through `mix pkg wotex-modbus`, as in Development).
Protocol execution remains
BEAM TCP with a C libmodbus test peer.
The Mix tasks build and verify manifests, run the independent peer and record
actual ExUnit outcomes and cleanup results. Full task acceptance requires fresh
results on both supported toolchains. A native owner-liveness guardian covers the
whole Docker create/start interval, including whole-VM loss, while exact CID and
random-label checks constrain cleanup to the owned peer. Shell compatibility
entry points execute the Mix tasks; no Python build/test orchestrator is required.

## License

Wotex Modbus is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-modbus/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-modbus/NOTICE).
