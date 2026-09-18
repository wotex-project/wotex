# Security

Report suspected vulnerabilities privately to `security@wotex.io`. Include the
affected version, impact, and a minimal reproduction. Do not include live
credentials or target a system without authorization.

Supported release lines and disclosure timing are published with each release.

## Dependency audit and Decimal parser boundary

On 2026-09-08, `mix hex.audit` reports no matching advisory for the exact locked
dependency set. The project therefore carries no advisory suppression. The
[Decimal maintainer advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected; this package locks Decimal
3.1.1.

Dependency security tests retain a defense-in-depth boundary: they bind the
reviewed loaded version and prove that default parse, cast and construction
limits reject pathological exponents and over-limit digit counts. No
arithmetic on a pathological value is executed.

This evidence is not a general Decimal safety or whole-VM memory guarantee. Any
dependency or advisory change requires a fresh review. A failed regression,
changed lock, or audit finding blocks the explicit dependency-evidence lane.
Never disable parsing limits for untrusted input.
