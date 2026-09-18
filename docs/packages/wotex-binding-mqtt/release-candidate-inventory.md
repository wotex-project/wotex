# Public release-candidate inventory

WBM-C05 defines a structural public-package gate. It prepares and verifies a
candidate; it does not publish, tag, release, alter a remote, or assert that a
package exists in a registry. The explicit dependency, documentation,
application, boundary, and exact-archive commands in the README provide its
executable evidence.

## Vector map

| Vector | Candidate assertion |
|---|---|
| WBM-P01 | Mix project and Hex metadata have the exact application/package name, version, description, Elixir requirement, source and homepage URLs, maintainer, license, and exactly three package links: GitHub, Changelog, and Specifications |
| WBM-P02 | `LICENSE` and `NOTICE` retain the Apache-2.0 identity and copyright; the package security policy, published through HexDocs, retains the private disclosure address, secret-handling guidance, and dependency-audit policy |
| WBM-P03 | The package allowlist contains public source, `README.md`, `CHANGELOG.md`, `LICENSE`, and `NOTICE`; specifications, plans, provenance, archive evidence, and this candidate inventory reach consumers through HexDocs; archive inspection rejects Markdown documentation, repository automation, QA configuration, tests, build products, local task state, and development instructions |
| WBM-P04 | Exact archive metadata names `wotex ~> 0.1.0`, `wotex_runtime ~> 0.1.0`, and `jason ~> 1.4` as Hex requirements and rejects Git, path, or environment-selected release dependencies |
| WBM-P05 | Dependency resolution checks the package lock without mutation, while the external archive consumer creates and rechecks an independent lock before its behavioral test pass |
| WBM-P06 | Every relative Markdown link resolves, every catalogued specification/evidence file exists, ExDoc builds without warnings, and standards wording retains Profile/Registry/certification nonclaims |
| WBM-P07 | The minimum CI lane in `tooling/packages.yaml` declares Elixir `1.18.4-otp-27` with OTP `27.3.4.15`; each executed compatibility lane records its actual runtime and dependency revisions |
| WBM-P08 | The fast gate (`mix check.fast`) remains compile, format, Credo, and behavioral tests; the package gate adds audits, documentation, coverage, Dialyzer, application-free, boundary, archive, and diff checks |

## Publication-order boundary

The dependency graph is proven from exact archive metadata and the
three-archive external consumer. It does not establish registry availability.
A default registry installation can be admitted only after compatible `wotex`
and `wotex_runtime` releases exist there. Publishing those dependencies or this
package remains a human action outside every repository gate.

Hosted CI verifies `wotex`, `wotex_runtime`, and this package from one commit
of the repository, which a human must first make available to the remote host.
The gate does not substitute moving refs when an exact cohort is required.

The package's Elixir requirement is broader than the one pinned QA pair.
WBM-P07 proves that pair only. A supported platform matrix and registry
installation remain explicit promotion evidence.

No C05 result is W3C conformance, Binding Registry membership, external
certification, production-client/broker certification, compatibility freeze,
or permission to publish. Those limitations survive a fully green structural
candidate gate.
