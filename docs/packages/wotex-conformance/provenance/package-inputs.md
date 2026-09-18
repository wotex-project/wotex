# Package inputs

`mix.exs` defines the Hex archive inputs with an explicit `files` allowlist:

- `lib`
- `priv/schemas` and `priv/vectors`
- `.formatter.exs`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `README.md` and
  `mix.exs`

The archive ships no Markdown documentation, governance or agent files.
Specifications, decisions and provenance live in this repository under
`docs/packages/wotex-conformance/`, outside the package directory, and reach
consumers through HexDocs. Local execution records live only in the ignored
root `docs/tasks/local/wotex-conformance/`, also outside the package
directory. Their Git ignore rule is repository hygiene; it is not the package
exclusion mechanism.

The WCF-C07 evidence lane places a sentinel under the root
`docs/tasks/local/wotex-conformance/`, builds the archive, reviews the archive
listing, and runs from `packages/wotex-conformance`:

```console
mix run --no-start bin/check_archive.exs
```

The checker rejects an archive containing any `docs` or `tasks` path segment,
local Dialyzer state, Git state, dependencies, or build output. It also checks
required package material and compiles the extracted library outside the
source tree.

This boundary covers the candidate Hex archive produced from the recorded
source and Mix configuration. It makes no claim about files copied by another
packaging system or about a published release.
