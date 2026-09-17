---
name: quality-gates
description: Apply before committing, handing off, or making a completion, release, or package-readiness claim for a package.
---

# Quality gates

Run fresh checks against the final tree, from inside `packages/<name>/`, using
a clean build directory:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs                      # MIX_ENV=docs mix docs where the package defines a docs environment
mix package                   # where the package defines the alias; otherwise mix hex.build
git diff --check
```

The package gate `WOTEX_PATH_DEPS=1 mix check --no-retry` (`ex_check`) covers
the same checks; run it, then run the gate of every package that depends on
the changed one.

When testing against sibling packages under `packages/`, set
`WOTEX_PATH_DEPS=1` explicitly for format, compile, test, and documentation
commands. Do not set it for production dependency inspection or the archive
build. Where the `mix package` alias exists it removes the switch before
building package metadata; otherwise unset it yourself before `mix hex.build`.

Then confirm:

1. The OTP application has no callback module:
   `Application.spec(:<otp_app>, :mod)` is empty (for example
   `:wotex_conformance`, `:wotex_directory`).
2. Production dependencies match the reviewed allowlist or accepted graph.
3. The packaged file list from `mix hex.build` contains only code, `priv/`,
   `README.md`, `CHANGELOG.md`, `LICENSE`, and `NOTICE`.
4. Tracked text contains no consumer, company, or product names, consumer
   namespaces, absolute machine paths, organization-internal paths,
   credentials, private data, or copied non-public prose. Review the public
   boundary semantically; do not encode private consumer names in a denylist.
   Sibling packages are referenced by package name; relative paths inside this
   repository are allowed.
5. Record the exact commit of this repository, the package path, and the
   archive digest in the handoff. Report every skipped or failed check.

Stop after local evidence. Automated agents never configure or remove remotes,
push, create tags, publish packages, or create releases.
