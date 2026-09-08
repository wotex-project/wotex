# Security

Report vulnerabilities privately to hello@wotex.io. Include affected versions,
reproduction steps, impact, and suggested mitigations when available.

Treat observations and metadata as untrusted input. Enforce consumer-selected
limits before forming windows or tensors. Never place secrets in observations,
provenance, errors, model outputs, or Action proposals. Numerical output remains
inert until a consumer performs its own authorization and admission.

## Reviewed Decimal advisory metadata

On 2026-09-08, Hex previously reported `EEF-CVE-2026-32686` for Decimal 3.1.1, while
the [maintainer advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected. The
[EEF/OSV record](https://osv.dev/vulnerability/EEF-CVE-2026-32686) carried that same
prose with an unbounded machine-readable affected range. The
[3.1.1 implementation](https://github.com/ericmj/decimal/blob/v3.1.1/lib/decimal.ex)
applies finite default parsing limits.

The current Hex audit no longer matches that advisory to the lock, so this
repository carries no advisory exception. Its dependency-security tests retain
the exact reviewed 3.1.1 Hex lock tuple, including outer checksum
`c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6`,
and loaded version. They require parse, cast and construction to reject the
reported pathological exponent and prove the default exponent/digit thresholds.
No arithmetic on the pathological value is executed.

This is retained regression evidence, not a general Decimal safety or whole-VM
memory guarantee. All advisories remain active. Any dependency or advisory
change requires review, and a failed regression or changed lock blocks `mix check`.
Never disable parsing limits for untrusted input.
