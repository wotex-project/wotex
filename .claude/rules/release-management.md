---
paths:
  - "packages/**/CHANGELOG.md"
  - "packages/**/mix.exs"
  - "packages/**/README.md"
  - "git_ops.json"
---

# Release metadata

Each package under `packages/<name>/` keeps its own `CHANGELOG.md` and version.
`CHANGELOG.md` is release metadata maintained only by GitOps. Never edit,
format, reorder, or curate it manually. Conventional commits are its input.

GitOps is configured once, in the root `git_ops.json`: one entry per package
with its `<package>-v<version>` tags, its `CHANGELOG.md`, the `@version` in its
`mix.exs` and only the commits that touch it (outside `bench/`). Packages carry
no GitOps configuration or dependency. The human maintainer runs
`mix git_ops.release` from the repository root; it releases every package with
releasable commits since its last tag. A package's first release starts from
the tag `<package>-v0.0.0` at the package's first commit (see
`docs/guides/release.md`). `--override` and `--initial` do not apply to
several packages. These tasks update release metadata and create Git state, so
automated agents must not invoke them.

Automated work may configure GitOps, maintain release-ready source and
documentation, and run verification that cannot change the changelog, version,
commits, or tags.
