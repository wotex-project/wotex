# Wotex Conformance

**Deterministic, subject-independent conformance evidence for W3C WoT libraries.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_conformance.svg)](https://hex.pm/packages/wotex_conformance)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_conformance)
[![CI](https://github.com/wotex-project/wotex-conformance/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-conformance/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-conformance/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-conformance)
[![License](https://img.shields.io/hexpm/l/wotex_conformance.svg)](https://github.com/wotex-project/wotex-conformance/blob/main/LICENSE)

[Installation](#installation) · [Evidence Model](#evidence-model) ·
[Quick Start](#quick-start) · [External Target Protocol](#external-target-protocol) ·
[Security Boundary](#security-boundary) · [Development](#development)

---

This development checkout has an unstable public API. Package publication
requires a separately reviewed release.

`wotex_conformance` owns versioned claims, immutable vectors, verified corpora,
an external target protocol, result classification, and canonical evidence
reports. It never links the subject under test into its production dependency
graph: the consumer supplies a content-addressed subject archive and an adapter
executable.

The bundled baselines contain fourteen Thing Description 1.1 vectors and six
Thing Model 1.1 vectors. Each is claim-scoped synthetic evidence; corpus size
is not a whole-standard conformance or interoperability claim. Negative vectors
expect the bounded rejection identifiers an implementation emits for the cited
clause, not invented codes.

## Installation

```elixir
def deps do
  [{:wotex_conformance, "~> 0.1.0"}]
end
```

## Evidence Model

A report establishes only the exact tuple it records: claim and standards
revision, vector digest, corpus digest, subject identity and archive digest,
target protocol, bounded environment metadata, observation digest, and result.
It is not a package-wide interoperability or W3C certification claim.

| Status | Meaning |
|--------|---------|
| `pass` | The target observation canonically equals the runner-owned expectation. |
| `fail` | The target produced a valid but different observation. |
| `unsupported` | The target explicitly declined the bounded operation. |
| `not_run` | Selection excluded the vector. |
| `infrastructure_error` | Archive verification or target execution prevented evaluation. |

Expected values and provenance never cross the target boundary. Reports retain
expected and actual digests, not raw observations. An adapter derives its
observation from the request alone, so a target that guesses by vector identity
proves nothing.

## Quick Start

```elixir
alias Wotex.Conformance.{Corpus, Runner, Subject}
alias Wotex.Conformance.Target.External

{:ok, corpus} = Corpus.load("priv/vectors/thing-description-1.1")

{:ok, subject} =
  Subject.from_map(%{
    id: "example.thing-description",
    version: "1.2.3",
    artifact_digest: "sha256:" <> String.duplicate("0", 64),
    interface: %{"kind" => "archive_adapter", "revision" => "1"}
  })

{:ok, target} =
  External.from_map(%{
    executable: "/absolute/path/to/elixir",
    args: ["/absolute/path/to/adapter.exs", "--archive", "{subject_archive}"],
    artifact_path: "/absolute/path/to/subject.tar.gz"
  })

{:ok, report} =
  Runner.run(corpus, subject, target,
    generated_at: ~U[2026-09-02 12:00:00Z],
    environment: %{"runtime" => "otp-28", "mode" => "air_gapped"}
  )
```

Use `priv/vectors/thing-model-1.1` when the subject interface implements
`thing_model.parse` and `thing_model.validate`. The two corpora remain
independent so a subject can report exactly which document boundary it
implements.

Use the digest of the actual archive; the zero digest above only demonstrates
the required wire shape.

## External Target Protocol

`Wotex.Conformance.Target.External` starts one direct executable per selected
vector—never a shell. It writes one canonical JSON request to standard input,
collects one bounded JSON response from standard output, and enforces a timeout.
The inherited operating-system environment is removed before explicitly
configured non-sensitive values are applied.

Arguments may contain `{subject_archive}` to receive the verified absolute
archive path. The target response must echo the vector ID and declare either an
`observed` value or an `unsupported` outcome. The complete protocol and failure
codes are specified in [`WCF.01`](docs/specs/WCF.01-conformance-runner.md).

### Normalized observations

Vectors for `thing_description.parse`, `thing_description.validate`,
`thing_model.parse`, and `thing_model.validate` declare their input as a
document plus a projection of RFC 6901 JSON Pointers, and expect one normalized
observation:

```json
{"accepted": true, "document": {"/title": "Minimal Thing"}}
```

```json
{
  "accepted": false,
  "errors": [{"code": "schema_violation", "phase": "schema", "path": "/title"}]
}
```

An accepted observation maps each declared pointer that resolves to its member
value and omits the pointers that do not; an empty projection declares the whole
accepted document. Rejection errors carry only bounded `code`, `phase`, and
`path` identifiers, unique and sorted by path and code, because messages are not
a stable interface. The projection travels to the target inside `vector.input`,
so an independent adapter derives the observation from the request alone and
never needs the runner-owned expectation. A non-normalized observation is an
`infrastructure_error`, not a `fail`.

## Security Boundary

Corpus loading rejects symbolic links, undeclared files, traversal, duplicate
vector IDs, oversized inputs, and digest mismatches before invocation. Artifact
verification streams a bounded regular file without extraction or subject code
execution. Target output, execution time, arguments, and environment are
bounded; keys suggesting credentials or secrets are rejected.

The package starts no application callback or supervision tree, owns no
database or persistent filesystem authority, reads no global configuration,
and opens no network connection. I/O occurs only when a consumer explicitly
loads a corpus, verifies an artifact, or runs an external target.

## Development

```console
mix deps.get
mix check
```

`mix check` runs warnings-as-errors compilation, formatting, and the test suite.
Package, documentation, audit, and compatibility checks are explicit
release-readiness work.

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[SECURITY.md](SECURITY.md), and [GOVERNANCE.md](GOVERNANCE.md). Licensed under
Apache-2.0; see [LICENSE](LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex-conformance/blob/main/NOTICE).
