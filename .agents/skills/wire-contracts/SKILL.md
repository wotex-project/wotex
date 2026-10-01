---
name: wire-contracts
description: Change Continuum wire values, schemas, canonical encoding, compatibility or lifecycle transitions. Use for schema-vector-code agreement and deterministic bytes; exclude transport execution and archive-only validation.
user-invocable: false
---

# Validate wire agreement

Input: the affected WCT requirement, value or transition and compatibility
classification.
Output: matching schema, vectors, constructors and tests, with the wire version
and compatibility decision explicit.

Read the owning specification in `docs/packages/wotex-continuum/specs/`.
Classify the change as compatible, additive or incompatible using its accepted
compatibility rules; package version and wire version remain independent.

Update the owning normative text and schema when the obligation changes.
Add vectors under `packages/wotex-continuum/priv/vectors/` for valid,
invalid, canonical and compatibility behavior as applicable. Invalid vectors
name the expected error code and JSON Pointer path.

Exercise schema-constructor-codec agreement through public values, including
forged structs, nested values, defaults, limits and rejected input. Test
encode/decode round trips and canonical bytes from equivalent values with
different key insertion order. Lifecycle changes need accepted and rejected
transition cases.

Keep host authority out of constructors and exchange values. Run the focused
schema, vector, codec or lifecycle tests identified by package guidance.
Select `archive-validation` only when the task includes artifact compatibility.
