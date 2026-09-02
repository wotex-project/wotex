# Contributing

Contributions are welcome through public issues and pull requests.

## Contract-first changes

A change to a public value or encoded form must update, in the same commit:

1. the owning WCT specification;
2. valid, invalid, canonical, or compatibility vectors;
3. implementation and tests;
4. security and compatibility notes when affected; and
5. the schema version when the wire contract is incompatible.

Distinguish W3C-defined terminology from project-defined continuum fields.
Every standards claim must cite an exact dated document and section. Do not
describe project fields as W3C fields.

## Quality gate

Run all commands listed under Verification in `README.md`. Public modules need
documentation and typed specifications. Keep modules small, deterministic, and
free of ambient configuration or mutable global state.

## Commit messages

Use lowercase conventional commit subjects, for example:

```text
feat: add delivery receipt validation
```

Do not include generated attribution or issue/spec identifiers in the subject.

## Developer certificate of origin

By contributing, you certify that you have the right to submit the work under
the Apache-2.0 license. Sign commits with `git commit -s` when project policy
requires it.
