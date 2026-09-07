# Changelog

## 0.1.0

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
