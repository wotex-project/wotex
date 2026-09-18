# Wotex Matter package contract

Wotex Matter (`packages/wotex-matter`, Hex `wotex_matter`) owns Matter values
(paths, TLV, descriptors, reports), bounded Interaction Model operations,
commissioning and subscriptions through the first-party C++ connectedhomeip
controller Port, Form mapping, the Runtime Transport and stream relay, and a
neutral compatibility adapter. Wotex core owns W3C Web of Things values and
Wotex Runtime owns interaction mechanics; consumers own policy, credentials,
supervision, connection configuration and canonical Property truth.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Production protocol execution uses the first-party C/C++ Port specified in
  WMA.13. Generic build/fixture orchestration and assertions use Mix/ExUnit.
  Python is limited to required upstream build tools or justified independent
  test peers.
- Specifications state contracts declaratively; implementation status and
  evidence are separate. Do not write changelog or migration narratives.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child
  specifications. No native binary ships or builds with the dependency.
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

- `lib/wotex/matter.ex`: the `Wotex.Matter` facade: compatibility callbacks,
  named operations, commissioning, subscriptions and `profile/0,1`;
  `standalone.ex` implements the named operations.
- `lib/wotex/matter/{address,read_path,tlv,descriptor,endpoint_catalogue,path_results}.ex`:
  paths, bounded TLV, the descriptor registry and batch-read results;
  `{attribute_report,event_report,onboarding_material}.ex`: typed results.
- `lib/wotex/matter/{client,session,port_call,subscription}.ex`: the client
  port, sessions and subscription handles.
- `lib/wotex/matter/native.ex` and `native/`: the `Native` client over the
  first-party host: admission, Port connection, request bounds, wire decoding,
  report ledger, stream owner and process command.
- `lib/wotex/matter/{mapping,transport,runtime_oneshot}.ex`, `runtime_relay*`:
  Form mapping, the Runtime Transport and the relay owning a Runtime stream;
  `error.ex`: structured errors and Runtime classes.
- `native/`: the C++17 controller host (`src/`, `include/wotex_matter/`),
  process-flow and resource test hosts (`testing/`), CMake and GN builds;
  `test/native/`: its C++ unit tests.
- `lib/mix/tasks/`: the explicit native and software tasks; `bin/`: the
  gate's archive and application-free checks plus the per-packet native and
  advisory lanes.
- Specifications: `docs/packages/wotex-matter/specs/` (WMA.00–WMA.03,
  WMA.10–WMA.13; `catalogue.yaml` owns status). Plans and evidence:
  `docs/packages/wotex-matter/plans/` and `provenance/`.
- Fixtures: `priv/fixtures/` (contract, native-port and integration corpora).
- Test support: `test/support/` (scripted clients, Runtime credentials and
  result transport); `test/support/software/` (build, run, scenarios, peers,
  manifests and the required-case inventory `acceptance.json`).

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-matter test test/wotex/matter/<file>_test.exs`, or `mix impact Wotex.Matter.Module fun --run` |
| 1 | `mix check.fast --package wotex-matter` |
| 2 | `mix check` (full gate here) |

Native code (`native/`, `test/native/`): `mix native.lint --package
wotex-matter` checks clang-format on the changed lines (`--fix` formats
them). The full gate adds `native_lint` and `native_test`: the SDK-free value
library and its CTest build on the host; the SDK-bound sources build in the
pinned linux/amd64 container (`wotex.matter.native.build`, Docker), which
runs their CTest suite, normal and sanitized. clang-tidy has no compile
commands for the SDK-bound translation units outside that container, so
`native_lint` reports them as not analysed. The `.inc` peer fragments follow
the SDK's style and are excluded.

The full gate alone is `mix pkg wotex-matter check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-matter`); it
adds dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the
exact-archive check and the application-free check. Run
`mix dialyzer.pkg wotex-matter` in tier 1 when a typespec, a client callback
or an inferred return type changed. The ordinary test run needs only
`/bin/sh` and `/bin/kill`; it excludes `interop`, `software` and `hardware`.

Tests by area, under `test/wotex/matter/` unless noted:

- Paths, TLV and descriptors: `path_value_test.exs`, `tlv_test.exs`,
  `descriptor_boundary_test.exs`.
- Named operations and commissioning: `interaction_test.exs`,
  `interaction_boundary_test.exs`, `standalone_boundary_test.exs`,
  `commissioning_test.exs`.
- Subscriptions and recovery: `subscription_test.exs`,
  `subscription_recovery_test.exs`, `report_ledger_test.exs`.
- Native client, Port framing and admission: `native_contract_test.exs`,
  `native_frame_test.exs`, `native_request_test.exs`,
  `native_startup_test.exs`, `native_wire_test.exs`,
  `persistent_bridge_test.exs`, `admission_test.exs`,
  `process_command_test.exs`.
- Form mapping and the facade contract: `mapping_test.exs`,
  `contract_test.exs`, `port_test.exs`.
- Runtime integration and streams: `runtime_integration_test.exs`,
  `runtime_stream_test.exs`, `runtime_relay_test.exs`.
- Software-lane tooling (build, run, peers, scenarios, acceptance inventory):
  `software_*_test.exs`; peer workflows in `test/interop/` and stress/resource
  census in `test/software/` run only in the software lane.
- Locked Decimal parser boundary: `dependency_security_test.exs`.
- C++ host: `test/native/*.cpp`, only in the native lanes.
- Package contents or `mix.exs` `package`: the full gate (archive check).

No sibling package depends on `wotex-matter`; it uses only the public APIs of
`wotex` and `wotex-runtime`. Consumers call its public API, so list callers
with `mix refs Wotex.Matter.Module fun` and the tests to run with
`mix impact Wotex.Matter.Module fun` before changing a public function.

Explicit-only lanes, never part of a bounded change. They need Docker able to
run `linux/amd64` containers, `git`, `curl`, `tar`, `kill` and network access
for the pinned SDK sources and OSV. The workspace is a disposable absolute
directory outside the package, empty or holding a matching manifest:

```console
mix wotex.native.build --package wotex-matter --workspace /absolute/disposable/dir
mix pkg wotex-matter wotex.software.build --workspace /absolute/disposable/dir
mix pkg wotex-matter wotex.software.run --workspace /absolute/disposable/dir
(cd packages/wotex-matter && elixir bin/check_p01_native.exs)
(cd packages/wotex-matter && elixir bin/check_p02_native.exs)
mix pkg wotex-matter run bin/check_p03_native.exs   # also check_p04..p07_native.exs
mix pkg wotex-matter run bin/check_p03_advisories.exs  # also check_p02_advisories.exs
```

A native-only workspace cannot be reused for a software build. Native C++
changes require the affected native lanes; see the README Development section.
Apply the shared `.claude/skills/spec-delivery/SKILL.md` for public behavior
and standards claims and `.claude/skills/release-readiness/SKILL.md` for
compatibility claims.
