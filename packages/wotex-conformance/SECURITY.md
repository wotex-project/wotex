# Security policy

## Reporting

Send suspected vulnerabilities privately to `hello@wotex.io`. Do not include
raw credentials, customer data, or live endpoint details in a public issue.

An acknowledgement will identify the maintainer handling the report. A public
advisory is issued after a fix and affected-version assessment are ready.

## Supported versions

No stable version is currently published. The default branch receives security
fixes, but source availability is not a support commitment.

## Security boundary

The runner executes a consumer-supplied executable. It does not provide an
operating-system sandbox. The consumer must run untrusted subjects inside an
appropriate process, container, virtual-machine, network, and filesystem
isolation boundary.

The library reduces accidental exposure by:

- invoking executables directly without a shell;
- requiring an absolute executable path;
- verifying the subject archive digest before execution;
- bounding time, stdout, argument, environment, and protocol values;
- never sending expected results to the target;
- storing observation digests instead of raw observations in reports; and
- rejecting free-form target diagnostics.

Do not put secrets in claims, vectors, target environment values, or reports.

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
