# Security Policy

Report vulnerabilities in any WoTEx package privately to `hello@wotex.io`.
Include the package, affected version or commit, impact, reproduction
conditions and any proposed mitigation. Do not open a public issue before
coordinated disclosure.

## Shared boundary

The packages are development checkouts without certification claims. Protocol
capability is bounded by each package's specifications and executable
vectors. A consumer supplies credentials, trust anchors, deadlines,
authorization and deployment policy explicitly; no package infers an
authenticated or encrypted channel from a URI scheme, fetches remote JSON-LD
contexts, or retries a write whose effect is unknown.

Errors and telemetry never carry credentials, private key material or raw
protocol payloads. Error details may contain bounded representations of
malformed input and are not universally safe to log.

## Package notes

Package-specific security posture (parser limits, dependency audits, native
component boundaries) is recorded in `docs/packages/<name>/security.md` and
in the package README. Any dependency, advisory or pinned native source change
requires a fresh review in that package.
