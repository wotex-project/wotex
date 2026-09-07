# Changelog

## 0.1.0

- Establish caller-owned HTTP request and response mapping for selected WoT operations.
- Define an explicit client port with ephemeral credential handling.
- Add Server-Sent Events subscriptions with client-owned framing and lifecycle.
- Hand the client the Runtime subscription process and decode frames there through `decode_frame/3`.
- Accept client session statuses and let Runtime supervision own reconnection decisions.
- Classify every failure as `:timeout`, `:rate_limited`, `:unavailable`, `:protocol`, or `:permanent`.
- Return the neutral `:ok` and `:accepted` Runtime statuses and report the HTTP status in metadata.
- Decode JSON through the bounded `Wotex.JSON` admission limits and publish the client byte limits on each request.
- Enforce credential, framing, URI, media-type, and encoded-byte safety boundaries.
- Ship immutable public values, normalized errors, and a process-free library application.
- Add strict documentation, static analysis, coverage, dependency-audit, and archive gates.
