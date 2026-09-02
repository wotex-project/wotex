---
name: spec-delivery
description: Apply when implementing an accepted repository specification.
---

# Specification delivery

1. Read the complete owning specification and its cited decision records.
2. Confirm dependency direction and public boundaries before adding code.
3. Write failing tests for one coherent requirement slice.
4. Implement the smallest complete public contract for that slice.
5. Run the focused tests and warning-free compilation.
6. Preserve requirement-to-test traceability in the specification evidence
   table.
7. Run the quality-gates skill before claiming the slice complete.

Do not implement referenced optional profiles or transport ownership as a side
effect.
