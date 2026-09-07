# Changelog

## 0.1.0

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
