# Agent Instructions

Read and follow the root `CLAUDE.md` before any work, then the
`packages/<name>/CLAUDE.md` of every package you touch. Apply matching rules
under `.claude/rules/` and matching skills under `.claude/skills/`
automatically.

The checked-in contracts are authoritative. Keep machine-local memories,
progress notes and consumer-specific details out of tracked files; the only
place for them is the ignored `docs/tasks/local/<name>/`.

Run the gate of the package you changed and of its dependents, from inside
each package directory. Do not run every package's gate for a one-package
change.

Commit rules: GitOps/conventional prefix and a natural sentence; no
specification or work-package identifiers; the contributor's configured
identity; no agent, tool or bot as author, committer or co-author; no
"Generated with" attribution. Never add or change remotes, push, tag, publish
or change visibility.
