---
name: spec-delivery
description: Apply when implementing an accepted package specification, or when a change adds or alters Wotex public behavior, values, errors, compatibility, or a standards claim.
---

# Specification delivery

Specifications live in `docs/packages/<name>/specs/` (with `catalogue.yaml` as
the normative status owner); code, vectors, and tests live in
`packages/<name>/`. Execution status stays in `docs/tasks/local/<name>/`.

1. Read the complete owning specification and its cited decision records.
   Identify the owning normative requirement and the exact standard revision.
2. State ownership and explicit non-ownership. Confirm dependency direction and
   public boundaries before adding code.
3. Define values, errors, determinism, limits, and compatibility before code.
4. Write failing tests for one coherent requirement slice. Add valid, invalid,
   boundary, and extension-preservation vectors.
5. Implement the smallest complete public contract for that slice. Implement
   only the claimed cells.
6. Run the focused tests and warning-free compilation, then the package checks,
   and record exact evidence.
7. Preserve requirement-to-test traceability in the specification evidence
   table.
8. Run the `quality-gates` skill (or `release-readiness` for an archive or
   release claim) before claiming the slice complete.
9. Reject a completion claim when implementation, docs, and vectors disagree.

Do not implement referenced optional profiles or transport ownership as a side
effect.
