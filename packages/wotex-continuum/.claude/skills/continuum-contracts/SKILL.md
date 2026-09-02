---
name: continuum-contracts
description: Apply when changing a WCT specification, continuum value, encoded form, lifecycle transition, mode, compatibility rule, or executable vector.
---

# Continuum contract workflow

1. Read the owning WCT specification completely.
2. Classify the change as compatible, additive, or incompatible.
3. Update normative text and schema before implementation.
4. Add a valid, invalid, canonical, or compatibility vector that proves the
   change from outside the module.
5. Implement with typed errors and no host authority.
6. Test encode/decode round trips, byte determinism, limits, and rejected input.
7. Run formatting, warnings-as-errors compilation, tests, docs, archive build,
   and the public-boundary scan.
