# Agent instructions

Read the root `CLAUDE.md` before any work, then the `packages/<name>/CLAUDE.md`
of every package you touch. Apply matching rules under `.claude/rules/` and
matching skills under `.claude/skills/`; the `monorepo-workflow` skill is the
working loop for every code change.

Work from the repository root:

- `mix setup` once.
- Locate with `mix def Module [fun]` and `mix refs Module [fun]` (Dexter),
  not repository-wide text search.
- Test what the change reaches: `mix pkg <name> test <files>` or
  `mix impact Module [fun] --run`.
- `mix check.fast --package <name>` when a package is ready, `mix check`
  before a commit. For C, C++ or Rust changes, `mix native.lint --package
  <name>` (`--fix` formats) while editing; the package gate adds clang-tidy
  and the native tests.
- Never run every package's gate or Dialyzer across packages for a bounded
  change, and never start native or interop lanes unless asked.

Keep machine-local notes and consumer-specific details out of tracked files;
the only place for them is the ignored `docs/tasks/local/<name>/`.

Commits use a GitOps/conventional prefix and a natural sentence, without
specification or work-package identifiers, with the contributor's configured
identity; no agent, tool or bot as author, committer or co-author and no
"Generated with" attribution. Never add or change remotes, push, tag, publish
or change visibility.
