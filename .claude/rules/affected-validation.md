---
paths:
  - "packages/**"
  - "lib/**"
  - "test/**"
  - "tooling/**"
  - "mix.exs"
---

# Proportional validation

Validation matches the reach of the change. Find the reach first, then run
only what covers it.

1. Before changing a public function or module, list its callers with
   `mix refs Module fun` (Dexter, all packages). `mix impact Module fun`
   turns that into the test files to run; `--run` runs them.
2. While editing, run only the tests that exercise the change:
   `mix pkg <package> test <files>` or `mix impact Module fun --run`.
3. When one package's change is ready: `mix check.fast --package <package>`
   (compile with warnings as errors, format, Credo strict, tests).
4. Before a commit: `mix check.affected` — the full gate for changed packages,
   the fast gate for their dependents.

Run Dialyzer (`mix dialyzer.pkg <package>`) when a typespec, a callback or an
inferred return type changed; otherwise the pre-commit gate runs it for changed
packages only. Never run Dialyzer or the full gate across all packages for a
bounded change.

`mix check.all` and every package's full gate are for repository-wide changes
only: the root toolchain, `tooling/`, root `mix.exs`, CI, a change to `wotex`
or `wotex-runtime` that alters a public signature, or an explicit request.
Native builds, software profiles, interop suites and containment lanes run only
when invoked explicitly with a disposable absolute `--workspace`.

Report the exact commands and test files you ran and why they cover the change.
Dexter is navigation, not type checking; it never replaces Dialyzer or tests.
