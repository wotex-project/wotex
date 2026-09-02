# Wotex Conformance

`wotex_conformance` is a subject-independent evidence library for W3C Web of
Things implementations and related public contracts. It owns versioned claims,
immutable vectors, an external target protocol, archive verification, result
classification, and deterministic machine-readable reports.

The library does not link a subject package into its production dependency
graph. A consumer supplies an immutable subject artifact and a separate adapter
executable. The runner verifies the artifact digest, sends each vector without
its expected value, evaluates the returned observation, and records one of:
`pass`, `fail`, `unsupported`, `not_run`, or `infrastructure_error`.

## Maturity and non-claims

The source is an executable pre-release baseline. Public source availability is
not a stable API promise, a Hex publication promise, interoperability evidence,
or W3C certification. A vector proves only the exact claim, standards revision,
subject digest, adapter protocol, and environment present in its report.

This project:

- starts no application callback or supervision tree;
- owns no database, filesystem authority, credentials, or network client;
- performs I/O only when a consumer explicitly loads a corpus, verifies an
  artifact, or invokes an external target;
- sends no expected result to the target;
- stores target observations as digests rather than raw values in reports; and
- uses W3C WoT terms such as Thing, Property, Action, Event, Form, DataSchema,
  and Thing Description with their standards meanings.

## Example

```elixir
alias Wotex.Conformance.{Corpus, Runner, Subject}
alias Wotex.Conformance.Target.External

{:ok, corpus} = Corpus.load("priv/vectors/thing-description-1.1")

{:ok, subject} =
  Subject.new(%{
    id: "example.thing-description",
    version: "1.2.3",
    artifact_digest: "sha256:...",
    interface: %{"kind" => "archive_adapter", "revision" => "1"}
  })

{:ok, target} =
  External.new(%{
    executable: "/absolute/path/to/elixir",
    args: ["/absolute/path/to/adapter.exs", "--archive", "{subject_archive}"],
    artifact_path: "/absolute/path/to/subject.tar.gz"
  })

{:ok, report} =
  Runner.run(corpus, subject, target,
    generated_at: ~U[2026-09-02 12:00:00Z],
    environment: %{"runtime" => "otp-28", "mode" => "air_gapped"}
  )

report.summary
#=> %{"pass" => 3, "fail" => 0, ...}
```

The adapter contract is documented in
[`WCF.01`](docs/specs/WCF.01-conformance-runner.md). The canonical corpus
manifest is `priv/vectors/thing-description-1.1/manifest.json`.

## Development

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[GOVERNANCE.md](GOVERNANCE.md) before proposing a claim or compatibility
change.
