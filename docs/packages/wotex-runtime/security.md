# Security Policy

Report vulnerabilities privately to `hello@wotex.io`. Include the exact version
or commit, impact, and reproduction conditions.

Credential material is resolved immediately before transport execution and is
never stored in a Thing Description, binding profile, request, error, or
subscription state exposed by this package.

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
