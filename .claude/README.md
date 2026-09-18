# Instruction layout

The root `CLAUDE.md` is the repository-wide contract. Each
`packages/<name>/CLAUDE.md` remains that package's contract and governs work
inside the package. This directory holds the path-scoped rules and the
repeatable workflows that were consolidated from the former per-package
`.claude/` trees. Select the narrowest matching rule and skill automatically.

## Rules (`rules/`)

Every rule carries `paths:` frontmatter; a rule loads only when a matching file
is touched.

Family-wide rules apply to every package under `packages/`:

| Rule | Scope |
| --- | --- |
| `affected-validation.md` | `packages/**`, root `lib/**`, `test/**`, `tooling/**`, `mix.exs` — which tests and gates to run |
| `wot-terminology.md` | `packages/**`, `docs/packages/**` |
| `elixir-library.md` | `packages/**/lib/**/*.ex`, `packages/**/test/**/*.exs`, `packages/**/mix.exs` |
| `release-management.md` | `packages/**/CHANGELOG.md`, `mix.exs`, `README.md`, `config/config.exs` |

Package-scoped rules are stored flat as `<package>--<rule>.md` and load only
for `packages/<package>/**` (and `docs/packages/<package>/**` where the rule
covers documentation or specifications):

| Package | Rules |
| --- | --- |
| `wotex-binding-http` | `http-binding-library`, `sse-lifecycle` |
| `wotex-binding-mqtt` | `mqtt-binding-library`, `wot-mqtt-mapping` |
| `wotex-conformance` | `elixir`, `testing`, `public-boundary`, `wot` |
| `wotex-continuum` | `elixir`, `public-boundary`, `specifications` |
| `wotex-directory` | `elixir`, `testing`, `wot`, `boundaries` |
| `wotex-nx` | `numerical-boundary`, `public-library` |
| `wotex-runtime` | `runtime-library`, `wot-operations` |

The same-named `elixir`, `testing`, `wot`, and `public-boundary` rules differ
in substance between packages and are deliberately kept package-scoped rather
than merged.

## Skills (`skills/`)

Family-wide workflows, applied whenever their description matches a task in
any package:

- `monorepo-workflow` for every code change: locating code with Dexter
  (`mix def`, `mix refs`, `mix impact`), running only the tests a change
  reaches, and the tiered gates.
- `research-register` for README, guide, and API documentation prose.
- `unslop` as the final pass over persisted text.
- `spec-delivery` when implementing an accepted specification or changing
  public behavior, values, errors, compatibility, or a standards claim.
- `quality-gates` before a commit, handoff, or completion claim (proportional
  gates: `mix check.affected`, `mix workspace`).
- `release-readiness` before an archive, release candidate, tag, or public
  compatibility claim.

Package-specific workflows: `conformance-contract` (wotex-conformance),
`continuum-contracts` and `release-proof` (wotex-continuum),
`directory-contract` (wotex-directory), `http-binding-proof`
(wotex-binding-http), `mqtt-binding-proof` (wotex-binding-mqtt),
`numerical-proof` (wotex-nx), and `runtime-proof` (wotex-runtime).

## Conventions

- Specifications live in `docs/packages/<name>/specs/`; check scripts live in
  `packages/<name>/bin/`; machine-local execution state lives in the ignored
  `docs/tasks/local/<name>/`.
- Consumer, company, and product names stay out of source, docs, fixtures,
  history, and metadata. Sibling packages are referenced by package name;
  relative paths inside this repository are allowed, absolute machine paths
  are not.
- `WOTEX_PATH_DEPS=1` is the only switch that resolves sibling packages from
  `packages/`; archive builds always run with it unset.
- Automated agents never edit a `CHANGELOG.md`, invoke a release task, or
  create remote Git state.
