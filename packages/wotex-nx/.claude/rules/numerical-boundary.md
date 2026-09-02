---
paths:
  - "lib/**/*.ex"
  - "test/**/*.{ex,exs}"
---

# Numerical boundary

- Validate shape, dtype, finite values, units, quality, and missing semantics
  before constructing a tensor.
- Preserve deterministic feature order from the accepted schema.
- Return structured errors; never silently coerce missing or invalid input.
- Use an explicit unit-conversion port when units differ.
- Never issue an Action or interpret numerical output as authorization.
