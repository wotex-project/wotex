# Governance

## Roles

- Maintainers approve releases, security actions, governance changes, and
  compatibility decisions.
- Reviewers approve specifications, claims, vectors, and implementation changes
  within their demonstrated expertise.
- Contributors propose and implement changes under the contribution policy.

## Decision rules

At least one maintainer and one qualified reviewer must approve a standards
claim, target-protocol change, canonicalization change, or release. The same
person may not supply both approvals for a new certification-facing claim.

Disagreement is resolved from reproducible evidence and the exact cited
standard revision. If evidence is insufficient, the claim remains unsupported
or unpublished.

## Release authority

A maintainer may create a release only when locked CI, allowed-newer CI,
documentation, package archive, dependency boundary, provenance, and security
gates pass against the exact commit. Tags and packages must identify that
commit and archive digest.

No maintainer may describe a release as W3C-certified without a separate,
applicable external certification record.

## Contact

Governance and maintainer enquiries: `hello@wotex.io`.
