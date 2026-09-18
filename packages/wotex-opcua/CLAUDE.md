# Wotex OPC UA package contract

Wotex OPC UA (`packages/wotex-opcua`, Hex `wotex_opcua`) owns OPC UA values and
Part 6 codecs, bounded protocol operations through the explicitly owned
open62541 C executable and its custody guardian, the explicit native build,
Form mapping, the Runtime Transport and observation relay, and a neutral
compatibility adapter. Wotex core owns W3C Web of Things values and Wotex
Runtime owns interaction mechanics; consumers own policy, credentials,
supervision, connection configuration and canonical Property truth.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications. The native executable is built only by the explicit build
  task, never on dependency load.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- The runtime package runs no Python. asyncua is only an independent software
  peer, and Python is only the SDK code generator during the explicit build.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- TD 1.1 is the baseline. Label binding drafts as drafts; a mapped Form proves
  neither authorization nor a physical effect.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Consumer neutrality is a review obligation; never add a consumer denylist.

## Where things are

- `lib/wotex/opcua.ex`: the `Wotex.OPCUA` facade: compatibility callbacks and
  bounded operations through an explicit client.
- `lib/wotex/opcua/{address,value}.ex`, `binary.ex`, `binary/`: NodeId
  addresses, typed Variant conversion and the Part 6 value, DataValue, name and
  reference codecs; `frame.ex`: UA TCP chunk decoding.
- `lib/wotex/opcua/{client,session,port_call}.ex`: the consumer-selected client
  port and sessions.
- `lib/wotex/opcua/open62541.ex`: the native client over the owned open62541
  executable; `browse.ex`, `browse/`: typed Browse pages and continuations;
  `subscription.ex`: monitored-item subscriptions.
- `lib/wotex/opcua/native/`: native host, custody, framing, ready and config
  (`host*.ex`, `frame.ex`, `ready.ex`, `config.ex`, `executable.ex`), the pinned
  build (`build.ex`, `source.ex`, `recipe.ex`, `toolchain.ex`, `workspace.ex`,
  `archive.ex`, `vendor.ex`, `command.ex`, `bootstrap.ex`) and the software
  lanes (`software.ex`).
- `lib/wotex/opcua/{mapping,transport,runtime_relay,runtime_handle}.ex`: Form
  mapping, the Runtime Transport and the observation relay; `error.ex`:
  structured errors and Runtime classes.
- `lib/mix/tasks/`: the explicit native build and software tasks; `bin/`: the
  native custody, archive and Application-free checks run by the gate.
- `priv/native/`: first-party C sources, CTest checks, the SDK patch, vendored
  yyjson and the native design notes (`runtime-guardian.md`, `json-codec.md`,
  `security.md`, `value-codec.md`).
- Specifications: `docs/packages/wotex-opcua/specs/` (WOP.01–WOP.03,
  WOP.04–WOP.07; `catalogue.yaml` owns status). Plans and evidence:
  `docs/packages/wotex-opcua/plans/` and `provenance/`.
- Fixtures: `priv/fixtures/` (contract, integration, native contract, custody,
  JSON, ready and pinned native source corpora).
- Test support: `test/support/` (scripted and streaming clients, recording and
  failure transports, credentials); `test/native/` (C probes and fixtures);
  `test/interop/` (asyncua secure peer, its hash-pinned lock and the peer
  suites).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-opcua test test/wotex/opcua/<file>_test.exs`, or `mix impact Wotex.OPCUA.Module fun --run` |
| 1 | `mix check.fast --package wotex-opcua` |
| 2 | `mix check` (full gate here) |

Native code (`priv/native/`, `test/native/`): `mix native.lint --package
wotex-opcua` checks clang-format on the changed lines (`--fix` formats them).
The full gate adds `native_lint` (clang-tidy with the CMake compile commands
against the pinned open62541 build) and `native_test` (that build's CTest
suite), in a cached workspace outside the repository; `mix native.test
--package wotex-opcua` runs the tests alone. `priv/native/vendor/` is never
formatted or linted.

The full gate alone is `mix pkg wotex-opcua check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-opcua`); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer, the native
custody check, `mix hex.build`, the archive check and the Application-free
check. Its coverage step sets `WOTEX_REQUIRE_NATIVE_BUILD=1` and so runs a real
pinned native build under `$TMPDIR/wotex-opcua-check`: it needs network access
and the native toolchain below. Run `mix dialyzer.pkg wotex-opcua` in tier 1
when a typespec, a client callback or an inferred return type changed. The
ordinary test run needs `cc`.

Tests by area, under `test/wotex/opcua/` unless noted:

- Values and Part 6 codecs: `value_test.exs`, `typed_values_test.exs`,
  `binary_test.exs`, `binary/names_test.exs`, `binary/reference_test.exs`.
- Form mapping and the facade contract: `mapping_test.exs`,
  `contract_test.exs`, `port_test.exs`, `standalone_contract_test.exs`.
- Native client, persistent Sessions and Browse: `open62541_test.exs`,
  `persistent_bridge_test.exs`.
- Native host, custody and IPC: `native/host_test.exs`,
  `native/host_options_test.exs`, `native/custody_test.exs`,
  `native/guardian_startup_test.exs`, `native/ready_test.exs`,
  `native/frame_test.exs`, `native/json_test.exs`, `native/executable_test.exs`,
  `native/config_test.exs`.
- Native build tooling: `native/build_test.exs` (the real build is tagged
  `native_build`), `native/build_fault_test.exs`, `native/workspace_test.exs`,
  `native/archive_test.exs`, `native/source_test.exs`, `native/vendor_test.exs`,
  `native/recipe_test.exs`, `native/toolchain_test.exs`,
  `native/command_test.exs`, `native/bootstrap_test.exs`; software tasks with
  fake tools: `native/software_test.exs`.
- Runtime integration and observations: `runtime_integration_test.exs`,
  `runtime_stream_test.exs`.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- Peer suites (`interop`/`software` tags, software lane only):
  `test/interop/`, `test/software/lifecycle_stress_test.exs`,
  `subscription_lifecycle_test.exs`.
- C sources in `priv/native/`: native CTest through the native build or
  software lane; package contents or `mix.exs` `package`: the full gate.

No sibling package depends on `wotex-opcua`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.OPCUA.Module fun` and the tests to run with
`mix impact Wotex.OPCUA.Module fun` before changing a public function.

Explicit-only lanes, never part of a bounded change. Each takes a disposable
absolute workspace (new or empty; the native build also reuses a verified one):

```console
mix wotex.native.build --package wotex-opcua --workspace /absolute/disposable/dir
mix pkg wotex-opcua wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-opcua wotex.software.run --workspace /absolute/disposable/dir
```

The native build needs network access, `cc`, CMake 3.20+ with `ctest`, `make`,
Perl, `python3`, `ar`, `ranlib`, `ld` and curl 8.4.0+ on Linux x86_64/aarch64
or macOS arm64. The software build adds a hash-pinned asyncua virtual
environment (`python3 -m venv`, PyPI access) and an ASan/UBSan tree; the run
starts the peer and runs the `interop`/`software` suites, native and sanitizer
CTest and the dependency audits. Apply the shared
`.claude/skills/spec-delivery/SKILL.md` for public behavior and standards
claims and `.claude/skills/release-readiness/SKILL.md` for compatibility
claims.
