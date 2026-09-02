# Threat model

## Assets

- integrity of encoded continuum values and canonical bytes;
- stable Thing references delegated to validated Thing Descriptions;
- bounded memory and CPU use while decoding untrusted JSON; and
- clear separation between a proposal and consumer-host authority.

## Trust boundaries

JSON input, extension values, evidence URIs, timestamps, artifact digests, and
opaque identity references are untrusted. A syntactically valid value is not
authenticated, authorized, current, or true.

## Controls

- byte, nesting, collection, and string limits;
- duplicate-member and atom/string-collision rejection;
- no dynamic atom or module creation from input;
- finite JSON values and absolute-IRI checks;
- deterministic canonical encoding;
- exact lifecycle and status invariants;
- no runtime process, I/O, ambient configuration, or mutable global state; and
- Thing Description validation through the Wotex core.

## Consumer-host obligations

The consumer host authenticates principals and artifacts, authorizes Actions,
protects idempotency state, verifies evidence and artifact digests, applies
clock-trust policy, bounds persistence and queues, selects transport, and
records canonical effects. It treats observation and Action values as input to
those decisions, not as their result.
