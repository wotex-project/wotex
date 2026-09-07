---
spec:
  id: WCF.01
  title: Subject-independent conformance runner
  status: accepted
  version: 1.1.0
  owner: wotex-conformance
  updated: 2026-09-07
---

# WCF.01: Subject-independent conformance runner

## Authority and scope

This specification owns:

- the claim, subject, vector, target request, target response, result, corpus,
  and report schemas;
- immutable subject-archive and vector-corpus verification;
- isolation of tested subjects from the production dependency graph;
- runner-side result evaluation and five-state classification;
- deterministic canonical encoding and evidence digests; and
- the public vocabulary used to express W3C Web of Things evidence.

It does not own a Thing Description parser, a protocol binding, a Thing
Description Directory, transport sessions, credentials, authorization,
certification, persistence, or deployment policy. It does not grant a W3C
conformance or interoperability designation.

## Normative language

`MUST`, `MUST NOT`, `SHOULD`, and `MAY` describe requirements of this project
contract. W3C requirements are attributed only through exact cited standards
revisions; project requirements do not become W3C requirements by association.

## Terminology

- **Subject**: the exact immutable artifact or public interface being tested.
- **Claim**: one bounded behavior at one revision and evidence profile.
- **Vector**: a versioned input plus a runner-owned expectation and provenance.
- **Corpus**: a content-addressed set of vectors and one manifest.
- **Target adapter**: an external executable translating the neutral protocol to
  the subject interface.
- **Observation**: the normalized JSON-compatible value returned by the target.
- **Result**: the runner classification for one vector.
- **Report**: the content-addressed evidence for one subject/corpus execution.

W3C WoT terms retain their standard meanings: a Thing Description describes a
Thing and its Property, Action, and Event interaction affordances, Forms,
security metadata, and DataSchemas.

## Invariants

1. Production code MUST NOT compile-depend on the subject package.
2. The subject artifact digest MUST be verified before any target invocation.
3. The expected value, expected digest, vector digest, and vector provenance
   MUST NOT be sent to the target.
4. The target MUST NOT classify pass or fail.
5. Target output MUST be bounded, valid protocol JSON, and tied to the requested
   vector ID.
6. Reports MUST retain actual values only as SHA-256 digests.
7. Target diagnostic data MUST be bounded identifiers, not free-form text.
8. Vector and report order MUST be stable by vector ID.
9. Loading the library MUST start no process and perform no I/O.
10. The library MUST own no database, background job, credential, network
    client, or global application configuration.

## Versioned schemas

Schema revision `1.0` is represented by:

- `priv/schemas/claim.schema.json`;
- `priv/schemas/corpus.schema.json`;
- `priv/schemas/subject.schema.json`;
- `priv/schemas/vector.schema.json`;
- `priv/schemas/document-input.schema.json`;
- `priv/schemas/observation.schema.json`;
- `priv/schemas/target-request.schema.json`;
- `priv/schemas/target-response.schema.json`;
- `priv/schemas/result.schema.json`; and
- `priv/schemas/report.schema.json`.

The Elixir constructors are the executable validation authority for this
release. JSON Schemas are portable mirrors. A disagreement is a release blocker
and requires both forms to be corrected in one change.

## Claim contract

A claim contains:

| Field | Contract |
|---|---|
| `id` | stable project claim identifier |
| `revision` | exact claim contract revision |
| `operation` | normalized operation exercised by the adapter |
| `evidence_profile` | bounded evidence category |
| `standard` | identifier, publication revision, HTTPS source, and section |
| `assertions` | bounded assertion identifiers |
| `tags` | non-authoritative selection metadata |

Evidence profiles are `value`, `codec`, `runtime`, `binding`, `directory`,
`simulator`, `live_transport`, `hardware`, `certification`, and `production`.
Evidence from one profile does not substitute for another. In particular, a
synthetic value vector does not prove a live transport or hardware claim.

A claim is intentionally narrow. “Supports HTTP,” “supports MQTT,” or
“conforms to Thing Description 1.1” is not a valid claim without exact
operations, directions, profiles, standards revisions, and applicable vectors.

## Subject contract

The reportable subject contains:

- stable ID;
- subject version;
- lowercase `sha256:<hex>` artifact digest; and
- interface kind and revision plus bounded public metadata.

The subject value never contains a local path, credential, raw endpoint secret,
or mutable branch reference. The external target configuration owns local
execution paths and is excluded from the report.

An interface may represent an archive adapter or a public API adapter. A public
API subject still needs an immutable artifact describing the exact deployed
build and interface revision; a mutable endpoint alone is insufficient
identity.

Artifact verification MUST enforce its byte budget during every streaming
read, including after a file grows. It MAY read one additional byte to detect
that the budget was exceeded, but MUST NOT hash that over-budget chunk or
continue reading. Successful verification MUST report the actual number of
bytes hashed, rather than a size observed before opening the file. Empty and
exact-budget regular files remain valid when their digests match.

Verification attests to the bytes read. The consumer MUST prevent mutation or
path replacement through verification and subsequent execution; digest checking
does not itself provide an immutable file handle, a filesystem snapshot, or
operating-system isolation.

## Vector and corpus contracts

A vector contains its identity, revision, claim, input, exact expectation,
provenance, tags, and content digest. Revision `1.0` supports only the `exact`
expectation operator. New comparison semantics require a protocol and schema
revision; a string flag cannot silently change equality.

A vector for a document operation MUST declare its input as an object with a
`document` object and a `projection` list of RFC 6901 JSON Pointers, and its
expectation value MUST be one normalized observation. The projection is
declared vector material: it travels to the target inside `vector.input`, so an
independent adapter can produce the expected observation from the request alone,
without knowing the vector identity or the expectation. Document operations are
`thing_description.parse`, `thing_description.validate`, `thing_model.parse`,
and `thing_model.validate`.

The vector digest is the canonical digest of every vector field except
`digest`. The corpus digest is the canonical digest of the schema version,
corpus ID, corpus revision, and the complete vector maps including their
digests.

`manifest.json` fixes each local JSON basename and vector digest. The loader
MUST reject:

- missing or empty manifests;
- unsupported schema revisions;
- absolute paths, subdirectories, or traversal;
- symbolic links and non-regular files;
- oversized manifests or vectors;
- duplicate files or vector IDs;
- mismatched manifest, embedded vector, or corpus digests; and
- invalid JSON-compatible values.

Corpus loading performs no remote retrieval. An air-gapped run uses the same
preloaded bytes and produces independently verifiable digests.

## Canonical JSON

Project canonical JSON revision `1.0` accepts JSON-compatible values only.
Object keys MUST be strings and are ordered by UTF-8 bytes. Arrays preserve
order. Encoding is compact. Numbers must be finite and use the selected JSON
encoder’s stable representation for the supported runtime cohort.

This canonical form is not an RFC 8785 claim. Changing string escaping, number
encoding, key order, accepted value types, or digest input requires a schema and
compatibility decision.

Digests use SHA-256 and lowercase `sha256:<hex>` representation.

## External target protocol

The target executable is invoked directly, not through a shell. One fresh
process handles one vector. It reads one canonical JSON request followed by a
newline from standard input, writes one JSON response to standard output, and
exits. Output and execution time are bounded.

One monotonic deadline MUST cover request encoding, process startup, request
submission and output collection. A busy target port MUST NOT suspend the
caller while writing its request; a rejected write is an infrastructure error.
The collector MUST check deadline exhaustion before consuming another queued
message, so a continuous output stream cannot reset or starve the deadline.
Every opened port MUST close on all return paths, including failed writes and
malformed output. Invalid request identity MUST be rejected before opening it.
These are cooperative runtime bounds, not hard-real-time scheduling guarantees.
Closing a port does not prove termination of arbitrary descendant OS processes;
that containment remains the consumer's responsibility.

The target is not an operating-system sandbox. A consumer MUST place untrusted
subjects in appropriate process, filesystem, network, and resource isolation.

### Request `1.0`

```json
{
  "protocol": "wotex.conformance.target",
  "protocol_version": "1.0",
  "subject": {
    "id": "example.thing-description",
    "version": "1.2.3",
    "artifact_digest": "sha256:<64 lowercase hex>",
    "interface": {"kind": "archive_adapter", "revision": "1"}
  },
  "claim": {
    "id": "w3c.wot.td11.parse",
    "revision": "1.0.0",
    "operation": "thing_description.parse",
    "evidence_profile": "value",
    "standard": {
      "identifier": "w3c.wot.thing-description",
      "revision": "2023-12-05",
      "source": "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/",
      "section": "5.3.1"
    },
    "assertions": ["context_recognized"],
    "tags": ["thing-description-1.1"]
  },
  "vector": {
    "id": "td11.parse.minimal",
    "revision": "1.0.0",
    "input": {
      "document": {"@context": "https://www.w3.org/2022/wot/td/v1.1", "title": "Minimal Thing"},
      "projection": ["/title"]
    }
  },
  "context": {
    "corpus": {"id": "example", "revision": "1", "digest": "sha256:<64 lowercase hex>"},
    "generated_at": "2026-09-02T12:00:00Z",
    "environment": {"runtime": "otp-28"}
  }
}
```

The request contains no `expectation`, `expected_digest`, `vector_digest`, or
provenance field.

### Observed response `1.0`

```json
{
  "protocol": "wotex.conformance.target",
  "protocol_version": "1.0",
  "vector_id": "td11.parse.minimal",
  "outcome": "observed",
  "actual": {},
  "codes": []
}
```

### Unsupported response `1.0`

```json
{
  "protocol": "wotex.conformance.target",
  "protocol_version": "1.0",
  "vector_id": "td11.parse.minimal",
  "outcome": "unsupported",
  "codes": ["operation_not_implemented"]
}
```

An unsupported response MUST omit `actual`. Codes are stable bounded
identifiers. Free-form messages, stack traces, raw output, and credentials are
not protocol fields.

### Normalized observations

For every document operation the `actual` value MUST be one of exactly two
shapes.

Accepted:

```json
{"accepted": true, "document": {"/title": "Minimal Thing"}}
```

Rejected:

```json
{
  "accepted": false,
  "errors": [{"code": "schema_violation", "phase": "schema", "path": "/title"}]
}
```

Requirements:

1. With a non-empty declared projection, `document` maps each declared pointer
   that resolves in the accepted document to that member value. A declared
   pointer that does not resolve MUST be omitted, so absence is observable
   evidence rather than a silent pass.
2. With an empty projection, `document` is the complete accepted document as
   the subject normalized it.
3. Pointers are RFC 6901: array members are addressed by index, `~0` decodes to
   `~`, and `~1` decodes to `/`.
4. Every rejection error object has exactly `code`, `phase`, and `path`.
   `code` and `phase` are lowercase bounded identifiers; `path` is a JSON
   Pointer rooted at `/`. Errors MUST be unique and sorted ascending by `path`
   and then `code`.
5. Messages, details, raw values, exception text, and counts are not
   observation members. Only codes, phases, and paths are stable enough to
   compare across subject revisions.
6. The adapter MUST derive the observation from the operation, the declared
   document, and the declared projection. It MUST NOT branch on the vector
   identity.

An observation that does not satisfy the normalized shape of its operation is a
protocol failure and produces `infrastructure_error`, never `fail`. Operations
outside this list carry no normalized shape at this revision and are compared
as bounded JSON values.

The external target receives a scrubbed process environment. The consumer may
supply bounded non-sensitive variables explicitly. Credentials belong in an
out-of-band capability available inside the consumer-owned isolation boundary,
not in vector or report values.

## Evaluation and result classification

| Status | Meaning |
|---|---|
| `pass` | target returned an observation whose canonical digest equals the runner-owned expected digest |
| `fail` | target returned a valid observation that does not match the expectation |
| `unsupported` | target explicitly reported that it does not implement the operation |
| `not_run` | runner selection excluded the vector before target invocation |
| `infrastructure_error` | artifact, process, timeout, output bound, protocol, or callback mechanics prevented evaluation |

An `unsupported` result is neither pass nor infrastructure failure. A consumer
may separately require support for a release gate. `not_run` cannot satisfy a
claim. Infrastructure failure does not establish subject failure.

Each result records claim and vector revisions, standard revision, vector and
expected digests, optional actual digest, status, stable code, duration, and a
digest covering that evidence value.

## Report contract

A report contains:

- report schema version;
- deterministic run ID;
- reportable subject identity;
- corpus digest;
- caller-supplied generation time;
- bounded non-sensitive environment metadata;
- vector-ID-sorted results;
- counts for all five statuses, including zero counts; and
- report digest.

The run ID is the canonical digest of subject identity, corpus digest,
generation time, and environment. The report digest covers every report field
except itself. The generation time is required input; the runner does not hide
a wall-clock read in report construction.

Environment keys associated with passwords, secrets, tokens, credentials, or
private keys are rejected recursively. Reports do not contain target stdout,
raw observations, local paths, or exception messages.

## Failure behavior

- Artifact mismatch produces `infrastructure_error` for selected vectors and
  starts no target.
- A non-zero target exit, timeout, oversized output, malformed JSON, wrong
  protocol version, wrong vector ID, invalid outcome, or invalid observation
  produces `infrastructure_error` for that vector.
- A valid non-matching observation produces `fail`.
- Selection produces `not_run` without invoking the target.
- Invalid corpus, subject, target configuration, environment, or runner options
  returns a typed construction error and produces no misleading report.
- Public tagged-return APIs reject malformed, duplicated, and unknown keyword
  options before reading any option value.

### Structured errors

Every rejection returns one structured error with `code`, `phase`, `path`,
`message`, and `details`.

| Field | Contract |
|---|---|
| `code` | stable atom identifying the rejected contract |
| `phase` | contract stage that rejected the value |
| `path` | RFC 6901 JSON Pointer string rooted at `/`, or `nil` when no single member is implicated |
| `message` | bounded static text; improvable, never a matching interface |
| `details` | bounded identifiers and numeric limits only |

Phases are `input`, `value`, `limits`, `claim`, `vector`, `subject`, `corpus`,
`artifact`, `target`, `protocol`, `result`, `report`, `environment`, and
`runner`. `code`, `phase`, and `path` are the matching interface. Pointer
segments escape `~` as `~0` and `/` as `~1`.

Error values do not echo raw target output or environment values.

### Resource limits

Bounded JSON admission uses one limit vocabulary: `max_bytes`, `max_depth`,
`max_nodes`, `max_string_bytes`, and `max_collection_size`. `max_nodes` counts
every JSON value including containers; `max_collection_size` bounds the members
of one object or array. An invalid limit is rejected with `invalid_limit`
rather than silently replaced by a default, so a caller cannot believe a bound
applies when it does not.

### Constructors

Contract values with map-shaped external input are built with `from_map/1`;
`new/1` remains a documented alias. Keyword configuration uses `new/1` with
explicit, closed option keys.

## Process and application behavior

The library defines no application callback. The runner owns no long-lived
process and returns no hidden child specification. Each external port exists
only for one explicit vector invocation and is closed on completion, timeout,
or output-limit failure.

No target is invoked while loading modules, reading documentation, starting the
dependency application, or loading a corpus.

## Continuum behavior

Corpus loading is local.

## Security requirements

- Use absolute executable and artifact paths.
- Invoke no shell.
- Require exactly one complete archive placeholder argument.
- Verify the archive before process creation.
- Scrub inherited environment variables.
- Bound arguments, environment, time, output, JSON depth, JSON entries, and
  string bytes.
- Reject symbolic-link artifacts and corpus entries.
- Never extract the subject archive in this library.
- Never return raw target stdout or observations in evidence.
- Never treat a target-supplied status as pass or fail.

The consumer remains responsible for operating-system isolation, executable
trust, network egress, archive format safety, and external endpoint policy.

## Acceptance evidence

The repository is standalone-green only when all of the following pass against
one commit and package archive:

1. deterministic constructor, canonicalization, digest, corpus, result, and
   report tests;
2. external archive adapter pass, fail, unsupported, not-run, wrong-vector,
   malformed-response, timeout, non-zero-exit, and output-limit tests;
3. proof that target requests omit expectations and provenance;
4. proof that archive digest mismatch starts no target;
5. proof that `Application.spec(:wotex_conformance, :mod)` is empty;
6. production dependency allowlist and no path dependencies;
7. documentation and package-archive builds; and
8. tracked-text review for consumer names, internal paths, secrets, and copied
   non-public material.

## Standards sources

- W3C Web of Things Thing Description 1.1, Recommendation 5 December 2023:
  https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/
- W3C Web of Things Discovery, Recommendation 5 December 2023:
  https://www.w3.org/TR/2023/REC-wot-discovery-20231205/

The bundled Thing Description 1.1 corpus contains fourteen project-authored,
claim-scoped vectors covering minimal structure, affordance categories,
extension preservation, multilingual metadata, security definition selection,
Property, Action, Event and Thing-level Forms, and five negative validation
cases, including Thing-level, Form-level and `ComboSecurityScheme` reference
integrity.

The independent Thing Model 1.1 corpus contains six project-authored vectors:
four positive parse observations for declaration, extension, optional and
placeholder values, and composition references; plus negative declaration
observations for the model type and TD 1.1 context. Its operations are
`thing_model.parse` and `thing_model.validate`; passing it makes no claim about
Thing Model derivation, remote reference resolution, or model registries.

Every bundled vector declares a projection and expects one normalized
observation. Negative vectors expect the bounded rejection identifiers a
Thing Description or Thing Model implementation emits for the cited clause,
such as `schema_violation`, `undefined_security_reference`, and
`unsupported_context`. A code that no implementation emits is not evidence.

Both corpora are synthetic evidence derived from cited semantics. They copy no
W3C schema or normative text and carry no W3C certification claim.
