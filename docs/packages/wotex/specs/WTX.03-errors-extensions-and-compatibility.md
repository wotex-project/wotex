# WTX.03: Errors, extension preservation, and compatibility

**Status**: Implemented development contract  
**Specification version**: 1.2.0

**Owner**: `wotex`  
**Requires**: WTX.01, WTX.02

## Error contract

Every public failure returns `{:error, %Wotex.Error{}}` or a non-empty list of
those errors. Stable fields are:

- `code`: package-defined atom suitable for matching;
- `phase`: parse, value, schema, semantic, or encode;
- `path`: JSON Pointer-like path rooted at `/`;
- `message`: safe human-readable explanation; and
- `details`: bounded machine-readable context specific to the error code. Some
  codes include a bounded representation of caller-supplied malformed data, so
  this field is not universally safe to log.

Raising variants use the same exception value. Error messages are not a stable
matching interface. `Wotex.Error.new/5` is the public constructor of this
value; sibling packages use it to report a failure at the `wotex` boundary or
to translate one into their own error module.

This five-field shape (`code`, `phase`, `path`, `message`, `details`) is the
WoTEx family error convention. Sibling packages define their own error module
with the same fields so a consumer can match errors from any package
uniformly; transport packages may add a retry `class`.

Schema violations MUST preserve the validator's field location rather than
collapse formatted errors to the root. A missing required member is one
`schema_violation` at the member's own pointer (for example `/title`) with
`details.assertion` `"required"` and `details.missing` naming the member, so
consumers and conformance vectors see the member rather than its parent. Native-array node-limit admission MUST
stop at the first over-budget node without materializing an indexed copy of
the remaining array. These are compatible corrections to the existing path and
resource-bound contracts; they do not change accepted TD/TM values.

Option-bearing admission, validation, and mutation operations use the documented
keyword-list shape. A non-list, improper-list, or non-keyword container MUST
fail with `invalid_options` in the `value` phase. The limit vocabulary is
`:max_bytes`, `:max_depth`, `:max_nodes`, `:max_string_bytes`, and
`:max_collection_size`, owned by `Wotex.JSON.Limits`. A limit MUST be a
positive integer; any other value fails with `invalid_limit` in the `value`
phase rather than silently replacing the default, so a consumer never believes
a limit applies when it does not. Non-fallible typed accessors still require
their documented typed inputs and keyword options.

`Wotex.JSON.decode/2` is the bounded admission pipeline for source bytes:
byte size and UTF-8 validity first, then a lexical depth and string-size scan
before allocation, then decoding with copied strings, then duplicate-member,
collection-size, node-count, and depth checks on the decoded value. Typed
codes are `byte_limit_exceeded`, `depth_limit_exceeded`,
`string_limit_exceeded`, `collection_limit_exceeded`, `node_limit_exceeded`,
`duplicate_member`, `invalid_string`, `invalid_json`, and `invalid_limit`.
`Wotex.JSON.validate/2` applies the structural subset to native values.
Duplicate object members can be detected only in source JSON. Native maps have
already collapsed or refused duplicates before Wotex receives them and cannot
provide duplicate-member evidence.

`undefined_security_reference` is a semantic error. Its path identifies the
offending Thing-level, Form-level, or `ComboSecurityScheme` member, and its
details contain only the unresolved definition name.

`invalid_limit`, `non_string_key`, `unsupported_encoding`, `encode_failed`,
and `unresolved_model_reference` details may contain a bounded inspected prefix
of caller-supplied data. `invalid_json` may contain the decoder's bounded
position diagnostic. Schema errors identify the assertion and path without
copying the rejected value. Consumers MUST treat all details as untrusted and
review them before logging; Wotex does not claim credential redaction.

## Extension contract

Unknown JSON members MUST be preserved without interpretation. Extension terms
do not become supported standard behavior merely because they survive a round
trip. A consumer may validate its own extension vocabulary after core
validation, without modifying Wotex or presenting that policy as W3C behavior.

Native-map constructors MUST reject invalid UTF-8 in string values and object
keys, including extensions, before schema validation or encoding. They return
`invalid_string` in the `value` phase. An invalid key reports its containing
object's path so the error itself remains valid Unicode. Valid Unicode is
preserved byte for byte without normalization. This implements the Unicode
string boundary of [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259), Sections
7 and 8.1.

Constructors reject an Elixir struct supplied where a native JSON map is
required. Typed accessors retain their documented typed-input precondition and
do not perform admission again.

## Compatibility contract

- Development versions make no stable API promise. Replacing silent limit
  defaults with `invalid_limit`, returning `invalid_options` for malformed
  option containers, enforcing context order, and rejecting duplicate members
  are admission corrections made before any release. The malformed-option
  correction changes only a previously excluded input surface from a runtime
  exception to a tagged error.
- A stable patch release may fix validation defects without removing accepted
  TD 1.1 values.
- A stable minor release may add functions, value modules, or optional fields.
- A stable major release is required to remove public functions or change
  successful result shapes.
- Standards support is versioned independently from package API compatibility
  and always names the exact W3C revision.
- Thing Description 2.0 draft fixtures are watch evidence only and cannot alter
  TD 1.1 behavior without a new admitted contract.

## Runtime contract

The package has no application callback. Loading it starts no process, creates
no table or registry, reads no application environment, and performs no network
or runtime filesystem access. All limits and behavior-changing options arrive
through function arguments.

## Evidence

Tests prove typed codes, stable paths, extension preservation, source-byte
invalidation after mutation, malformed-option and non-JSON struct refusal,
bounded diagnostic representations, configured resource-limit refusal, and
absence of an application callback. Archive inspection and the public-source
scan are release gates.
