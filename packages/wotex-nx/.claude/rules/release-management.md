---
paths:
  - "CHANGELOG.md"
  - "mix.exs"
  - "README.md"
  - "config/config.exs"
---

# Release metadata

`CHANGELOG.md` is release metadata maintained only by GitOps. Never edit,
format, reorder, or curate it manually. Conventional commits are its input.

The Mix `@version` attribute is the package-version source. Once GitOps is
configured for this repository, the human maintainer prepares
the first release from the existing changelog with
`mix git_ops.release --override 0.1.0`; later releases use
`mix git_ops.release`. Do not use `--initial`: GitOps reserves it for creating
a missing changelog and rejects an existing file. These tasks update release
metadata and create Git state, so automated agents must not invoke them.

Automated work may configure GitOps, maintain release-ready source and
documentation, and run verification that cannot change the changelog, version,
commits, or tags.
