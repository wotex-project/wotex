# Wotex Conformance completion contract

Plan `WCF-C`, revision `1.2.0`. This immutable baseline defines work, not current
progress. Preserve work IDs; revisions that change scope require an explicit
successor. Package 0.1.0, WCF.01 specification 1.1.0, corpus/schema revisions and
target protocol 1.0 are distinct version axes.

Revision 1.2.0 records the package's move into the `wotex` repository without
changing any obligation. Documentation now lives under
`docs/packages/wotex-conformance/`. Package archives no longer ship Markdown
documentation, governance files or agent files; specifications are published
through HexDocs. Fixtures and machine-read provenance ship under `priv/`. The
package gate `WOTEX_PATH_DEPS=1 mix check --no-retry`, run from
`packages/wotex-conformance`, and the package's CI lane now discharge
`repository_green` and `archive_consumer_green`. Tags use
`wotex-conformance-v<version>`.

Revision 1.1.0 aligns this acceptance baseline with WCF.01 1.1.0 and accepted
decision 0003's normalized-observation contract. It does not promote any
interoperability, certification, runtime-cohort, or release claim.

## Owned contract and exclusions

WCF.01 and decisions 0001/0002/0003 are normative. The package owns verified local
corpora, closed claim/subject/vector values, external-target protocol execution,
comparison and bounded content-addressed evidence. `Wotex.Conformance.load_corpus/1`
and `run/4` delegate to `Corpus.load/1` and `Runner.run/4`. Construct `Subject`,
`Claim`, `Vector` and `Target.External` with `from_map/1`, their closed public
map constructors; validate report metadata with `Environment.validate/1`. Do not
trust struct shape. Ten JSON schemas mirror the constructors, including the
declared document input and the normalized observation; a disagreement is a
defect, not permission to accept the looser side.

The runner never compiles a production subject as a dependency. It sends input,
not expectation, vector digest or provenance, to the target. An observed result
is not a claim of correctness until the runner compares it. Reports distinguish
`pass`, `fail`, `unsupported`, `not_run` and `infrastructure_error`; invalid runner
configuration is an error rather than a fabricated report. Report evidence binds
subject archive, corpus, claims, vectors, protocol and environment. Observations
are represented by digests and bounded codes, never raw stdout or secret values.

The bundled `test/fixtures/external_target.exs` is an independent protocol
fixture, not a subject adapter. It derives one normalized observation from the
request alone: it decodes the declared document, applies the declared
projection, and otherwise applies the structural rules stated in the fixture. It
holds no table of expected answers and never branches on a vector identity. It
proves protocol, projection, comparison and classification mechanics only; it is
not a W3C validator and is no evidence about any subject package. A real adapter
for a Web of Things package belongs in an external consumer laboratory, because
production code here may not depend on a tested subject. WCF-C03 remains the
lane for that archive-only consumer and its independently implemented target.

Loading the package starts no process. Explicit execution starts one bounded
subprocess per vector using an absolute executable, literal arguments and sanitized
environment, never a shell. Artifact validation precedes execution. Timeout
covers encoding/start/write/read; output bounds and port cleanup apply on every
path. The consumer supplies containment for descendants and malicious executables:
an Erlang Port is not an OS sandbox. Recovery reruns immutable evidence inputs;
there is no hidden queue, persisted checkpoint or retry worker. Concurrent callers
must not share mutable target state or leak output between runs.

Limits in WCF.01 remain authoritative: corpus manifest 1,048,576 bytes, vector
4,194,304 bytes and 10,000 vectors; external defaults 5,000 ms and 1,048,576 output
bytes; at most 64 arguments of 4,096 bytes and 64 environment values of 1,024
bytes. Archive streaming bounds include growth after inspection. File symlinks,
traversal, wrong digests and malformed protocol data fail closed. No network
retrieval, certification service, hardware harness or production SLA is implied.

## Standards and remaining-claim ledger

| Claim ID | Authority and current bounded evidence | Remaining / nonclaim |
| --- | --- | --- |
| WCF-CL01 | TD 1.1 Recommendation 2023-12-05; 16 bundled TD vectors (corpus revision 1.1.0) | Not exhaustive TD semantics or normative assertion coverage |
| WCF-CL02 | TD 1.1 section 9; 8 bundled Thing Model vectors (corpus revision 1.1.0) | No derivation, remote reference resolution or complete Thing Model conformance |
| WCF-CL03 | WCF.01 target protocol 1.0 and schema revision 1.0 | Cross-implementation interoperability needs independent target evidence |
| WCF-CL04 | Sorted-key deterministic JSON and SHA-256 evidence | Not RFC 8785 JCS; byte stability is tied to the recorded encoder/runtime cohort |
| WCF-CL05 | Discovery Recommendation 2023-12-05 is reserved provenance | No bundled Discovery corpus or Discovery conformance claim exists |
| WCF-CL06 | Bounded subprocess execution | No OS isolation, descendant termination guarantee or trusted hardware attestation |

Authoritative source URLs and sections belong in
`docs/packages/wotex-conformance/provenance/standards.md`
and each claim. A profile label such as `certification` or `live_transport` is a
classification, not evidence that this package performs that activity.

| Claim dimension | Current status | Promotion evidence |
| --- | --- | --- |
| Value support | Claim, expectation, vector, result and report values follow WCF.01 and bundled schemas | C01/02 schema, digest and malformed-vector matrix |
| Operation support | Local corpus execution and bounded external target protocol only | C03/04 success, mismatch, unsupported, failure and isolation vectors |
| Independent interoperability | Not established | C03 independently implemented target against exact archive |
| Profile conformance | Not established; corpus rows are bounded assertions | Separately reviewed revision-pinned profile corpus and subject evidence |
| External certification | None; runner output is not certification | Artifact from an external certification authority |

## Independently implementable work

| ID | Prerequisites | Deliverable | Executable acceptance |
| --- | --- | --- | --- |
| WCF-C01 | WCF.01 | Assertion inventory for the exact existing TD/TM corpus, pairing every vector with normative section and declared exclusions | Corpus loads with verified digests; schema/constructor tests accept all valid fixtures and reject malformed/mismatched manifests; every claimed assertion has a traceable vector |
| WCF-C02 | WCF-C01 | Expanded TD/TM vectors only for already accepted value operations; each added assertion includes source clause, positive/negative input and independent expected result | Existing and new targets receive no expectation material; wrong outputs fail, unsupported stays unsupported; vectors are schema-valid and manifest digests reproducible |
| WCF-C03 | WCF.01 | Archive-only minimal consumer and independently implemented external target fixture | Exact unpacked archive compiles without subject packages; observed/pass, mismatch/fail, unsupported, timeout and malformed response each produce their distinct contract outcome |
| WCF-C04 | WCF-C03 | Cross-run isolation and lifecycle proof | Concurrent target runs cannot exchange output; timeout during write/read cleans up ports; oversized/late/partial responses and target crashes remain bounded; changed artifact never starts target |
| WCF-C05 | WCF-C01 | Decision contract for any proposed Discovery corpus; keep it separate from existing TD/TM evidence | Before implementation, enumerate exact Discovery operations/assertions, source sections, consumer fixture obligations and unsupported profiles; no Discovery claim until vectors and independent target pass |
| WCF-C06 | WCF-C02, WCF-C03, WCF-C04 | Release evidence and explicit runtime compatibility cohort | Confirm the matching Elixir `~> 1.18` CLAUDE/Mix requirement, test the accepted minimum/current cohort cleanly, validate all ten schemas and publish no stronger claim than tested |
| WCF-C07 | None | Package inputs that ship no Markdown documentation, governance or agent files and exclude machine-local execution records | The `bin/check_archive.exs` archive listing contains no `docs/` or `tasks/` path segment, including a local sentinel under the root `docs/tasks/local/wotex-conformance/` |

C02 expands data/evidence, not the target execution protocol. New operations,
expectation operators or claim semantics require a revised WCF.01 contract before
code. C05 is a scope decision lane, not permission to invent Discovery behavior.
Corpus revisions, manifest hashes, schema mirrors and fixtures change atomically.
An independent target must not calculate expected answers using runner internals.

## Gates and evidence

- `repository_green`: the package gate `WOTEX_PATH_DEPS=1 mix check
  --no-retry`, run from `packages/wotex-conformance` (from the repository
  root: `mix pkg wotex-conformance check --no-retry`) and mirrored by the
  package's CI lane: clean-build warnings-as-errors compilation, locked and
  unused-dependency checks, format, dependency and Hex audits, strict Credo,
  Doctor, docs with warnings as errors, all tests with coverage, Dialyzer,
  schema mirror checks, the boundary scan, the archive and application-free
  checks and `git diff --check`. Record exact commit/runtime/dependencies; incremental
  compilation is not clean proof.
- `archive_consumer_green`: `bin/check_archive.exs`, run by the same gate and
  CI lane, builds and inspects one exact Hex archive, verifies license,
  schema/corpus assets and dependency allowlist, then runs C03 using only the
  archive and declared dependencies. No source checkout or subject dependency.
- `reference_consumer_green`: C03/C04 independent target and isolation evidence
  against that exact archive, with expected outcomes kept exclusively runner-side.
- `public_release_candidate`: preceding gates, C01/C02/C06, provenance and
  claim-ledger review. Remaining excluded claims are visible. No publication,
  tag or push is authorized by reaching the gate.
- `stable_api_candidate`: all preceding proof plus review of constructor fields,
  schemas, target protocol, canonicalization, result statuses and report identity;
  an unresolved advertised compatibility promise prevents admission.

Evidence records commit, archive SHA-256, corpus/manifest digest, protocol,
runtime and dependency cohort, commands and exit codes. Passing a different
corpus or subject cannot discharge a claim for the selected artifact.

Fresh checkout procedure: clone the repository; read the root `CLAUDE.md`,
`packages/wotex-conformance/CLAUDE.md`, this plan and WCF.01; run `mix setup`
from the repository root, use `mix pkg wotex-conformance test` and
`mix check.fast --package wotex-conformance` for the fast loop, and run
`mix pkg wotex-conformance check --no-retry` before recording
`repository_green` or `archive_consumer_green`.

## Local tracker contract

Use only the ignored root `docs/tasks/local/wotex-conformance/`. Package
inputs ship no Markdown documentation and structurally exclude that path;
every candidate archive still proves WCF-C07 because Git ignore is not Hex
exclusion. Schema: `schema_version: "1.0.0"`,
`plan_id: WCF-C`, `plan_revision: "1.2.0"`, `work_items` with `id`,
`state` (`queued|active|blocked|verified`), `prerequisites`, `evidence`
(source_commit, archive_sha256, corpus_digest, runtime, dependency_cohort,
command, exit_code), and `remaining_claims`. Unavailable proof is explicit null.
Do not put rolling task state, machine paths or worker histories in this plan.
