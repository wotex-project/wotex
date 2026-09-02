---
name: quality-gates
description: Apply before a completion, release, or package-readiness claim.
---

# Quality gates

Run fresh checks against the final tree:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=docs mix docs
mix package
git diff --check
```

When testing against a sibling checkout, set `WOTEX_PATH_DEPS=1` explicitly
for format, compile, test, and documentation commands. Do not set it for
production dependency inspection. The `mix package` alias always removes the
switch before building package metadata.

Also confirm that the OTP application has no callback module, no remote is
configured by the agent, production dependencies match the accepted graph, and
the repository contains no consumer names, internal paths, credentials, or
private data. Report every skipped or failed check.
