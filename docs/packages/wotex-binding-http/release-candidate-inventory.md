# Public release-candidate inventory

WBH-C05 defines a structural public-package gate. It prepares and verifies a
candidate; it does not publish, tag, release, alter a remote, or assert that a
package exists in a registry. The explicit dependency, documentation, boundary,
and exact-archive commands in the README provide its executable evidence.

## Vector map

| Vector | Candidate assertion |
|---|---|
| WBH-P01 | Mix project and Hex metadata have the exact application/package name, version, description, Elixir requirement, source/homepage links, maintainer, license and public documentation links |
| WBH-P02 | `LICENSE` and `NOTICE` are present in the package allowlist and retain the Apache-2.0 identity and copyright; the package security policy, published through HexDocs, retains the private disclosure address and dependency-audit policy |
| WBH-P03 | The package allowlist contains the public source, `README.md`, `CHANGELOG.md`, `LICENSE` and `NOTICE`; specifications, plans and evidence documents reach consumers through HexDocs; exact archive inspection rejects Markdown documentation, repository automation, QA configuration, tests, build products, local task state and development instructions |
| WBH-P04 | Exact archive metadata names `wotex ~> 0.1.0`, `wotex_runtime ~> 0.1.0`, and `jason ~> 1.4` as Hex requirements and rejects Git, path, or environment-selected release dependencies |
| WBH-P05 | Dependency resolution checks the package lock without mutation, while the external archive consumer creates and rechecks its independent lock before its behavioral test pass |
| WBH-P06 | Every relative Markdown link resolves inside the checkout, every catalogued specification/evidence file exists, ExDoc builds without warnings, and the dated standards wording retains its Profile/Registry/certification nonclaims |
| WBH-P07 | The minimum CI lane in `tooling/packages.yaml` declares Elixir `1.18.4-otp-27` with OTP `27.3.4.15`; each executed compatibility lane records its actual runtime and dependency revisions |
| WBH-P08 | The developer gate remains compile, format, and behavioral tests; audits, documentation, coverage, Dialyzer, boundary, archive, and diff checks run as explicit evidence |

## Publication-order boundary

The release dependency graph is proven from exact archive metadata and the
three-archive external consumer. That does not establish registry availability.
An actual default Hex installation can be admitted only after compatible
`wotex` and `wotex_runtime` releases exist in the selected registry. Publishing
those dependencies or this package remains a human action outside every
repository gate.

Likewise, hosted CI verifies `wotex`, `wotex_runtime` and this package from
one commit of the repository, which a human must first make available to the
remote host. The gate never substitutes a moving ref when an exact cohort is
required.

The package's `elixir: "~> 1.18"` requirement is also broader than the single
pinned QA pair. WBH-P07 proves that pair only. A supported Elixir/OTP matrix and
registry installation remain explicit promotion evidence rather than an
inference from the Mix constraint.

No C05 result is W3C conformance, registry membership, external certification,
production-client certification, compatibility freeze, or permission to
publish. Those limitations survive a fully green structural candidate gate.
