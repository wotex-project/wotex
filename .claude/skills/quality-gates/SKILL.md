---
name: quality-gates
description: Apply before committing, handing off, or making a completion, release, or package-readiness claim for a package.
---

# Quality gates

Run the gates proportional to the change (see the `monorepo-workflow` skill and
`.claude/rules/affected-validation.md`), from the repository root:

```sh
mix check                 # mix workspace, then the full gate for changed packages
                          # and the fast gate for dependents (mix check.affected)
```

The full gate of one package is `mix pkg <name> check --no-retry`
(`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/<name>`). It covers
locked dependencies, warnings-as-errors compilation, formatting, Credo strict,
Doctor, dependency audits, ExDoc with warnings as errors, tests with the 95%
coverage floor, Dialyzer, the archive check and, where present, the boundary
scan (`bin/check_boundary.exs`) and the application-free check. A package with
C, C++ or Rust code adds `native_format` (clang-format on changed lines,
rustfmt), `native_lint` (clang-tidy, clippy) and `native_test` (its native
tests); a suite that cannot run on the host fails with a message.

For a completion or readiness claim, additionally confirm:

1. The OTP application has no callback module:
   `Application.spec(:<otp_app>, :mod)` is empty.
2. Production dependencies match the reviewed allowlist or accepted graph.
3. The packaged file list from the archive check contains only code, `priv/`,
   `README.md`, `CHANGELOG.md`, `LICENSE` and `NOTICE` and, where the
   package's shipped Mix tasks need them, its native sources and the test
   assets those tasks run; never Markdown documentation, governance files,
   agent files or check scripts (root `CLAUDE.md`, "Layout invariants").
4. Tracked text contains no consumer, company or product names, consumer
   namespaces, absolute machine paths, credentials, private data or copied
   non-public prose. Review the boundary semantically; do not encode private
   consumer names in a denylist. Sibling packages are referenced by package
   name; relative paths inside this repository are allowed.
5. `mix wotex.boundary --package <name>` reports no use of a sibling's hidden
   API.
6. Record the commit of this repository, the package path and the archive
   digest in the handoff. Report every skipped or failed check.

Stop after local evidence. Automated agents never configure or remove remotes,
push, create tags, publish packages or create releases.
