---
name: monorepo-workflow
description: Select focused tests and package gates for code changes using the package graph and Dexter. Use for implementation and validation, including tooling changes; exclude prose-only edits.
user-invocable: false
---

# Validate affected code

Input: the changed mechanism, modules or callbacks, paths and comparison base.
Output: executed checks covering that reach, with failures and omissions reported
in chat.

Read the affected package's `AGENTS.md` for its source map and test areas.
Use `mix def Module [fun]` and `mix refs Module [fun]` to locate definitions
and actual callers. `mix impact Module [fun]` identifies direct and one-hop
referencing package tests; it does not cover root tooling tests or every
indirect behavior. Add tests for the changed behavior when the reference list
does not cover it.

Run focused package tests with `mix pkg <name> test <files>`, or
`mix impact Module [fun] --run` when its selected files cover the change.
Root tooling tests run with `mix test test/wotex/workspace/<file>_test.exs`.

Inspect `mix affected --base REF --detail` before choosing wider checks.
Use `mix check.fast --package <name>` for ready package code and
`mix dialyzer.pkg <name>` for changed types, callbacks or inferred returns.
Then use the pre-commit gate in `AGENTS.md`. Its selection includes staged
and unstaged paths, not just commits; review it before running.

A package gate can fetch dependencies, build native code and run host checks.
When the task excludes those operations, use existing focused tools instead
and report the full gate as unrun. Read `tooling/packages.yaml` or
`mix help wotex.<task>` only for the task or lane being selected. Report
the base, commands and actual results; passing caller tests alone does not
establish an entire specification's completion.
