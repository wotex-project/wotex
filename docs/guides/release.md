# Releasing a package

Releases are per package and are performed only by the human maintainer.
Automated agents never tag, push or publish.

## Preconditions

1. The package's completion plan gates are discharged and recorded under
   `docs/packages/<name>/provenance/` against the current source commit.
2. CI is green for the package on both toolchain lanes, and the archive job
   passed for it.
3. Every WoTEx dependency of the package is already published at a version
   the package's `mix.exs` requirement accepts.
4. The native lane has run for a native package on the current source.

## Steps

`git_ops.json` at the repository root configures git_ops for every package:
tags `<name>-v<version>`, the package's own `CHANGELOG.md`, the `@version` in
its `mix.exs`, and only the commits that touch the package outside `bench/`.
From the repository root:

```sh
git tag <name>-v0.0.0 <first commit of the package>   # once, before its first release
mix git_ops.release --no-major                        # every package with releasable commits
```

git_ops reads each package's current version from its tags, so a package's
first release starts from a `0.0.0` tag; its feature commits then make it
`0.1.0`, and the changelog lists every feature and fix since that commit.
`--no-major` keeps a package below 1.0 if its history has a breaking commit.
Each released package gets its own version, changelog entry and tag. Then,
for each released package:

```sh
git push origin main <name>-v<version>
(cd packages/<name> && env -u WOTEX_PATH_DEPS MIX_ENV=prod mix hex.publish)
```

ExDoc links on HexDocs use the same tag: each package's `source_url/2`
(its `source_url_pattern`) links modules under `packages/<name>/` and the
specification extras under `docs/packages/<name>/`, so source links resolve
inside this repository.

## After publishing

- Record the archive SHA-256 and the publication in the package's
  provenance.
- Consumers that used `sparse:` git dependencies can move to the Hex
  requirement.
