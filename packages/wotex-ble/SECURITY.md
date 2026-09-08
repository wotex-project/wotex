# Security

This development package has no certification claim. Protocol capability is
bounded by its specifications and executable vectors. The consumer supplies
credentials, trust anchors, deadlines and deployment policy explicitly.

Never infer an authenticated or encrypted channel from a URI scheme. Unsupported
security modes fail before opening a connection. Do not log credentials,
protocol payloads or private key material in errors or telemetry.

A timeout after sending a write means the effect may be unknown. No silent write
retry is allowed. Report security issues privately to hi@futhr.io.

## Decimal parser regression

As of 2026-09-08, `mix hex.audit` reports no advisory for the locked Decimal
3.1.1 cohort. No advisory is ignored by project configuration. The
[maintainer advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected, and the
[3.1.1 implementation](https://github.com/ericmj/decimal/blob/v3.1.1/lib/decimal.ex)
applies finite default parsing limits.

Dependency-security tests bind the reviewed cohort to the exact 3.1.1 Hex lock
tuple, including outer checksum
`c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6`,
and loaded version. They require parse, cast and construction to reject the
reported pathological exponent and prove the default exponent/digit thresholds.
No arithmetic on the pathological value is executed.

This regression is not a general Decimal safety or whole-VM memory guarantee.
Any future advisory, failed regression or changed lock blocks `mix check`.
Never disable parsing limits for untrusted input.
