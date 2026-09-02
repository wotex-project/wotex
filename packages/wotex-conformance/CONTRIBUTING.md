# Contributing

Contributions are welcome when they preserve the subject-independent evidence
boundary.

## Before opening a change

1. Read `CLAUDE.md` and `docs/specs/WCF.01-conformance-runner.md`.
2. For a standards claim, identify the exact public revision and section.
3. Describe what the vector proves and, equally, what it does not prove.
4. Use synthetic or redistributable fixtures and add provenance.
5. Keep consumer names, implementation details, customer material, and internal
   paths out of commits and files.

## Contract changes

A change to a claim, vector, target request/response, result status, canonical
encoding, or report schema requires:

- a specification update;
- schema and vector updates;
- positive and negative tests;
- compatibility analysis; and
- maintainer approval.

The target must never receive the expected value. New result categories cannot
be represented as diagnostic strings; they require a versioned schema change.

## Verification

Run:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

Commits use a conventional lowercase subject such as `feat: add archive digest
verification`. Do not put internal task identifiers or attribution trailers in
commit messages.
