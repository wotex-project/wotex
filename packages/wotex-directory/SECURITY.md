# Security policy

## Supported versions

Before the first stable release, the current development line receives security
updates. After stable release, the latest stable minor line and explicitly
listed long-lived lines are supported.

## Reporting

Report suspected vulnerabilities privately to hello@wotex.io. Include affected
versions, reproduction conditions, impact, and a minimal proof when safe. Do
not open a public issue before coordinated disclosure.

The maintainers will acknowledge the report, assess affected versions, prepare
a fix and tests, and coordinate disclosure. No response-time promise is made.

## Boundary

The consumer is responsible for authentication, authorization policy,
repository isolation, transport security, credential handling, deployment, and
operational monitoring. This library guarantees only its documented port order,
bounded operations, validation-before-write behavior, and deterministic errors.

## Reviewed dependency advisory

On 2026-09-08, Hex reports `EEF-CVE-2026-32686` for Decimal 3.1.1, while
the [maintainer advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected. The
[EEF/OSV record](https://osv.dev/vulnerability/EEF-CVE-2026-32686) has that same
prose but an unbounded machine-readable affected range. The
[3.1.1 implementation](https://github.com/ericmj/decimal/blob/v3.1.1/lib/decimal.ex)
applies finite default parsing limits.

The repository temporarily acknowledges only this advisory. Its dependency
security tests bind that acknowledgement to the exact 3.1.1 Hex lock tuple,
including outer checksum
`c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6`,
and loaded version. They require parse, cast and construction to reject the
reported pathological exponent and prove the default exponent/digit thresholds.
No arithmetic on the pathological value is executed.

This is a scoped metadata-conflict decision, not a general Decimal safety or
whole-VM memory guarantee. Other advisories remain active. Any dependency or
advisory change requires review; remove this acknowledgement when the metadata
is corrected. A failed regression or changed lock blocks `mix check`.
Never disable parsing limits for untrusted input.
