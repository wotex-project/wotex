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

From `packages/<name>`:

```sh
mix git_ops.release            # first release: mix git_ops.release --override 0.1.0
```

`git_ops` is configured per package (`config/config.exs`) with
`version_tag_prefix: "<name>-v"`, so the tag is `<name>-v<version>` and only
that package's version and changelog move. Then:

```sh
git push origin main <name>-v<version>
WOTEX_PATH_DEPS= MIX_ENV=prod mix hex.publish
```

ExDoc links on HexDocs use `source_url_pattern` with the same tag and the
`packages/<name>/` prefix, so source links resolve inside this repository.

## After publishing

- Record the archive SHA-256 and the publication in the package's
  provenance.
- Consumers that used `sparse:` git dependencies can move to the Hex
  requirement.
