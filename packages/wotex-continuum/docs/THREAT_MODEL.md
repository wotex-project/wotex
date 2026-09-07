# Threat model

## Assets

- integrity of encoded continuum values and canonical bytes;
- stable Thing references delegated to validated Thing Descriptions;
- bounded work while admitting untrusted JSON, within the stated limits; and
- clear separation between a proposal and consumer-host authority.

## Trust boundaries

JSON input, extension values, evidence URIs, timestamps, artifact digests, and
opaque identity references are untrusted. A syntactically valid value is not
authenticated, authorized, current, or true.

## Controls

- explicit byte, depth, node, collection, and string limits applied by the
  Wotex core admission pipeline: byte size and UTF-8 validity first, a lexical
  depth and string-size scan over the source binary before allocation-heavy
  decoding, then duplicate-member, collection-size, node-count, and depth
  checks on the decoded value;
- one depth bound shared by decoded source and native JSON values, measured for
  a native value from the value handed to the constructor;
- duplicate-member and atom/string-collision rejection;
- no dynamic atom or module creation from input;
- finite JSON values and absolute-IRI checks;
- deterministic canonical encoding;
- exact lifecycle and status invariants;
- no runtime process, I/O, ambient configuration, or mutable global state; and
- Thing Description validation through the Wotex core.

## Bounds this library does not claim

Iodata is flattened into one binary before the byte check, so the flattened
copy is not itself bounded by `max_bytes`; a consumer that accepts untrusted
iodata bounds it before calling the codec. Byte, node, collection, and string
limits apply to source admission; a native map handed straight to a constructor
is bounded by depth, UTF-8 validity, and the finite-number rule only. No limit
bounds consumer memory after an accepted value is returned.

## Consumer-host obligations

The consumer host authenticates principals and artifacts, authorizes Actions,
protects idempotency state, verifies evidence and artifact digests, applies
clock-trust policy, bounds persistence and queues, selects transport, and
records canonical effects. It treats observation and Action values as input to
those decisions, not as their result.
