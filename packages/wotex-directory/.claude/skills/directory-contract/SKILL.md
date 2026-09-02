---
name: directory-contract
description: Apply when changing Thing Description Directory values, operations, ports, expiry, pagination, or Introduction behavior.
---

# Thing Description Directory contract

- Read `docs/specs/WTD.01-directory-contract.md` completely.
- Keep Thing Description parsing, validation, identity, and serialization in
  the `wotex` core facade.
- Keep Discovery registration information separate from consumer persistence
  schemas.
- Authorize before repository access. An authorization denial must not reveal
  whether an entry exists.
- Treat register, replace, patch, delete, and expiry as optimistic-concurrency
  operations with explicit version conflicts.
- Apply JSON Merge Patch before core validation; never persist an invalid result.
- Use the injected clock for all registration timestamps and expiry decisions.
- Listing is bounded, sorted by Thing Description identifier in Unicode code
  point order, and tied to a collection revision.
- Introduction returns only the directory's own Thing Description and never
  reads entries.
- Search profiles remain explicit unsupported outcomes until their own contract
  is accepted.
