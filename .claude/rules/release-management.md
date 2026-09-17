---
paths:
  - "packages/**/CHANGELOG.md"
  - "packages/**/mix.exs"
  - "packages/**/README.md"
  - "packages/**/config/config.exs"
---

# Release metadata

Each package under `packages/<name>/` keeps its own `CHANGELOG.md` and version.
`CHANGELOG.md` is release metadata maintained only by GitOps. Never edit,
format, reorder, or curate it manually. Conventional commits are its input.

The Mix `@version` attribute in `packages/<name>/mix.exs` is the
package-version source. Once GitOps tooling and configuration are installed for
the package and release prerequisites pass, the human maintainer prepares the
first release from the existing changelog with
`mix git_ops.release --override 0.1.0`, because the initial changelog already
exists; later releases use `mix git_ops.release`. This describes the human
release workflow; it does not establish readiness or the presence of configured
tooling. Do not use `--initial`: GitOps reserves it for creating a missing
changelog and rejects an existing file. These tasks update release metadata and
create Git state, so automated agents must not invoke them. Tags use the form
`<package>-v<version>`.

Automated work may configure GitOps, maintain release-ready source and
documentation, and run verification that cannot change the changelog, version,
commits, or tags.
