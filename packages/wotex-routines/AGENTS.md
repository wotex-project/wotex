# Wotex Routines package guidance

Wotex Routines (`packages/wotex-routines`, Hex `wotex_routines`) owns closed installed behaviour, exact unit conversion, observation values and
the optional bounded pure routine kernel/host contracts. The consumer owns
canonical facts, device qualification, clocks, credentials, policy, persistence
and effects.
It uses `wotex` and `wotex-continuum` only through their public, documented API.
Repository-wide rules are in the root `AGENTS.md`.

## Invariants

- Loading the package starts no process and performs no runtime filesystem
  access; there is no application callback. Long-lived work is returned to
  the consumer as caller-configured child specifications.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  framework integration or automatic network activity.

## Where things are

- `lib/wotex/routines.ex`: the entry point, `Wotex.Routines`.
- `bin/check_archive.exs`: archive contents check;
  `bin/check_application_free.exs`: no application callback;
  `bin/check_boundary.exs`: consumer-neutral source scan (all in the full
  gate).
- Specifications: `docs/packages/wotex-routines/specs/` (`catalogue.yaml` owns
  status). Completion plan:
  `docs/packages/wotex-routines/plans/wotex-routines-completion.md`; provenance in
  `docs/packages/wotex-routines/provenance/`.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-routines test test/wotex/routines/basis_test.exs`, or `mix impact Wotex.Routines.Basis new --run` |
| 1 | `mix check.fast --package wotex-routines` |
| 2 | `mix check` (full gate here, fast gate in dependents) |

The full gate alone is `mix pkg wotex-routines check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-routines`); it
adds dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the
boundary scan, the archive check and the application-free check. Run
`mix dialyzer.pkg wotex-routines` in tier 1 when a typespec or inferred return
type changed.

Before changing a public function, list its callers with
`mix refs Wotex.Routines fun` and the tests to run with
`mix impact Wotex.Routines fun`. This package has no native build, software
profile or container lane.
