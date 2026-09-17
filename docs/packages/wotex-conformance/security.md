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

## Dependency audit and Decimal parser boundary

On 2026-09-08, `mix hex.audit` reports no matching advisory for the exact locked
dependency set. The project therefore carries no advisory suppression. The
[Decimal maintainer advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected; this repository locks Decimal
3.1.1.

Dependency security tests retain a defense-in-depth boundary: they bind the
exact 3.1.1 Hex lock tuple, including outer checksum
`c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6`,
to the loaded version and prove that default parse, cast and construction limits
reject pathological exponents and over-limit digit counts. No arithmetic on a
pathological value is executed.

This evidence is not a general Decimal safety or whole-VM memory guarantee. Any
dependency or advisory change requires a fresh review. A failed regression,
changed lock or audit finding blocks `mix check`. Never disable parsing limits
for untrusted input.
