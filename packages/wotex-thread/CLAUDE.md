# Wotex Thread package contract

Wotex Thread (`packages/wotex-thread`, Hex `wotex_thread`) owns Thread values
(Operational Datasets, joiner identities and admissions, State snapshots),
bounded read-only `ot-daemon` management, the explicitly started OpenThread SDK
adapter with its first-party C++ Port under `priv/openthread/`, Form mapping,
the Runtime Transport, a neutral compatibility adapter and the explicit native
build and software-fixture tooling. Wotex core owns W3C Web of Things values and
Wotex Runtime owns interaction mechanics; consumers own policy, credentials,
supervision, connection configuration and canonical Property truth.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Production protocol execution uses the first-party C/C++ Port specified in
  WTH.13. Generic build/fixture orchestration and assertions use Mix/ExUnit.
  Python is limited to required upstream build tools or justified independent
  test peers.
- Specifications state contracts declaratively; implementation status and
  evidence are separate. Do not write changelog or migration narratives.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications. No build or download happens outside the explicit tasks.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- TD 1.1 is the baseline. Label binding drafts as drafts; a mapped Form proves
  neither authorization nor a physical effect.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- Consumer neutrality is a review obligation; never add a consumer denylist.

## Where things are

- `lib/wotex/thread.ex`: the `Wotex.Thread` facade: compatibility callbacks,
  native Dataset/management/commissioner helpers and State subscriptions.
- `lib/wotex/thread/{dataset,state,joiner_identity,joiner_config,joiner_admission,address}.ex`:
  Operational Dataset TLVs, State snapshots, joiner values and the read-only
  request set.
- `lib/wotex/thread/{client,session,port_call}.ex`: the client port and
  sessions; `daemon.ex`: the read-only `ot-daemon` Unix-socket client.
- `lib/wotex/thread/open_thread.ex` and `open_thread/`: the owned Linux SDK
  host: configuration, the bridge connection and request queue, frame decoding,
  Dataset wire envelopes, commissioning values, State stream ownership and the
  report ledger; `subscription.ex` is the State subscription handle.
- `lib/wotex/thread/{mapping,transport}.ex`: Form mapping and the Runtime
  Transport; `error.ex`: structured errors.
- `lib/wotex/thread/native/`: the native build (pinned sources, SDK fixes,
  workspace manifests, compiler bootstrap and command guardian);
  `lib/wotex/thread/software/`: the software fixture build and run;
  `lib/mix/tasks/`: their Mix tasks.
- `priv/openthread/`: the C++ host, CMake project and source pins
  (`dependencies.json`); `priv/provenance/native-advisories.json`: native
  advisory reviews; `bin/`: the archive, application-free and native advisory
  checks.
- Specifications: `docs/packages/wotex-thread/specs/` (WTH.00–WTH.02,
  WTH.10–WTH.13; `catalogue.yaml` owns status). Plans, security policy and
  evidence: `docs/packages/wotex-thread/plans/`, `security.md` and
  `provenance/`.
- Fixtures: `priv/fixtures/` (contract, native-port and integration corpora);
  test peers in `test/fixtures/` (the escript SDK bridge and C fault peers).
- Test support: `test/support/` (scripted client, `BuildFixture` for recorded
  build environments, the software case formatter); `test/native/` (C/C++
  native tests and drivers built by the software lane);
  `test/software/acceptance.json` (required cases per software lane).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-thread test test/wotex/thread/<file>_test.exs`, or `mix impact Wotex.Thread.Module fun --run` |
| 1 | `mix check.fast --package wotex-thread` |
| 2 | `mix check` (full gate here) |

Native code (`priv/openthread/`, `test/native/`, `test/fixtures/*.c`):
`mix native.lint --package wotex-thread` checks clang-format on the changed
lines (`--fix` formats them). The full gate adds `native_lint` (clang-tidy)
and `native_test`: the SDK-free protocol tests (CTest) on any host and, on
Linux, the OpenThread host build and the SDK-bound Spinel test; on another
host the Linux suite fails with a message.

The full gate alone is `mix pkg wotex-thread check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-thread`); it
adds dependency audits, Doctor, docs, the coverage floor, Dialyzer, the
exact-archive reference consumer and the application-free check. Run
`mix dialyzer.pkg wotex-thread` in tier 1 when a typespec, a client callback
or an inferred return type changed. The ordinary test run needs `/usr/bin/cc`
and `escript`; it excludes the `interop`, `software` and `hardware` tags.

Tests by area, under `test/wotex/thread/` unless noted:

- Dataset, State and joiner values: `dataset_test.exs`,
  `dataset_boundary_test.exs`, `sdk_values_test.exs`,
  `commissioning_value_test.exs`.
- Facade, sessions and Form mapping: `contract_test.exs`, `port_test.exs`,
  `session_boundary_test.exs`, `mapping_test.exs`,
  `contract_fixture_test.exs`.
- `ot-daemon` client: `daemon_test.exs`, `daemon_fault_test.exs`.
- OpenThread bridge, frames and Dataset/management commands:
  `sdk_bridge_test.exs`, `sdk_frame_test.exs`, `sdk_dataset_test.exs`,
  `sdk_dataset_wire_test.exs`, `management_test.exs`,
  `connection_boundary_test.exs`.
- State subscriptions and flow credit: `state_subscription_test.exs`,
  `report_ledger_test.exs`.
- Native build and software tooling: `native_build_test.exs`,
  `native_command_test.exs`, `native_source_test.exs`,
  `native_tooling_test.exs`, `native_workspace_test.exs`,
  `native_tasks_test.exs`, `software_build_test.exs`,
  `software_fixture_test.exs`, `software_run_test.exs`.
- Native advisory reviews and the locked Decimal parser boundary:
  `native_advisories_test.exs`, `dependency_security_test.exs`.
- Real SDK, process-flow and stress cases: `test/software/` and
  `native_contract_test.exs` (`software` tag, software lane only).
- Package contents or `mix.exs` `package`: the full gate (archive check).

No sibling package depends on `wotex-thread`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.Thread.Module fun` and the tests to run with
`mix impact Wotex.Thread.Module fun` before changing a public function.

Explicit-only lanes, never part of a bounded change. They require Linux,
`cmake`, `ninja`, `cc`, `c++`, `readelf`, HTTPS access to the pinned sources
and a disposable absolute workspace (empty, or a completed manifest that is
verified and reused):

```console
mix pkg wotex-thread wotex.native.build --workspace /absolute/disposable/native [--sanitizers]
mix pkg wotex-thread wotex.software.build --workspace /absolute/disposable/software
mix pkg wotex-thread wotex.software.run --workspace /absolute/disposable/software
```

`mix wotex.native.build --package wotex-thread --workspace /absolute/dir`
dispatches the native build from the root. The software run needs a completed
software build and a fresh workspace per run. Also explicit: the `hardware`
test (`WOTEX_THREAD_DAEMON_SOCKET=/path mix pkg wotex-thread test test/interop/daemon_device_test.exs --include hardware`)
and the live native advisory check
(`mix pkg wotex-thread run --no-start bin/check_native_advisories.exs`, network
access to OSV, NVD and GitHub). Apply the shared
`.claude/skills/spec-delivery/SKILL.md` for public behavior and standards
claims and `.claude/skills/release-readiness/SKILL.md` for compatibility
claims.
