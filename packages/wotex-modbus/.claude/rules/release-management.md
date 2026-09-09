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

The Mix `@version` attribute is the package-version source. Once GitOps tooling
and configuration are installed, the human maintainer prepares the first
release with `mix git_ops.release --override 0.1.0` because the initial changelog
already exists. Later releases use `mix git_ops.release`. This describes the
human release workflow; it does not establish readiness or the presence of
configured tooling. Do not use `--initial`: GitOps reserves it for creating
a missing changelog and rejects an existing file. These tasks update release
metadata and create Git state, so automated agents must not invoke them.

Automated work may configure GitOps, maintain release-ready source and
documentation, and run verification that cannot change the changelog, version,
commits, or tags.
