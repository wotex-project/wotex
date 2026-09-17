# Decision: retain observation digests instead of raw observations

## Status

Accepted.

## Context

Raw target values may contain large payloads, endpoint details, identifiers, or
other material that should not enter a portable evidence artifact. Omitting the
observation entirely would make result reproduction difficult.

## Decision

The runner canonicalizes the observation, compares its digest with the
runner-owned expected digest, and stores only the actual digest in the result.
Target diagnostics are stable bounded codes; free-form text is rejected.

The report digest covers the complete report except its own digest field.
Canonical JSON sorts object keys by UTF-8 bytes and preserves array order.

## Consequences

- Reports are bounded and safer to distribute.
- A reviewer with the corpus and target observation can independently reproduce
  equality.
- Reports do not provide a human-readable payload diff. Debug artifacts require
  a separate consumer-controlled channel with its own retention policy.
- Canonicalization is a compatibility boundary and must be versioned when its
  byte representation changes.
