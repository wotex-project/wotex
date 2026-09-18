# Wotex Nx package contract

Wotex Nx (`packages/wotex-nx`, Hex `wotex_nx`) owns the explicit numerical
conversion between Wotex values and Elixir Nx: typed observations, ordered
features, deterministic temporal windows, lazy `Nx.Batch` encoding and
decoding of numerical output into inert values. The core `wotex` package owns
W3C Web of Things values and terminology; this package inherits them and adds
only numerical semantics. Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- No model fetching, training, selection, serving, agent routing, Action
  execution, authorization, canonical state, database, Repo, migration, Ash,
  Phoenix, Ecto, Oban, endpoint, application callback, or global registry.
- Loading starts no process. Every operation is deterministic and
  caller-driven; the package never reads a clock.
- All time, identity, window, unit, missing-value, dtype, shape, quality, and
  output interpretations are explicit inputs. Silent coercion is forbidden.
- Numerical output and Action proposals are inert values, never authority.
- Observation, feature, prediction, anomaly and Action-proposal values are
  package extension terms, never presented as W3C-defined structures.
- Tensor layout, dtype, mask polarity (`1` observed), quality codes, temporal
  selection and output meaning are public contract; changing them needs a
  WNX.01 version and explicit compatibility review.
- One module per `.ex`. Tests use `@moduledoc false` followed by a blank line.

## Where things are

- `lib/wotex/nx.ex`: entry point and stable quality codes.
- `lib/wotex/nx/observation.ex`, `row.ex`: caller-supplied observations and
  timestamped rows.
- `lib/wotex/nx/feature.ex`, `schema.ex`: ordered features derived from a
  `Wotex.DataSchema` and allocation limits; `numerical_schema.ex`,
  `data_schema_validator.ex` and `data_schema_contract.ex` (hidden) map the
  supported DataSchema subset.
- `lib/wotex/nx/window.ex`: deterministic resampling and selection.
- `lib/wotex/nx/encoder.ex`, `encoded.ex`, `encoded/lazy_container.ex`: rows to
  a lazy `Nx.Batch`, masks and quality vectors.
- `lib/wotex/nx/output_schema.ex`, `decoder.ex`: the accepted output contract
  and decoding into `Observation`, `Prediction`, `Anomaly` or
  `ActionProposal` (`prediction.ex`, `anomaly.ex`, `action_proposal.ex`).
- `lib/wotex/nx/unit_converter.ex`: the consumer unit-conversion port;
  `options.ex`: closed keyword options; `error.ex`: structured errors.
- `bin/check_archive.exs`: archive and isolated-consumer check (full gate);
  `bin/check_boundary.exs`: numerical-boundary source scan (full gate).
- Specification: `docs/packages/wotex-nx/specs/WNX.01-observation-numerical-boundary.md`
  (`catalogue.yaml` owns status). Completion plan:
  `docs/packages/wotex-nx/plans/wotex-nx-completion.md`; decisions and the
  runtime/backend cohort under `docs/packages/wotex-nx/`.
- Test support: `test/support/factory.ex` (`Wotex.Nx.TestFactory`) and
  `test/support/unit_converter.ex`. There are no fixture files.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-nx test test/wotex/nx/<file>_test.exs`, or `mix impact Wotex.Nx.Encoder encode --run` |
| 1 | `mix check.fast --package wotex-nx` |
| 2 | `mix check.affected` (full gate here, fast gate in `wotex-lab`) |

The full gate alone is `mix pkg wotex-nx check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-nx`); it adds
dependency audits, Doctor, docs, the coverage floor, Dialyzer, the boundary scan
and the archive check. Run `mix dialyzer.pkg wotex-nx` in tier 1 when a typespec
or inferred return type changed.

Tests by area, under `test/wotex/nx/` unless noted:

- Observation, feature and schema construction, identity, bounds:
  `observation_feature_schema_test.exs`.
- Window order, ties, age, units, fill masks, quality, encoded batch and
  accessors: `window_encoder_test.exs`; selection equivalence properties:
  `window_selection_property_test.exs`.
- Integer endpoints, normalization and dtype overflow, rounding:
  `numerical_integrity_test.exs`; fixed shapes: `shape_property_test.exs`.
- Decoder admission and inert output kinds: `decoder_test.exs`.
- Closed options, forged structs and the public error matrix:
  `contract_matrix_test.exs`.
- No application callback and quality codes: `library_contract_test.exs`;
  locked Decimal boundary: `dependency_security_test.exs`; doctests:
  `test/documentation_test.exs`.
- Archive contents, `mix.exs` `package` or the reference cohort: the full gate
  (archive check).

Only `wotex-lab` depends on Wotex Nx. Before changing a public function, list
its callers with `mix refs Wotex.Nx.Module fun` and the tests to run with
`mix impact Wotex.Nx.Module fun`. This package calls only the public API of
`wotex` (`Wotex.DataSchema`).

The full gate runs the boundary scan; run it alone with
`elixir bin/check_boundary.exs` from `packages/wotex-nx`. There is no native
build, software profile or container lane.