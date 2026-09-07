# Changelog

## 0.1.0

- Establish versioned claims, immutable vectors, and verified corpora.
- Provide an isolated external-target protocol and bounded archive verification.
- Emit deterministic result and evidence-report digests.
- Adopt the family error shape: `code`, `phase`, JSON Pointer `path`, `message`,
  and bounded `details`.
- Adopt the family limit vocabulary `max_bytes`, `max_depth`, `max_nodes`,
  `max_string_bytes`, and `max_collection_size`; invalid limits are rejected
  with `invalid_limit` instead of defaulted.
- Build map-shaped contract values with `from_map/1`, keeping `new/1` as a
  documented alias.
