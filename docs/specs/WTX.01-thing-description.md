# WTX.01: Thing Description 1.1 value, parsing, and serialization

**Status**: Implemented development contract  
**Owner**: `wotex`  
**Standard baseline**: W3C WoT Thing Description 1.1, Recommendation
5 December 2023

## Ownership

This package owns the consumer-neutral Elixir value boundary for a W3C Thing
Description, bounded TD JSON parsing, validation, JSON-value round trips, and a
deterministic package-local encoding.

It does not own a Thing's physical state, identifier allocation, persistence,
authorization, endpoint selection, credentials, transport execution, directory
registration, or Action-effect truth. A consumer resolves those inputs.

## Requirements

1. `Wotex.ThingDescription.parse/2` MUST accept UTF-8 TD JSON and return a
   validated immutable value or a structured error.
2. The production context MUST include
   `https://www.w3.org/2022/wot/td/v1.1`. The legacy context is not accepted as
   a TD 1.1 production claim.
3. Parsing MUST apply explicit byte, nesting-depth, and node-count limits before
   the value enters a consumer boundary.
4. Parsing and validation MUST NOT fetch a remote JSON-LD context, schema, or
   vocabulary.
5. `from_map/2` and `to_map/1` MUST preserve every JSON-compatible member,
   including unknown extension terms, at JSON-value semantics.
6. `encode/2` with `:source` MUST return the original bytes only while the value
   is unmodified. It MUST fail explicitly after a mutation.
7. `encode/2` with `:canonical` MUST sort object keys recursively, omit no
   values, and return byte-identical output for equal JSON values. This is a
   Wotex deterministic encoding and MUST NOT be described as RFC 8785 JCS.
8. Only `application/td+json` is a supported serialization claim. Turtle and
   RDF/XML are absent from the API.
9. The bundled schema MUST have an immutable upstream revision, digest, license,
   and modification notice.

## Public operations

| Operation | Result |
|---|---|
| `parse/2` | TD JSON to validated Thing Description |
| `from_map/2` | JSON-compatible map to validated Thing Description |
| `to_map/1` | preserved JSON-compatible map |
| `validate/2` | unchanged value or structured errors |
| `id/1` | current optional TD identifier |
| `put_id/3` | validated value with a new identifier |
| `encode/2` | source, compact, pretty, or deterministic canonical TD JSON |
| `schema_info/0` | exact bundled schema identity and digest |

## Determinism and limits

Defaults are one mebibyte, 64 nested containers, and 100,000 JSON nodes. A
consumer may lower or explicitly raise these limits. Errors identify the phase,
stable code, JSON path, and safe details.

## Evidence

- valid TD 1.1 parse and source-byte return;
- equal maps with different insertion order produce equal canonical bytes;
- extension terms survive parse/map/encode;
- legacy context, malformed JSON, non-object roots, excessive bytes, depth, and
  nodes fail with typed codes;
- a mutation invalidates source-byte encoding; and
- bundled schema bytes match the recorded SHA-256 digest.

## Primary sources

- https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/
- https://github.com/w3c/wot-thing-description/tree/REC1.1
