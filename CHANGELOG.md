# Changelog

## 0.1.0

- Completion baseline 1.1.0 now matches the existing WTX.03 invalid-limit and
  lexical-preflight contract. All independent-consumer and resource evidence
  obligations remain required; this documentation correction changes no values.

- Remove the stale `EEF-CVE-2026-32686` Hex advisory suppression now that the
  registry audit reports no matching advisory. Exact Decimal 3.1.1 lock,
  loaded-version and bounded-parser regression checks remain active.

- Apply TD 1.1 default Form operations per interaction context and expose
  affordance `forms/1` and `operations/2` helpers.
- Enforce TD 1.1 `@context` position rules and reject a Thing Model as a
  Thing Description with `thing_model_not_accepted`.
- Add `Wotex.JSON.decode/2`: lexical depth and string bounds before decoding,
  copied strings, duplicate-member rejection, collection limits, and
  `Wotex.JSON.Limits` with `invalid_limit` instead of silent defaults.
- Resolve `tm:optional` and local `tm:ref` pointers in Thing Models.
- Report a missing required member at its own pointer, one violation per
  member.
- Preserve TD/TM schema error field paths and short-circuit native array
  validation before copying over-budget input.

- Add bounded W3C WoT Thing Description 1.1 parsing and validation.
- Preserve extension members through immutable typed values.
- Add compact, pretty, source-preserving, and deterministic canonical encoding.
- Publish structured errors with stable codes, phases, and JSON Pointer paths.
