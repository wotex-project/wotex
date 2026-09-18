# Security

Report suspected vulnerabilities privately to `security@wotex.io` before public
discussion. Do not include live credentials, broker addresses, payloads, or
client state in a report. This package never owns a connection and never stores
the execution context passed to a client port.

## Reviewed Decimal advisory metadata

On 2026-09-08, Hex previously reported `EEF-CVE-2026-32686` for Decimal 3.1.1, while
the [maintainer advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v)
identifies versions before 3.0.0 as affected. The
[EEF/OSV record](https://osv.dev/vulnerability/EEF-CVE-2026-32686) carried that same
prose with an unbounded machine-readable affected range. The
[3.1.1 implementation](https://github.com/ericmj/decimal/blob/v3.1.1/lib/decimal.ex)
applies finite default parsing limits.

The current Hex audit no longer matches that advisory to the lock, so this
package carries no advisory exception. Its dependency-security tests retain
the reviewed loaded version. They require parse, cast and construction to
reject the reported pathological exponent and prove the default exponent/digit
thresholds. No arithmetic on the pathological value is executed.

The package gate (`mix check`) runs `mix deps.audit` and `mix hex.audit`;
either audit failure blocks the candidate and requires review rather than a
waiver.

This is retained regression evidence, not a general Decimal safety or whole-VM
memory guarantee. All advisories remain active. Any dependency or advisory
change requires review. A failed regression or changed lock blocks the package
gate. Never disable parsing limits for untrusted input.
