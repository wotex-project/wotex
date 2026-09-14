# Package documentation inputs

`mix.exs` defines the Hex archive inputs with an explicit `files` allowlist.
Publishable documentation enters the archive only through these directory
roots:

- `docs/decisions`
- `docs/plans`
- `docs/provenance`
- `docs/specs`

The allowlist does not contain `docs/tasks` or one of its ancestors. Local
execution records under `docs/tasks/local` therefore remain outside the
archive even when those files exist while `mix hex.build` runs. Their Git
ignore rule is repository hygiene; it is not the package exclusion mechanism.

The WCF-C07 evidence lane places a sentinel under `docs/tasks/local`, builds
the archive, reviews the archive listing, and runs:

```console
mix run --no-start bin/check_archive.exs
```

The checker rejects an archive containing `docs/tasks/local`, local Dialyzer
state, Git state, dependencies, or build output. It also checks required
package material and compiles the extracted library outside the source tree.

This boundary covers the candidate Hex archive produced from the recorded
source and Mix configuration. It makes no claim about files copied by another
packaging system or about a published release.
