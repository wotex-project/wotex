# Changelog

## 0.1.0

- Measure JSON iodata against `max_bytes` before allocating its flattened
  binary; direct native constructors retain their documented depth-only
  resource envelope.

- Remove the stale `EEF-CVE-2026-32686` Hex advisory suppression now that the
  registry audit reports no matching advisory. Exact Decimal 3.1.1 lock,
  loaded-version and bounded-parser regression checks remain active.

- Validate every canonical and valid vector against the embedded normative JSON
  Schemas with a dependency-free subset checker, and record which invalid
  vectors express rules JSON Schema cannot state. Add a canonical vector for
  every registered kind and move the mode vectors to the `wct-03-` prefix that
  owns the kind.

- Wire schema 2.0.0, incompatible with wire 1.0.0. Rename the
  `execution_context` kind to `execution_scope` and the module to
  `WotexContinuum.ExecutionScope`, ending the basename collision with the
  in-memory `Wotex.Runtime.ExecutionContext`; members that reference a scope
  keep the name `context`. State the `changed_at` ordering rule enforced by
  `WotexContinuum.Lifecycle` in WCT.03, define the project term *continuum* in
  the README and WCT.01, and add a WCT.02 wire mapping to
  `Wotex.Nx.Observation`, `Wotex.Nx.ActionProposal` and `Wotex.Runtime.Result`.

- Delegate JSON source admission to `Wotex.JSON.decode/2` and remove the local
  byte scan. `WotexContinuum.Limits` keeps the family option names
  `max_bytes`, `max_depth`, `max_nodes`, `max_string_bytes` and
  `max_collection_size`, adds the node bound, and applies one `max_depth` of 32
  to decoded source and native JSON values. Core admission codes are translated
  into the continuum vocabulary documented in WCT.01.

- Adopt the Wotex family error shape: `WotexContinuum.Error` carries `code`,
  `phase`, `message`, structured `details`, and an RFC 6901 JSON Pointer `path`
  rooted at `/` instead of a path-segment list. `path` is `nil` when no wire
  location applies.

- Document `from_map/1` as the constructor for map-shaped wire input on every
  value module and keep `new/1` as its alias; `new/1` carries keyword
  configuration only in `WotexContinuum.Limits`.

- Reject invalid UTF-8 native object keys at safe parent paths, including
  nested extensions and failure details; avoid eager indexed list copies.

- Initial continuum value, codec, lifecycle, and vector contract.
