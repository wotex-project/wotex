# WCT-C05 release-candidate dossier

This dossier classifies the public `wotex_continuum` 0.1.0 candidate. It is a
verification map, not a release announcement or a publication record. The
wire contract is independently versioned at 2.0.0. Neither version implies
that the package is available from a public registry.

## Candidate identity

`bin/check_archive.exs` builds one exact package archive and emits the source
revision, archive SHA-256, source lock SHA-256, schema-set SHA-256, vector-set
SHA-256, package and wire versions, core source revision and candidate archive
SHA-256, each independent consumer lock SHA-256, and the active Elixir/OTP
versions. Run it only from the source revision being evaluated. A `+dirty`
suffix means that the revision alone does not identify the evaluated tree.

Those values are execution evidence and remain outside the package. Embedding
an archive digest in a file contained by that archive would be
self-referential. A maintainer can retain the command output beside a later
immutable release record without changing the candidate.

The reviewed command is:

```sh
WOTEX_PATH_DEPS=1 mise exec erlang@27.3.4.15 elixir@1.18.4-otp-27 -- \
  mix check --no-retry
```

The default gate resolves the repository lock with `--check-locked`, compiles
with warnings as errors, checks formatting and strict Credo, audits
dependencies, runs Dialyzer, Doctor and documentation checks, executes the
test suite once with coverage, scans the public boundary, and runs the archive
consumers. Release and publication commands are not part of the gate.

## Package and wire compatibility

| Dimension | Candidate decision |
| --- | --- |
| Package API | Package 0.1.0 is pre-1.0 and unstable. The exported API is reviewed and regression-tested, but this dossier makes no stable package-API promise. |
| Wire schema | Exactly 2.0.0 is admitted. Missing, 1.x, 3.x, and other non-current versions are rejected with `unsupported_schema_version` at `/schema_version`. |
| Wire 1 to wire 2 | Incompatible. Wire 2 renamed `execution_context` to `execution_scope` and uses RFC 6901 error paths. No implicit migration occurs. |
| Wire 2 extensions | Absolute-IRI extension members can be added without changing field meaning. Unknown ordinary members remain rejected. |
| Canonical bytes | Exact for wire 2.0.0 and this encoder contract. Changing member meaning, accepted enum vocabulary, or canonical bytes requires an incompatible wire classification. The format is project-canonical JSON, not RFC 8785 JCS. |
| Schema repair | A schema-only correction is compatible only when constructors already enforced the normative rule and accepted values and canonical bytes do not change. Schema digests still change and require fresh evidence. |

The packaged compatibility vectors prove both a matching wire/capability cohort
and every reported mismatch. The invalid `wct-01-unsupported-schema` vector
proves the version rejection path. There is no best-effort decoding of another
wire version.

## API review

The supported entry surface consists of:

- the `WotexContinuum` registry and map facade;
- the 13 registered value modules and three nested value modules;
- `Codec`, `CanonicalJSON`, `Schema`, `Limits`, `Error`, and `ThingReference`;
- compatibility evaluation and manifest delegation; and
- mode enumerations and pure lifecycle transitions.

`new/1` remains the 0.1 alias of each value module's `from_map/1`.
`Lifecycle.transition/3` is the default-options form of `transition/4`.
`WotexContinuum.Contract` and `WotexContinuum.Validation` are documented
implementation helpers, not alternate admission surfaces. Their exports and
the `@doc false` registry/error/limit helpers remain inventoried so an
accidental export change cannot bypass review. The exact export snapshot is in
`release_contract_test.exs`.

Expected failures return `{:error, %WotexContinuum.Error{}}`. Consumers may
match `code`, `phase`, and `path`; message prose and `details` membership may
change compatibly. Optional means absent, not `null`. Explicit JSON `null` is
accepted only as a present JSON value for observation `value`, Action `input`,
a successful Action `output`, or failure `details`. The internal
`output_present?` marker preserves absent output versus present `null`.
Defaults, conditional result states, exact error paths, and reconstruction are
mapped in WCT-C01. Native/decoder admission differences are mapped in WCT-C02,
and constructor/schema/vector/canonical agreement is mapped in WCT-C03.

## Dependencies and toolchains

The archive metadata declares only two runtime requirements:

| Dependency | Declared range | Reviewed evidence |
| --- | --- | --- |
| `wotex` | `~> 0.1` | Exact 0.1.0 core candidate archive from the named clean source revision. It remains a candidate until the core package is publicly available. |
| `jason` | `~> 1.4.5` | Direct floor and reviewed latest cohort are both 1.4.5. They are installed separately from the same continuum archive and both run the contract consumer. Jason 1.4.0 through 1.4.4 exclude Decimal 3 and cannot resolve with the exact core cohort. |

The locked runtime graph also contains `ex_json_schema` 0.11.5 and `decimal`
3.1.1 through core. The archive check installs exact versions and Hex-only
lock entries in two behavior-complete consumers and one direct-dependency-floor
consumer. Each uses an independent OS-temporary Mix home, Hex home, dependency
tree, build tree, and lockfile. Loaded Wotex BEAMs must come from the consumer,
not either source checkout.

The arbitrary lowest transitive graph allowed by core's current
`ex_json_schema ~> 0.11` declaration is not claimed: early 0.11 releases allow
Decimal 2.x, while this package's reviewed parser and advisory boundary is
Decimal 3.1.1. Tightening that upstream range belongs to the core package. This
candidate proves its exact locked/candidate graph and the direct Jason floor;
it does not claim every resolver outcome permitted by an upstream broad range.

The package declares Elixir `~> 1.18`. Release-candidate evidence is pinned to
Elixir 1.18.4 on OTP 27. The repository's CI compatibility lane is separate
evidence and does not replace the exact local candidate toolchain.

## Public archive and legal/security review

The archive check reads Hex `metadata.config` and requires the exact package
name, application, version, description, links, Elixir requirement, Apache-2.0
license, build tool, and runtime requirements. It requires the README, LICENSE,
NOTICE, SECURITY, GOVERNANCE, threat model, dependency/source provenance,
owning specifications, WCT-C01 through WCT-C05 maps, schemas, and public
vectors. It rejects repository control files, repository-only tooling, local
execution state, source checkouts, build output, coverage output, PLTs,
executable verification scripts, and the internal test suite. Symlinks and
embedded local source paths are rejected.

The package has no application callback and starts no process. The default gate
runs both Hex retirement and advisory audits without suppressions. The exact
Decimal lock tuple and bounded parser behavior have dedicated regression tests.
Apache-2.0 licensing is represented by `LICENSE`; `NOTICE` records project and
W3C attribution boundaries. W3C Thing Description and Architecture terminology
is used by reference. WCT envelopes are project-defined and are not a W3C
Profile, WoT Scripting API, certification, or endorsement.

## Nonclaims

This packet does not prove public Hex availability, third-party or cross-vendor
interoperability, RFC 8785 compatibility, artifact authenticity, trusted time,
identity, authorization, dispatch, exactly-once delivery, persistence,
reconciliation, actual disconnected operation, teardown, or certified
standards conformance. The package represents inert claims as data. Consumers
retain every authority and side effect.
