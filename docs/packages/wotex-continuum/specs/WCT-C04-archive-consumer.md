# WCT-C04 archive-consumer proof

This verification packet exercises the package as a dependency, not as a
checkout. `bin/check_archive.exs` builds one `wotex_continuum` Hex archive with
`WOTEX_PATH_DEPS` unset, places that exact artifact in a temporary signed Hex
registry, and installs it in two behavior-complete independent projects under
the operating system temporary directory. WCT-C05 adds a third direct-Jason-
floor consumer using the same archive. Each project has its own Hex home, Mix
home, dependency directory, build directory, and lockfile.

The core `wotex` package is not yet available from the public Hex registry.
Until it is published, the check builds an exact core candidate archive from
the development dependency (`packages/wotex`) selected by the outer package
gate. This source checkout is only an input to package construction. The
temporary consumers resolve both Wotex packages as `:hex` lock entries through
the signed candidate registry; they have no path or Git dependencies and
assert that loaded BEAMs
come from their own build directories. Released `jason`, `ex_json_schema`, and
`decimal` tarballs are fetched at the versions in the source lock before the
registry is built.

## Executable matrix

| Consumer | Exact archive behavior |
| --- | --- |
| Contract consumer | Constructs a manifest and capability declarations, evaluates compatible and missing-capability outcomes, validates observation and Action Thing identifiers against a caller-supplied Wotex Thing Description, and canonical-round-trips the manifest, observation, Action intent, and successful Action result with extensions. |
| Reference consumer | Runs every packaged valid, canonical, invalid, and compatibility vector under `priv/vectors/`; asserts exact invalid code, phase, and path; validates a packaged Action intent against a supplied Thing Description; canonical-round-trips failure and `unknown` Action results; and applies a same-time lifecycle transition while preserving extensions and incrementing generation. |
| Floor consumer | Repeats the contract consumer with the direct Jason dependency fixed to the declared 1.4.5 floor. The core transitive cohort remains exact and separately qualified by WCT-C05. |
| All consumers | Resolve only Hex lock entries, download bytes whose SHA-256 equals the one archive built by the check, compile with warnings as errors, load no checkout BEAM, and require no network service, process coordinator, clock, database, or privileged resource in the examples. |

The local HTTP listener exists only to serve the signed temporary package
registry during verification. It is not started by the library or used by the
consumer examples.

## Reproduction and evidence

Use the pinned repository toolchain and the explicit development core
selection, from `packages/wotex-continuum`:

```sh
WOTEX_PATH_DEPS=1 mix run --no-start bin/check_archive.exs
```

Package construction and all consumer commands remove `WOTEX_PATH_DEPS`.
The command prints source and core revisions; continuum and core archive,
source lock, schema set, vector set, and consumer-lock SHA-256 digests;
package/wire versions; and the active Elixir/OTP versions. Temporary archives,
keys, consumer projects, locks, and build products are deleted after the check;
execution receipts do not enter the repository or package.

This proves candidate archive installation and the named public seams. It is
not evidence that either Wotex package is publicly released, that a third-party
implementation interoperates, or that any represented Action or lifecycle
transition occurred. Publication and immutable candidate evidence remain
separate maintainer-controlled work.
