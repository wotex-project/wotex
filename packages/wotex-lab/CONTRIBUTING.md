# Contributing

Read `CLAUDE.md`, `docs/specs/catalogue.yaml` and the owning WLB specification.
Keep one module per file, documented public types and structured errors. Use
public WoTEx APIs. Do not copy sibling internals to make a scenario pass.

Use `WOTEX_PATH_DEPS=1 mix setup` and `WOTEX_PATH_DEPS=1 mix check --no-retry`
for source work. Changes to contracts require positive, applicable negative,
lifecycle and limit evidence. Keep source/evidence/adoption statuses accurate.
An integration without an implementation belongs in an accepted specification,
not a placeholder module that reports success.

For an ecosystem seam review, run `elixir bin/check_source_cohort.exs` with all eight
WoTEx source owners present. It compares content, including dirty files, to the
reviewed workspace cohort. A mismatch requires reviewing the affected contracts
and renewing evidence, not blindly replacing hashes. `--print` only displays
current digests; it never changes the baseline. This optional workspace guard
is separate from package-local CI and is never artifact-adoption evidence.

All programme obligations have an owner and acceptance gate in the completion
contract. Keep execution notes in ignored `docs/tasks/local/`. Check package
contents before release claims. Maintainers own publication and Git remotes;
repository visibility is changed manually by the user only.
