# Public release-candidate inventory

WBM-C05 defines a structural public-package gate. It prepares and verifies a
candidate; it does not publish, tag, release, alter a remote, or assert that a
package exists in a registry. The executable authority is
`bin/check_release.exs`, combined with the boundary and exact-archive consumer
checks in the ordinary default `mix check --no-retry` gate.

## Vector map

| Vector | Candidate assertion |
|---|---|
| WBM-P01 | Mix project and Hex metadata have the exact application/package name, version, description, Elixir requirement, source/homepage links, maintainer, license, and public documentation links |
| WBM-P02 | `LICENSE`, `NOTICE`, and `SECURITY.md` retain the Apache-2.0 identity, copyright, private disclosure address, secret-handling guidance, and dependency-audit policy |
| WBM-P03 | The package allowlist contains public source, specifications, plans, provenance, archive evidence, and this candidate inventory; archive inspection rejects repository automation, QA configuration, tests, build products, local task state, and development instructions |
| WBM-P04 | Exact archive metadata names `wotex ~> 0.1.0`, `wotex_runtime ~> 0.1.0`, and `jason ~> 1.4` as Hex requirements and rejects Git, path, or environment-selected release dependencies |
| WBM-P05 | The repository lock contains only exact Hex tuples for registry dependencies; the default gate checks it without mutation, while the external archive consumer creates and rechecks an independent lock before one test pass |
| WBM-P06 | Every relative Markdown link resolves, every catalogued specification/evidence file exists, ExDoc builds without warnings, and standards wording retains Profile/Registry/certification nonclaims |
| WBM-P07 | `.tool-versions` and CI declare Elixir `1.18.4-otp-27` with OTP `27.3.4.15`; CI pins exact core and Runtime revisions, bootstraps all locked gate tools, and runs the ordinary authoritative gate |
| WBM-P08 | The authoritative gate includes compile, lock, unused-dependency, format, audits, Credo, Doctor, documentation, Dialyzer, one coverage-backed test run, boundary/application, exact-archive/reference-consumer, candidate, and diff checks without a second ExUnit pass |

## Publication-order boundary

The dependency graph is proven from exact archive metadata and the
three-archive external consumer. It does not establish registry availability.
A default registry installation can be admitted only after compatible `wotex`
and `wotex_runtime` releases exist there. Publishing those dependencies or this
package remains a human action outside every repository gate.

Hosted CI can resolve its immutable sibling revisions only after a human makes
those commits available to the remote host in dependency order. The repository
does not substitute moving refs when an exact cohort is required.

The package's Elixir requirement is broader than the one pinned QA pair.
WBM-P07 proves that pair only. A supported platform matrix and registry
installation remain explicit promotion evidence.

No C05 result is W3C conformance, Binding Registry membership, external
certification, production-client/broker certification, compatibility freeze,
or permission to publish. Those limitations survive a fully green structural
candidate gate.
