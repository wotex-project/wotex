# WTX.03: Errors, extension preservation, and compatibility

**Status**: Implemented development contract  
**Owner**: `wotex`  
**Requires**: WTX.01, WTX.02

## Error contract

Every public failure returns `{:error, %Wotex.Error{}}` or a non-empty list of
those errors. Stable fields are:

- `code`: package-defined atom suitable for matching;
- `phase`: parse, value, schema, semantic, or encode;
- `path`: JSON Pointer-like path rooted at `/`;
- `message`: safe human-readable explanation; and
- `details`: bounded machine-readable context without credentials or source
  document copies.

Raising variants use the same exception value. Error messages are not a stable
matching interface.

`undefined_security_reference` is a semantic error. Its path identifies the
offending Thing-level, Form-level, or `ComboSecurityScheme` member, and its safe
details contain only the unresolved definition name.

## Extension contract

Unknown JSON members MUST be preserved without interpretation. Extension terms
do not become supported standard behavior merely because they survive a round
trip. A consumer may validate its own extension vocabulary after core
validation, without modifying Wotex or presenting that policy as W3C behavior.

## Compatibility contract

- Development versions make no stable API promise.
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
invalidation after mutation, and absence of an application callback. Archive
inspection and the public-source scan are release gates.
