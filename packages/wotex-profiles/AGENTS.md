# Wotex Profiles package guidance

Wotex Profiles (`packages/wotex-profiles`, Hex `wotex_profiles`) owns bounded external profile/definition reading, exact mechanical interpretation
and authoring contracts. Consumers own profile data, installed bindings, identity,
trust, physical qualification, persistence and effects.
It uses `wotex` and `wotex-runtime` only through their public, documented API.
Repository-wide rules are in the root `AGENTS.md`.

## Invariants

- Loading the package starts no process and performs no runtime filesystem
  access; there is no application callback. Long-lived work is returned to
  the consumer as caller-configured child specifications.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  framework integration or automatic network activity.

## Where things are

- `lib/wotex/profiles.ex`: the entry point, `Wotex.Profiles`.
- `bin/check_archive.exs`: archive contents check;
  `bin/check_application_free.exs`: no application callback;
  `bin/check_boundary.exs`: consumer-neutral source scan (all in the full
  gate).
- Specifications: `docs/packages/wotex-profiles/specs/` (`catalogue.yaml` owns
  status). Completion plan:
  `docs/packages/wotex-profiles/plans/wotex-profiles-completion.md`; provenance in
  `docs/packages/wotex-profiles/provenance/`.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-profiles test test/wotex/profiles_test.exs`, or `mix impact Wotex.Profiles version --run` |
| 1 | `mix check.fast --package wotex-profiles` |
| 2 | `mix check` (full gate here, fast gate in dependents) |

The full gate alone is `mix pkg wotex-profiles check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-profiles`); it
adds dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the
boundary scan, the archive check and the application-free check. Run
`mix dialyzer.pkg wotex-profiles` in tier 1 when a typespec or inferred return
type changed.

Before changing a public function, list its callers with
`mix refs Wotex.Profiles fun` and the tests to run with
`mix impact Wotex.Profiles fun`. This package has no native build, software
profile or container lane.
