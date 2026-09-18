# Wotex Continuum package contract

Wotex Continuum (`packages/wotex-continuum`, Hex `wotex_continuum`) owns inert,
host-neutral continuum exchange values under `WotexContinuum.*`: manifest,
compatibility, execution-scope and capability values; observation proposals,
Action intents and results, evidence and delivery values; deployment mode,
lifecycle, degradation and exit values; and their bounded codec, canonical
JSON, schemas and vectors at wire schema 2.0.0. It does not own Thing
Description semantics, canonical Thing state, identity, policy, provider
selection, dispatch, persistence, jobs, UI, or release supervision.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Use Consumer, Exposer, interaction affordance and the other W3C terms as the
  cited W3C Web of Things documents define them; Wotex public types and
  specifications are the Elixir vocabulary authority. Continuum fields are
  project-defined: never represent them as W3C-standard fields or imply W3C
  certification.
- No `Application.start/2` callback or dependency-start side effect.
- No hidden process, supervisor, registry, agent, task, network client, or
  mutable global state.
- No database, migration, filesystem authority, job system, web framework, or
  ambient application configuration.
- Constructors and codecs are deterministic, total over documented input, and
  return typed errors.
- Action intent and result remain data; no module dispatches an Action.
- Consumer hosts own clocks, identity, authorization, persistence, I/O,
  supervision, retries, and reconciliation.
- The only WoTEx compile dependency allowed is the core `wotex` package. Never
  import a consumer host or another WoTEx package; the WCT.02 mapping to
  sibling in-memory values is documentation, not a dependency. External
  dependencies must be small, justified, and included in provenance review.
- Public wire changes update the owning WCT specification, `priv/schemas/`,
  `priv/vectors/`, tests, implementation and compatibility classification
  atomically. Package version and wire-schema version stay independent.
- Credentials and non-public fixtures stay out of source, tests, package
  contents and generated documentation. Synthetic examples use `example` names
  and reserved URNs only.

## Where things are

- `lib/wotex_continuum.ex`: entry point; `value.ex`, `contract.ex` and
  `validation.ex`: the shared value contract, envelope and field validators.
- `lib/wotex_continuum/{manifest,artifact,capability,capability_requirement,compatibility,execution_scope}.ex`:
  WCT.01 context and compatibility values.
- `lib/wotex_continuum/{observation_proposal,action_intent,action_result,evidence_reference,delivery,failure,thing_reference}.ex`:
  WCT.02 exchange values; `thing_reference.ex` checks references against a
  core `Wotex.ThingDescription`.
- `lib/wotex_continuum/{mode,lifecycle,degradation,exit_receipt}.ex`: WCT.03
  mode, lifecycle transitions and exit values.
- `lib/wotex_continuum/codec.ex`, `canonical_json.ex`, `limits.ex`: bounded
  decoding (delegated to `Wotex.JSON.decode/2`) and deterministic encoding;
  `schema.ex` embeds `priv/schemas/wct-0{1,2,3}.schema.json`; `error.ex`:
  typed errors with JSON Pointer paths.
- `priv/vectors/{canonical,valid,invalid,compatibility}/`: executable wire
  vectors, shipped in the package. `test/support/json_schema_subset.ex`: the
  schema-keyword evaluator used by the schema tests.
- `bin/check_archive.exs`: archive and isolated-consumer proof (WCT-C04/C05,
  full gate); `bin/check_boundary.exs`: public-boundary scan (full gate).
- Specifications: `docs/packages/wotex-continuum/specs/` (WCT.01 to WCT.03
  and the WCT-C01 to WCT-C05 verification maps; `catalogue.yaml` owns status).
  Completion plan: `docs/packages/wotex-continuum/plans/wotex-continuum-completion.md`;
  threat model and provenance beside it.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-continuum test test/wotex_continuum/<file>_test.exs`, or `mix impact WotexContinuum.Codec decode --run` |
| 1 | `mix check.fast --package wotex-continuum` |
| 2 | `mix check` (full gate here, fast gate in `wotex-lab`) |

The full gate alone is `mix pkg wotex-continuum check --no-retry`
(equivalently `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-continuum`); it adds dependency audits, Doctor, docs, the
coverage floor, Dialyzer, the public boundary scan and the archive check. Run
`mix dialyzer.pkg wotex-continuum` in tier 1 when a typespec or inferred
return type changed.

Tests by area, under `test/wotex_continuum/`:

- Codec, registry and canonical round trips: `codec_test.exs`,
  `property_contract_test.exs`; vectors: `vector_test.exs`.
- Field, default and forged-struct inventory (WCT-C01):
  `contract_inventory_test.exs`; field validators: `validation_test.exs`.
- Native UTF-8 and decoder admission parity (WCT-C02):
  `admission_parity_test.exs`.
- Schema, constructor and codec agreement (WCT-C03):
  `schema_agreement_test.exs`, `schema_conformance_test.exs`.
- Action result, delivery and nested value invariants: `value_state_test.exs`;
  lifecycle matrix: `lifecycle_test.exs`; Thing references:
  `thing_reference_test.exs`.
- Passive load and source boundary: `library_contract_test.exs`; package and
  wire identities: `release_contract_test.exs`; locked Decimal boundary:
  `dependency_security_test.exs`; doctests: `test/documentation_test.exs`.
- Schemas, vectors, `mix.exs` `package` or archive contents: the full gate
  (archive check).

Only `wotex-lab` depends on Wotex Continuum (optionally). Before changing a
public function, list its callers with `mix refs WotexContinuum.Module fun` and
the tests to run with `mix impact WotexContinuum.Module fun`. This package
calls only the public API of `wotex` (`Wotex.ThingDescription`, `Wotex.JSON`,
`Wotex.Error`).

The full gate runs the public boundary scan; run it alone with
`elixir bin/check_boundary.exs` from `packages/wotex-continuum`. There is no
native build, software profile or container lane.