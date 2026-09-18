# Security

Report suspected vulnerabilities privately to `hello@wotex.io`. Include the
affected version, impact, and a minimal reproduction. Do not include live
credentials or target a system without authorization. Disclosure timing is
published with each release.

## Supported versions

No version is published yet. Security fixes land on the default branch, and
each release states the release lines it supports. The supported toolchains
are Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through Elixir 1.20.2 with
Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).

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
changed lock, or audit finding blocks the package gate (`mix check`), which runs
`mix deps.audit` and `mix hex.audit`. Never disable parsing limits for
untrusted input.
