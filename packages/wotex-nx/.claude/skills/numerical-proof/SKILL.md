---
name: numerical-proof
description: Apply when changing Wotex Nx observations, feature schemas, windows, tensors, masks, batches, unit conversion, normalization, or output values.
---

# Numerical proof

1. Identify the affected WNX requirement and public types.
2. Test invalid shape, dtype, non-finite, unit, quality, and missing cases.
3. Prove deterministic ordering and tie-breaking with executable tests.
4. Verify output values remain inert and contain no execution callback.
5. Run format, warnings-as-errors compile, coverage, docs, Hex build, boundary,
   application-callback, and archive checks.
