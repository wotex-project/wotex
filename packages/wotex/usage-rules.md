# Wotex usage rules

These rules describe the completed contract defined by WTX.01–WTX.04. The
package catalogue records implementation status separately.

- Admit Thing Descriptions and Thing Models through
  `Wotex.ThingDescription.parse/2`, `Wotex.ThingDescription.from_map/2` and the
  corresponding `Wotex.ThingModel` functions with explicit limits. Use
  documented constructors and accessors instead of depending on struct fields.
- Validate the aggregate before giving it to Runtime or a binding. Setting
  `validate: false` skips aggregate validation, not JSON admission, and is not
  a conformance result.
- Preserve unknown extension terms and never fetch remote JSON-LD contexts.
  Consumer extensions do not redefine W3C Web of Things terms.
- Treat canonical encoding as package-deterministic bytes, not RFC 8785 JCS or
  a signature format. Untouched parsed values alone may retain source bytes.
- Match `Wotex.Error` by code, phase and path, not rendered message. Error
  details may contain bounded input fragments and are not universally log-safe.
- Keep protocol execution, credentials, policy, persistence, identifiers and
  canonical Thing state outside this passive in-memory value package.
