---
name: monorepo-workflow
description: Use for any code change in this repository — locating code, finding callers, choosing which tests and gates to run, and working across packages without running the whole repository.
---

# Working in the WoTEx monorepo

The repository is 16 independent Mix projects under `packages/` plus a root
tooling project. Every command below runs from the repository root. The root
project never loads package code; it runs each package's Mix in its own
process with `WOTEX_PATH_DEPS=1`.

## 1. Orient

- `mix setup` once (dependencies for root and packages, Dexter index).
- Read the root `CLAUDE.md`, then `packages/<name>/CLAUDE.md` for every package
  you touch; its "Where things are" section maps modules, specs and tests.
- Specifications: `docs/packages/<name>/specs/`; the package catalogue
  `catalogue.yaml` there owns each specification's implementation status.

## 2. Locate

- Definition: `mix def Wotex.Runtime.ConsumedThing read_property`
- Callers across all packages: `mix refs Wotex.Runtime.ConsumedThing read_property`
- Tests that cover a change: `mix impact Wotex.Runtime.ConsumedThing read_property`

Prefer these to repository-wide text search; they resolve aliases and only
report real references, grouped by package and by `lib/` or `test/`.

## 3. Change and test (tier 0)

- Run the tests next to the change: `mix pkg <name> test test/<path>_test.exs`.
- For a changed public function: `mix impact Module fun --run` runs the
  referencing tests in every package that uses it.
- `mix pkg <name> <any mix task>` reaches anything inside a package.
- For C, C++ or Rust: `mix native.lint --package <name>` checks clang-format
  on the changed lines, rustfmt and clippy; `--fix` formats. Add `--tidy` for
  clang-tidy and run `mix native.test --package <name>` when the native code
  is ready.

## 4. Package ready (tier 1)

`mix check.fast --package <name>`: compile with warnings as errors, format
check, Credo strict, the package's tests and, for a package with native code,
`mix native.lint`. If a typespec, callback or inferred return type changed,
also `mix dialyzer.pkg <name>`.

## 5. Before a commit (tier 2)

`mix check`: `mix workspace` (root compile, format, Credo, tests, catalogue,
links, boundary), then the full `mix check --no-retry` gate (coverage floor,
Dialyzer, docs, audits, archive and, for native packages, clang-tidy and the
native tests) for the packages you changed and the fast gate for their
dependents. `mix check --base REF` compares with another base.

## 6. Do not

- Run `mix check.all`, every package's gate, or Dialyzer for all packages for a
  bounded change. They are for repository-wide changes or an explicit request.
- Start native builds, software profiles, interop or containment lanes unless
  asked; they need a disposable absolute `--workspace` and external tools.
- Call a sibling package's `@moduledoc false` module or `@doc false` function;
  `mix wotex.boundary` rejects it.
- Make code read from `docs/`, add an umbrella, or add a second sibling-resolution
  mechanism besides `WOTEX_PATH_DEPS=1`.

## Report

State the commands and test files you ran, why they cover the change, and
anything skipped.
