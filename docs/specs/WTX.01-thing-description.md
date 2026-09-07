# WTX.01: Thing Description 1.1 value, parsing, and serialization

**Status**: Implemented development contract  
**Specification version**: 1.1.0

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
2. The production `@context` MUST be `https://www.w3.org/2022/wot/td/v1.1`,
   or an array whose first element is that URI, or an array whose first two
   elements are `https://www.w3.org/2019/wot/td/v1` followed by that URI, as
   TD 1.1 section 5.3.1.1 requires. Any other position or the legacy context
   alone fails with `unsupported_context`. A document whose `@type` includes
   `tm:ThingModel` fails with `thing_model_not_accepted`.
3. Parsing MUST apply explicit byte, nesting-depth, node-count, string-size,
   and collection-size limits before the value enters a consumer boundary.
   Depth and string size MUST be bounded by a lexical scan before the decoder
   allocates, decoded strings MUST NOT retain the source binary, and duplicate
   object members MUST fail with `duplicate_member`.
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
10. Every Thing-level, Form-level, and `ComboSecurityScheme` security reference
    MUST name an entry in the Thing Description's `securityDefinitions` map.
    Undefined names fail with `undefined_security_reference` at the exact JSON
    Pointer-like reference path.

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

Limit options are `:max_bytes`, `:max_depth`, `:max_nodes`,
`:max_string_bytes`, and `:max_collection_size`, with defaults of one
mebibyte, 64 nested containers, 100,000 JSON nodes, 256 KiB per string, and
10,000 members per container. A consumer may lower or explicitly raise these
limits; a non-positive or non-integer limit fails with `invalid_limit`. For a
native map, `:max_bytes` bounds the total string and key payload. Errors
identify the phase, stable code, JSON path, and safe details.

The documented `validate: false` staged-ingestion option bypasses the aggregate
schema and semantic pass, not JSON-value or resource-limit admission. Such a
value MUST NOT be presented as successfully validated against TD 1.1 until
`validate/2` succeeds. API and release acceptance are separate gates in
the package completion contract, `docs/plans/wotex-completion.md`.

## Evidence

- valid TD 1.1 parse and source-byte return;
- equal maps with different insertion order produce equal canonical bytes;
- extension terms survive parse/map/encode;
- Thing-level, Form-level, and `ComboSecurityScheme` names cannot reference an
  undefined security scheme;
- legacy context, misplaced context, Thing Model type, malformed JSON,
  duplicate members, non-object roots, excessive bytes, depth, nodes, strings,
  and collections, and invalid limit options fail with typed codes;
- hostile nesting is rejected before decoding with bounded work;
- a mutation invalidates source-byte encoding; and
- bundled schema bytes match the recorded SHA-256 digest.

## Primary sources

- https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/
- https://github.com/w3c/wot-thing-description/tree/REC1.1
