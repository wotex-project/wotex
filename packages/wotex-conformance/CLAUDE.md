# Wotex Conformance package contract

Wotex Conformance (`packages/wotex-conformance`, Hex `wotex_conformance`) is a
public, normal Mix library that depends on no other WoTEx package. It owns
conformance claims, verified vector corpora, the external target protocol,
result classification and canonical evidence reports for any W3C Web of Things
implementation. Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Production code may not compile-depend on a tested subject. Subjects are
  exercised only through immutable archives or public interfaces via an
  external adapter. The only production dependency is `jason`.
- Expected values, expected digests, vector digests and provenance never cross
  the target protocol boundary.
- This library defines no `Application.start/2`, database, persistence layer,
  background job, network client, global registry, or hidden process tree.
- I/O happens only after an explicit API call. Module loading is inert.
- Do not infer standards support from a module name, fixture presence, or a
  successful unrelated vector.
- A report is evidence for only its exact subject digest, corpus digest, claim,
  vector revision, protocol revision, and environment.
- Public source is not W3C certification or a stable release promise.
- Elixir `~> 1.18`, matching `mix.exs`; the repository toolchain in the root
  `mise.toml` is Elixir 1.20 and Erlang/OTP 29. Minimum-runtime evidence and
  the accepted cohort are reviewed separately under WCF-C06; the Mix
  requirement alone does not prove coverage.
- One module per `.ex` file. Tests use `@moduledoc false` followed by a blank
  line.
- Use tagged return values and `Wotex.Conformance.Error`; do not raise for
  untrusted data.
- Keep user-controlled strings bounded. Never create atoms from input.
- Canonical JSON is the digest authority. Map keys are strings and sorted by
  their UTF-8 byte representation.
- Reports contain observation digests and bounded diagnostic codes, not raw
  target values, stdout, credentials, endpoints, or exception text.
- External commands use direct executable invocation, never a shell.
- Corpus revisions, manifest digests, the ten schema mirrors in
  `priv/schemas/` and fixtures change atomically with the constructors they
  mirror. Tests and specifications under `docs/packages/wotex-conformance/`
  change with the contract they prove.

## Where things are

- `lib/wotex/conformance.ex`: the facade (`load_corpus/1`, `run/4`).
- `lib/wotex/conformance/runner.ex`: verifies the archive, invokes the target
  per selected vector, compares observations and builds the report.
- `lib/wotex/conformance/target.ex`, `target/external.ex`,
  `target/response.ex`: the target behaviour, the direct-executable external
  target (ports, timeouts, output bounds, scrubbed environment) and response
  validation.
- `lib/wotex/conformance/corpus.ex`, `vector.ex`, `claim.ex`,
  `expectation.ex`: corpus loading and digest verification, and the closed
  claim, vector and expectation values.
- `lib/wotex/conformance/observation.ex`, `pointer.ex`: the normalized
  document observation and RFC 6901 projection.
- `lib/wotex/conformance/subject.ex`, `artifact.ex`: subject identity and
  streaming archive digest verification.
- `lib/wotex/conformance/report.ex`, `result.ex`, `environment.ex`,
  `canonical.ex`: results, content-addressed reports, bounded environment
  metadata and canonical JSON digests.
- `lib/wotex/conformance/error.ex`, `input.ex`, `value.ex`: structured errors
  and bounded input and JSON-value validation.
- `priv/vectors/thing-description-1.1/`, `priv/vectors/thing-model-1.1/`: the
  bundled corpora with their `manifest.json`; `priv/schemas/`: the JSON Schema
  mirrors of every constructor.
- `test/support/`: `fixtures.ex`, `json_schema.ex` and the static and failing
  targets; `test/fixtures/external_target.exs` (independent protocol target)
  and `archive_consumer.exs` (archive-only consumer).
- `bin/check_archive.exs`, `bin/check_application_free.exs`,
  `bin/check_boundary.exs`: the package checks.
- Specification: `docs/packages/wotex-conformance/specs/WCF.01-conformance-runner.md`
  (`catalogue.yaml` owns status); decisions 0001 to 0004 and provenance beside
  it; completion plan `docs/packages/wotex-conformance/plans/wotex-conformance-completion.md`.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-conformance test test/wotex/conformance/<file>_test.exs`, or `mix impact Wotex.Conformance.Runner run --run` |
| 1 | `mix check.fast --package wotex-conformance` |
| 2 | `mix check` (full gate here, fast gate in `wotex-lab`) |

The full gate alone is `mix pkg wotex-conformance check --no-retry`
(equivalently `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-conformance`); it adds dependency audits, Doctor, docs, the
coverage floor, Dialyzer, the boundary scan over the source tree, the
archive check (which also runs `bin/check_boundary.exs` over the unpacked
archive and the archive-only consumer) and the application-free check. Run
`mix dialyzer.pkg wotex-conformance` in tier 1 when a typespec, the
`Wotex.Conformance.Target` callback or an inferred return type changed.

Tests by area, all under `test/wotex/conformance/`:

- Runner classification and target isolation: `runner_test.exs`.
- External target lifecycle, ports, timeouts and partial output:
  `external_lifecycle_test.exs`.
- Corpus loading, manifests and traversal: `corpus_test.exs`; assertion
  provenance: `assertion_inventory_test.exs`.
- Constructor limits and closed contracts: `validation_matrix_test.exs`,
  `contracts_test.exs`, `conventions_test.exs`.
- Normalized observations and projections: `observation_test.exs`.
- Schema mirrors against vectors, reports and protocol messages:
  `schema_test.exs`.
- Canonical JSON and digests: `canonical_test.exs`; reports:
  `report_test.exs`; archive verification: `artifact_test.exs`.
- No application callback, dependency allowlist, inert loading, boundary
  script: `boundary_test.exs`; locked Decimal boundary:
  `dependency_security_test.exs`; doctests: `documentation_test.exs`.
- Package contents, `priv/`, `mix.exs` `package` or the archive fixtures: the
  full gate (archive check).

`wotex-lab` calls this package's public API in dev and test
(`Wotex.Conformance`, `Wotex.Conformance.Corpus`,
`Wotex.Conformance.Target.External`); `packages/wotex/bin/wcf_target.exs` is a
target that speaks the WCF target protocol. Before changing a public function
or the protocol, list callers with `mix refs Wotex.Conformance.Module fun` and
the tests to run with `mix impact Wotex.Conformance.Module fun`.

Wotex Conformance has no native build, software profile or container lane.
The runtime cohort evidence in
`docs/packages/wotex-conformance/provenance/runtime-compatibility.md` is
re-recorded only when asked.
