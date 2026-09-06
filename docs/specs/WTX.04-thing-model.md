# WTX.04: Thing Model 1.1 value, parsing, and serialization

**Status**: Implemented development contract  
**Specification version**: 1.0.0

**Owner**: `wotex`  
**Requires**: WTX.01, WTX.03  
**Standard baseline**: W3C WoT Thing Description 1.1, Recommendation
5 December 2023, section 9 Thing Model

## Ownership

This package owns the consumer-neutral Elixir value boundary for a W3C Thing
Model, bounded Thing Model JSON parsing, validation, JSON-value round trips,
and deterministic package-local encoding.

It does not instantiate a Thing Model as an operational Thing Description,
resolve `tm:ref` across documents, allocate identifiers, select optional
affordances, own a model registry, persist versions, execute Forms, or decide
which model a Thing implements. A consumer owns those decisions.

## Requirements

1. `Wotex.ThingModel.parse/2` MUST accept UTF-8 `application/tm+json` bytes and
   return a validated immutable value or structured errors.
2. A production value MUST declare `tm:ThingModel` and include the TD 1.1
   context `https://www.w3.org/2022/wot/td/v1.1` as required by the pinned W3C
   schema and semantic context check.
3. `tm:optional`, `tm:ref`, `schemaDefinitions`, placeholders, and unknown
   extension members MUST retain native JSON-value semantics.
4. Parsing MUST apply explicit byte, nesting-depth, and node-count limits
   before the value enters a consumer boundary.
5. Parsing and validation MUST NOT retrieve remote contexts, schemas, models,
   or references.
6. `encode/2` with `:source` MUST return original bytes only while the value is
   unmodified and MUST fail after mutation.
7. `encode/2` with `:canonical` MUST be deterministic for equal JSON values and
   MUST NOT be described as RFC 8785 JCS.
8. Only the `application/tm+json` JSON representation is claimed.
9. The bundled informative W3C schema MUST have an immutable upstream revision,
   upstream and bundled digests, license, and modification notice.
10. Security references present in a model MUST resolve to entries in its
    `securityDefinitions` map using the same deterministic semantic rule as a
    Thing Description.

## Public operations

| Operation | Result |
|---|---|
| `parse/2` | Thing Model JSON to a validated value |
| `from_map/2` | JSON-compatible map to a validated value |
| `to_map/1` | complete preserved JSON-compatible map |
| `validate/2` | unchanged value or structured errors |
| `id/1` | optional model identifier |
| `put_id/3` | validated model with a replacement identifier |
| `encode/2` | source, compact, pretty, or deterministic canonical JSON |
| `schema_info/0` | exact standard revision and schema provenance |

## Determinism and limits

Defaults are one mebibyte, 64 nested containers, and 100,000 JSON nodes. A
consumer may lower or explicitly raise them. Validation error ordering is
deterministic for the same JSON value; errors expose stable codes, phases, and
JSON Pointer-like paths.

## Compatibility and failure behavior

Thing Models are not accepted by `Wotex.ThingDescription`, and Thing
Descriptions are not accepted by `Wotex.ThingModel`. Model instantiation is a
future, separately specified operation rather than an implicit parse side
effect. Invalid JSON, non-object roots, resource-limit failures, schema
violations, unsupported contexts, and unresolved security references use the
shared `Wotex.Error` contract.

## Evidence

- valid Thing Model 1.1 parse and source-byte return;
- deterministic encoding independent of map insertion order;
- placeholder, `tm:optional`, `tm:ref`, schema definition, and extension
  preservation;
- exact unresolved-security-reference paths;
- invalid type, context, JSON, root value, and resource limits fail safely;
- mutation invalidates source-byte encoding; and
- schema provenance exposes immutable upstream and bundled digests.

## Primary sources

- https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#thing-model
- https://github.com/w3c/wot-thing-description/tree/REC1.1
