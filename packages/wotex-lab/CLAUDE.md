# Wotex Lab package contract

Wotex Lab (`packages/wotex-lab`, Hex `wotex_lab`) is the family's consumer
laboratory, with Nx as the primary numerical adoption path. It owns scenarios
and their runner, reference adapters behind sibling ports, evidence records,
the conformance target and containment profiles, the knowledge graph, MCP,
metrics, cookbooks, and the Workbench and Nerves reference hosts. Dependencies
point from Lab to public libraries; no package depends on Lab. Do not copy
private package implementations or change WoT meaning. Repository-wide rules
are in the root `CLAUDE.md`.

## Invariants

- Loading Lab starts no Lab process. Consumers explicitly place its child spec.
- Processes, stores and simulated effects belong to an explicit Lab instance.
  No singleton, auto-discovery, implicit backend change or application callback.
- Keep one module per `.ex`. Tests have `@moduledoc false` and a blank line.
- Use structured errors, explicit options, bounded work and public package APIs.
- No model download, Action dispatch or verification pool starts implicitly.
- Numerical output and formal-model results are inert; neither grants authority.
- PromEx/BeamLens/Phoenix belong to an explicit reference host. GreptimeDB is
  a supplied/local service, not embedded BEAM storage. No implicit LLM calls,
  introspection, database connection or public metrics listener.
- The Workbench is one LiveView application with the Svelte 5 islands, Vite,
  Storybook and browser TypeScript/JavaScript selected by WLB.11 and WLB.12.
  Backend and native language constraints do not restrict frontend source or
  build tooling. The base library keeps its first-tensor path independent of
  Phoenix and Node, and the reference release starts no Node runtime process.
- Workspace mode (`WOTEX_PATH_DEPS=1`) never proves artifact adoption. Release
  paths use Hex or verified archives.
- Specs and completion contracts describe the entire accepted programme; do not
  create a deferred backlog, TODO modules or fake successful adapters.
- Distinguish implemented source, evidence coverage and artifact adoption.
  Unbuilt accepted contracts have `implementation_status: planned`.
- Preserve sibling ownership. Evidence references do not close sibling work
  items or authorize edits to their catalogues.
- Publish only consumer-neutral fixtures and allowlisted documentation. No
  secrets, coordination daemons or shared execution trackers.
- Lab holds the one exception to the root rule that code never reads `docs/`:
  its documentation-backed development features (the knowledge graph and its
  MCP resources) read `docs/packages/wotex-lab/` as their subject, only
  through `Wotex.Lab.Documentation`, and report it unavailable in a released
  archive. Everything else Lab reads lives in `priv/`; add no other reader.
- `priv/provenance/source-index.json` is a historical snapshot: never move its
  statuses or digests to current sibling state. `source-cohort.json` and the
  `WLB.0x-evidence.json` records change only by re-running their evidence.
- `priv/provenance/wotex-lab-api.json` records the public surface. A changed
  public function, struct or typespec needs
  `mix pkg wotex-lab run --no-start bin/generate_api_surface.exs --write` and a
  compatibility review.

## Where things are

- `lib/wotex/lab.ex`, `supervisor.ex`, `options.ex`, `plugin.ex`,
  `component.ex`: the explicit Lab instance, role supervisors and component
  activation (WLB.01, WLB.02).
- `scenario.ex`, `runner.ex`, `runner/`, `lib/mix/tasks/wotex.lab.scenarios.ex`:
  admitted scenario descriptors and the bounded runner with replay (WLB.02).
- `examples/`, `simulators/`, `experiments/`, `analytics.ex`, `analytics/`,
  `benchmark.ex`: the Nx lanes and Explorer analysis (WLB.03).
- `adapters/{runtime,http,mqtt,directory,nx}/`, `reference/thing.ex`,
  `network/`: reference adapters and the simulated Thing host (WLB.04, WLB.05).
- `continuum/`, `smart_room/`: the Continuum channel/host and the smart room
  (WLB.05).
- `evidence/`, `conformance/`, `telemetry.ex`: evidence records, the
  conformance target and containment profiles (WLB.06).
- `cookbook.ex`, `graph.ex`, `graph/`, `mcp/`, `documentation.ex`: cookbooks,
  the knowledge graph and its representations, MCP (WLB.07).
- `formal/`: the ex_maude verification profile (WLB.09). `metrics/`, `otlp/`:
  collector, history, remote write and GreptimeDB (WLB.10).
  `design_system.ex`: tokens (WLB.11).
- `hosts/workbench/` and `hosts/nerves/`: separate Mix projects for the
  reference hosts; `clients/typescript/`: the generated control client.
- `priv/fixtures/<lane>/` (manifest with input digest), `priv/cookbooks/`,
  `priv/models/`, `priv/conformance/native/` (Rust helper source),
  `priv/provenance/` (evidence records, source index and cohort, SBOM, API
  snapshot). `bin/`: gate and lane scripts; `bin/support/`: shared helpers.
- `test/support/`: component fixtures, HTTP/MQTT servers, broker, GreptimeDB
  and remote-write harnesses, the native helper builder, the cookbook runner.
- Specifications: `docs/packages/wotex-lab/specs/` (WLB.01 to WLB.12;
  `catalogue.yaml` owns status). Plans, the qualification runbook, decisions and
  provenance reviews sit beside them. The graph digests every document;
  `bin/check_graph.exs`,
  `bin/check_contracts.exs` (spec headings, versions and links) and
  `bin/generate_typescript_client.exs` reach the tree through
  `Wotex.Lab.Documentation` too.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-lab test test/wotex/lab/<file>_test.exs`, or `mix impact Wotex.Lab.Runner start --run` |
| 1 | `mix check.fast --package wotex-lab` (also compiles, formats, lints and tests both hosts) |
| 2 | `mix check` (full gate here; Lab has no dependents) |

Rust (`priv/conformance/native/`): `mix native.lint --package wotex-lab` runs
`cargo fmt --check` and clippy with `-D warnings` (`--fix` formats); the full
gate adds `native_test` (`cargo test --all-features --locked`). The toolchain
is pinned in the root `rust-toolchain.toml` (`mise install`).

The full gate alone is `mix pkg wotex-lab check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-lab`). Beyond
tier 1 it runs the audits, Doctor, docs, the 95% coverage floor, Dialyzer,
the contract, graph, API-surface, Nerves-source, boundary and package-content
scripts, `optional_deps` (compiles without the optional dependencies with
warnings as errors and tests their typed fallbacks), and the reference hosts'
own gates: `workbench` (`mix check` in
`hosts/workbench/`) and `nerves_host` (`mix check` in `hosts/nerves/` with
`MIX_TARGET=host`). A host change is ready when
`mix pkg wotex-lab check --no-retry --only workbench` (or
`--only nerves_host`) passes; host Credo follows this package's
`.credo.exs`. Run `mix dialyzer.pkg wotex-lab` in tier 1 when a typespec or
inferred return type changed. If Dialyzer reports `call_to_missing` for a
sibling function after a sibling change, delete `priv/plts/dialyxir.plt*` and
rerun.

Tests by area, all under `test/wotex/lab/`:

- Instance, supervisors, options, errors: `library_contract_test.exs`,
  `supervisor_test.exs`, `options_test.exs`, `error_test.exs`.
- Scenarios and runner: `scenario_test.exs`, `runner_test.exs`,
  `scenario_frontends_test.exs`.
- Nx lanes: `thermal_test.exs`, `window_anomaly_test.exs`, `serving_test.exs`,
  `room_model_test.exs`, `backend_cohort_test.exs`, `analytics_test.exs`,
  `benchmark_test.exs`.
- Adapters: `loopback_test.exs`, `http_test.exs`, `http_destination_test.exs`,
  `network_destination_test.exs`, `mqtt_test.exs`,
  `mqtt_sample_admission_test.exs`, `directory_test.exs`.
- Continuum and smart room: `continuum_test.exs`, `smart_room_test.exs`.
- Evidence, conformance, telemetry: `evidence_test.exs`,
  `evidence_digest_errors_test.exs`, `conformance_containment_test.exs`,
  `conformance_target_process_test.exs`, `kernel_containment_test.exs`,
  `telemetry_test.exs`.
- Graph, cookbooks, MCP: `graph_test.exs`, `cookbook_catalogue_test.exs`,
  `cookbook_runner_test.exs`, `mcp_*_test.exs`; after editing the catalogue,
  specs or descriptors also run
  `mix pkg wotex-lab run --no-start bin/check_contracts.exs` and
  `mix pkg wotex-lab run --no-start bin/check_graph.exs`.
- Formal: `formal_test.exs`, `formal_search_test.exs`,
  `mcp_formal_tool_test.exs`. Metrics: `metrics_*_test.exs`,
  `otlp_*_test.exs`. Design system: `design_system_test.exs`.
- Release tooling: `reference_inputs_test.exs`, `reference_summary_test.exs`,
  `check_work_directory_test.exs`, `dependency_security_test.exs`.

No package depends on Lab, so a Lab change needs only Lab's gate. Before
changing a public function, still list its callers with
`mix refs Wotex.Lab.Module fun`: the Workbench and Nerves hosts and the
cookbooks call the Lab API. A sibling change reaches Lab through
`mix impact` on the sibling's module.

Explicit-only lanes, run inside `packages/wotex-lab` and only when asked (the
README's Development section lists prerequisites): tagged suites behind
`WOTEX_LAB_INTEGRATION=1` (conformance source suite with Rust, cookbook
execution, evidence manifests, source cohort), `WOTEX_LAB_BROKER=1`,
`WOTEX_LAB_GREPTIME=1`, `WOTEX_LAB_MAUDE=<path>` and `WOTEX_LAB_CONTAINER=1`;
`elixir bin/check_native_containment.exs`,
`elixir bin/check_linux_containment.exs`,
`elixir bin/check_source_cohort.exs`, and
`WOTEX_PATH_DEPS=1 mix run --no-start bin/check_reference_consumer.exs`,
`bin/check_archive_consumer.exs` and `bin/check_workbench_archive.exs`, and
the Nerves rpi4 firmware build (`MIX_TARGET=rpi4 mix firmware`, which needs
the Nerves toolchain, `nerves_bootstrap` and `fwup`).
