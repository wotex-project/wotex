# Changelog

## 0.1.0

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
