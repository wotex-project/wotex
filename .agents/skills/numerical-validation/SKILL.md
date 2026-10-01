---
name: numerical-validation
description: Change observations, feature schemas, windows, tensors, masks, batches, unit conversion or decoded numerical output. Use for shape, dtype, missingness and deterministic selection; exclude model serving and Action execution.
user-invocable: false
---

# Test numerical meaning

Input: the affected WNX requirement, feature order, units, dtype, shape,
timestamps and missing-value policy.
Output: executable value and tensor tests preserving the accepted numerical
meaning and inert output boundary.

Read the owning specification under `docs/packages/wotex-nx/specs/`.
Determine whether tensor layout, mask polarity, quality code or temporal
selection changes require a compatibility update.

Test invalid shape, dtype, non-finite values, units, quality and missingness
before tensor construction. Exercise integer endpoints, conversion, rounding
and normalization overflow when affected. A unit mismatch uses the explicit
conversion port and reports its failures.

Test deterministic feature order, window selection, age boundaries and ties.
Compare selection with the existing independent property-test model where
relevant. For lazy batches, verify masks and quality remain aligned with their
feature rows. Decoding must validate the supplied output schema and return
inert values without an execution callback.

Use the package guidance to select integrity, property, contract-matrix or
decoder tests. Report the tested dtype, shape and boundary cases; a tensor
that builds successfully does not establish semantic correctness.
