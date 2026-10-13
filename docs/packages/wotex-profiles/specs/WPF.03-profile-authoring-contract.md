# WPF.03 — Consumer-owned profile authoring and validation

Version: 0.1.2. Updated: 2026-10-13. Status: accepted target.
Implementation: bounded v1 export/finalization/validation and CLI adapters.
Evidence: focused suites, independent identity vectors and pinned structural cells;
exact archive execution is retained separately.

## Scope and inherited behavior

A consumer obtains a machine-readable description of supported profile
mechanics, authors a bounded draft, finalizes its identities and receives
deterministic validation results. Manual editors, CI, imports and AI authors
use the same mechanics. WoTEx owns no model catalogue, generator/provider,
source downloader, approval decision, credentials or durable state.

[WPF.01](WPF.01-external-profile-language.md) owns closed profile/definition
fields, exact rational conversions, URI/version references, semantic identities
and reader Limits. [WPF.02](WPF.02-profile-interpretation.md) owns explicitly
supplied installed bindings/contracts, static checking, capture correspondence
and interpretation. Bindings come from the trusted consumer, never the draft.
Core owns TD/TM/DataSchema; a WPF document is a package extension, not a W3C TD.

Consumers ship selected public model templates in their own release or retain
private drafts in their own custody. Cross-consumer sharing is an explicit
data import. Reader loading cannot discover, scan, fetch or install collections.

All public seams below are exports under Wotex.Profiles. Native
structs/maps are revalidated. No function reads files, clocks, environment,
networks, loaded providers or ambient registries. Release artifacts, schemas,
bindings, contracts, bytes and optional capture are explicit immutable inputs.

## Closed values and work bounds

| Input | Representation and bounds |
| --- | --- |
| Bindings / Contracts | WPF.02 revalidated values and exact installed references; selected set only |
| Authoring limits | Exactly reader (WPF.01 Limits), max_bundle_bytes, max_diagnostics, max_report_bytes, max_check_steps; all required positive integers |
| Authoring ceilings | Bundle 1048576 bytes including all definitions; diagnostics 256; encoded report 65536 bytes; 1000000 check steps; reader limits also apply per object/closure |
| Release artifacts | Exactly producer, schemas, semantic_rules; producer is one WPF Reference to an installed release identity |
| Schemas | Exactly profile, definition, draft, bundle; each a supplied bounded JSON Schema object; full release artifacts ≤2097152 encoded bytes, depth 32, 50000 nodes |
| Semantic rules | 1–128 objects exactly id and summary; id is ASCII [A-Z0-9._-]{1,64}, unique/sorted; summary ≤512 UTF-8 bytes, no controls |
| Candidate | Original UTF-8 JSON bytes; duplicate/unknown fields and resource excess reject before expansion |
| Optional capture | Explicit absent or the WPF.02 Capture supplied by the consumer; no draft-authored capture |

Resource limits are admission ceilings, not throughput claims. Missing/invalid
limits refuse. Parsing, finalization, reference traversal and validation share
the admitted node/closure budgets; no exponential expression language or
recursive remote schema is admitted. Library validation has no owned process,
timeout, retry loop or retained state; a host can run it under its own deadline.
Each WPF.03 schema assertion/node visit and finalizer reference expansion
consumes one check step, including alternative branches. Exhaustion returns
input_limit, never a partial compatible result. Memoization does not remove a
visited node's accounting; independent vectors freeze exact count boundaries.
WPF.01/02 calls retain their separately bounded reader/numeric work; this counter
does not claim to meter hidden instructions inside another public function.

## Requirements

**WPF03-01 — Contract export.** Contract.export/4 takes Bindings,
Contracts, authoring limits and release artifacts, returning a revalidated
Contract or typed error. Its document contains exactly format, producer,
schemas, semantic_rules, bindings, contracts and limits. Format is
wotex.profile.authoring-contract@1. Bindings use complete WPF.02 normalized
registrations sorted by id/version; contracts use exact sorted references.
The complete exported document also fits 2097152 bytes/depth 32/50000 nodes,
including bindings; enforce that bound before encoding/hash copies. Excess
returns input_limit. No live capture values, routes, credentials, consumer grants
or instance data are exported. A supplied release identity is an assertion; consumers must bind
it to their actual installed archive and matching schemas/rules.

Contract identity is SHA-256 of UTF-8 wotex.profile.authoring-contract@1 plus
newline and core deterministic sorted-key JSON of the complete document.
Any schema, rule, binding, contract or limit change changes this identity.
Contract.encode/1 returns those document bytes; identity is returned separately,
never a self-hashed field. Release artifacts are inert data, not executable
callbacks or paths. Artifacts.current/0 returns the installed producer's
compile-time literal release identity, four schemas and rule table without I/O.
Export/parse compare schemas/rules/producer identity to that exact installed
artifact set before any schema execution; substitutions return invalid_contract.
Bindings/contracts/limits remain explicit trusted consumer inputs.
Contract.parse/1 admits the bounded serialized document, reconstructs
its native values and recomputes its identity; parsing grants no trust in the
supplied binding registrations or deployment. Runtime admission requires the
consumer's current Contract.export/4 identity, not a draft-supplied contract. An incompatible artifact/registration refuses invalid_contract.

The first structural export declares JSON Schema draft-07. Its closed keyword
set is $schema, $id, $ref, definitions, type, properties, required,
additionalProperties, items, minItems, maxItems, uniqueItems, enum, const,
anyOf, oneOf, allOf, not, minimum, maximum, exclusiveMinimum, exclusiveMaximum,
multipleOf, minLength, maxLength, minProperties, maxProperties, propertyNames,
pattern, title, description and examples.
Alternatives have at most 16 branches. References use only fragment-local
JSON pointers, with no remote resolution, cycles or custom keyword execution.
Patterns are the exact installed schema artifact's finite ASCII grammar
patterns, verified by artifact identity before execution; arbitrary caller or
candidate regular expressions are not executed. Metadata keywords are inert; $id never authorizes a fetch.
Freeze positive/negative schemas/vectors and the rule table in release artifacts
before implementation. Profile value
DataSchema's smaller WPF.01 subset remains distinct from this authoring schema.
The export MUST identify all cross-field/identity/mechanical obligations through
semantic_rules; structural success never implies those rules passed. Consumers
may narrow a provider's generation schema only as an authoring aid. Unsupported
provider features cannot narrow or replace the authoritative validator.

**WPF03-02 — Draft and finalized bundle.** A finalized bundle contains exactly
format, profile and definitions. Format is wotex.profile.bundle@1; profile is
one WPF.01 Profile, definitions are the complete selected WPF.01 descriptors,
unique/sorted by id/version. Definitions omitted from the reachable semantic
closure refuse; installed contract references are resolved only from Contract.
Bindings, credentials and operational TD instances are never bundled.

A draft has the same three fields with format wotex.profile.draft@1. At precisely
profile.channels[].semantic, profile.requires[] and definitions[].requires[],
an author may use an exact WPF Reference or a local reference consisting of
exactly local, whose value is exactly id and version under WPF.01. A local
reference must identify one included definition. All other references,
including binding and behavior/codec references, remain exact installed WPF
References. No other field permits omission, an unresolved placeholder,
expression, template or generated module. Definitions carry their ordinary
WPF.01 IDs/versions; there is no second catalogue key space.

Draft.finalize/2 takes original draft bytes and Contract. It validates
bounds/closed draft shape, resolves the definition DAG, normalizes sets in the
WPF.01 order, computes each definition's WPF.01 semantic identity and substitutes
only local references. It verifies every supplied exact hash; it never repairs
a forged hash or silently replaces an external version. Missing, duplicate,
cyclic or conflicting closure refuses. Unreachable included definitions refuse
invalid_input rather than inflating an export or hiding a dependency.

Success is a Finalized value containing exactly bundle_bytes, draft_sha256,
bundle_sha256 and contract_sha256. Bundle bytes are core deterministic JSON;
draft/bundle hashes are SHA-256 of the corresponding exact byte strings.
Finalization computes identities and ordering only. It cannot guess model,
units, scale, byte order, invalid sentinels, protocol support or missing evidence.
It changes neither grants nor current observations. Failure returns a bounded
WPF03-03 invalid report when a bounded candidate is available; invalid API
arguments/resource excess return a typed Error before a result is constructed.

**WPF03-03 — Validation and diagnostics.** Validation.check/3 takes
bundle bytes, Contract and optional Capture. It runs byte/shape checks, WPF
semantic/reference checks, WPF.02 Compiler.check/3 against the explicit installed
closure, then Compiler.compile/4 only if Capture was supplied. No check starts
a decoder/transport, performs device I/O or writes state. Finalization success
does not substitute for this validation step.

Success returns a Report, including invalid dispositions. Exactly its fields
are format (wotex.profile.validation-report@1), contract_sha256,
candidate_sha256, disposition, capture_status, diagnostics and truncated.
Candidate identity is SHA-256 of original checked bundle bytes. Disposition is
invalid or compatible. Compatible means only that all applicable deterministic
checks passed against the supplied contract. Capture_status is not_supplied,
not_checked, matched or mismatch: not_supplied when absent; not_checked when an
earlier stage prevented a supplied capture check; mismatch on a failed capture
check; matched only after the supplied capture passed. Neither status proves
authenticity, model truth, current deployment approval or physical qualification.

Each diagnostic contains exactly phase, code, instance_path, rule_id and repair.
Phase is syntax, shape, semantic, binding or capture. Code is a WPF.01 Error
code. Instance_path is an RFC 6901 pointer ≤512 bytes constructed only from
contract-known field names and array indexes; unknown supplied keys report
their known parent. Rule_id names the exported trusted semantic/structural rule.
Repair is edit_candidate, supply_reference, install_mechanic, refresh_basis or
provide_capture. No raw values, foreign key names, document passages, callback
exceptions, filesystem paths or credentials enter diagnostics.

Dependent phases stop at the first failing phase; independent errors within
that phase may be collected. Sort by phase order above, pointer segment order
(indexes numerically, names by UTF-8 bytes), then rule_id/code. Retain the prefix
within both report limits and mark truncated if errors were omitted. An invalid
report always retains at least its first diagnostic; an insufficient budget
for that report returns report_limit. A compatible report has no diagnostics
and truncated=false. Partial checking cannot report compatible.

**WPF03-04 — Shared validation and compatibility.** Authoring, import, CI and
runtime use WPF.01–03 public mechanics and the same semantic rules. CLI/editor
adapters handle input/output outside these pure functions; they cannot implement
a weaker parser or turn a validation flag into approval. A CLI must supply an
explicit contract file/bytes and candidate, emit a bounded JSON report, and
exit 0 for compatible, 1 for invalid, 2 for API/contract/resource/I/O failure.
No network, install, source scan or missing-contract fallback is allowed.
CLI/runtime output parity vectors are an implementation-entry obligation.

A mechanically valid selector/scale can still describe the wrong hardware.
A compatible report cannot detect that fact without independent model evidence.
Consumers retain original draft, finalized bundle, exact contract and review
basis separately. Extracted canonical profile/definition files are newly derived
artifacts; their raw digests are not the digest of a claimed original substring.
A consumer requiring original source bytes must supply/retain those explicitly.
Every admission/activation rechecks current installed binding/producer, actual
capture, accepted semantics and consumer authority. A report against a replaced
contract is historical evidence, never current admission. Cross-consumer import
reruns local validation and review; exported approval is never transferable.

**WPF03-05 — Author independence.** A consumer can feed its exact Contract,
selected public examples and separately approved source passages to a human
or AI author. WoTEx has no model/provider dependency. A generator is allowed
only to produce candidate data; its score, prose, tool call or fixture output
cannot install mechanics, accept source truth, enroll a Thing or authorize an
Action. Unknown required source facts remain unresolved in the consumer's
draft record and prevent admission; they are not guessed defaults in WPF.

## Failure, continuation and implementation entry

Repeated bytes/contract/capture yield identical results. Errors extend WPF.01
with invalid_contract and report_limit; all existing refusal meanings remain.
No retry or continuation exists inside the library. Cancellation/restart of
a consumer draft changes no active profile; the consumer retains or abandons
its immutable candidate under its own custody policy. Changed source, contract,
capture or policy requires a new validation/review basis.

Before implementation freeze the four schemas, rule table, planned public value
shapes, CLI adapter contract and independent finalization/diagnostic vectors in
the prospective package's priv/schemas and priv/vectors. Pin the exact independent
draft-07 test subset and compatible notice from the JSON Schema Test Suite.
No schema/compiler copy is placed in a consumer. The four frozen schemas,
rule table, native value contracts and independent identity/diagnostic fixtures
are retained in this package. Source implementation and bounded tests do not
establish current consumer admission or physical qualification.

## Acceptance obligations

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WPF03-T1 | 01, 04–05 | Two archive consumers export independent bindings/limits and author unseen model/quantity data; reader has no model enum or consumer database | Archive/offline |
| WPF03-T2 | 01, 04 | Installed schema/rule successor or changed binding/limit changes identity; forged artifact bytes return invalid_contract; old admission refuses | Independent encoder and consumer race |
| WPF03-T3 | 01–03 | At/above each byte/node/closure/report limit, duplicate/unknown fields and untrusted native structs | Bounded refusal before I/O |
| WPF03-T4 | 02 | Reverse DAG/order, missing/cyclic local ref, forged exact hash and unreachable definition | Independent semantic-hash oracle; no guess/repair |
| WPF03-T5 | 03–04 | Schema-valid wrong reference/unit/unsupported selector and binding contract | Semantic/binding refusal, never compatible from schema alone |
| WPF03-T6 | 03 | Multiple errors, huge foreign key/path/secret and report truncation | Exact sorted safe report/CLI parity; invalid retained |
| WPF03-T7 | 01, 05 | Provider lacks an authoring keyword or emits unknown executable behavior | Local validator still runs; unsupported mechanic refuses |
| WPF03-T8 | 03–04 | Absent, matching, mismatching or obsolete capture/installed basis | Truthful status; consumer rejects stale active use |
| WPF03-T9 | 01–05 | Manual and scripted generator produce same draft; docs include an instruction to install/run code | Same bounded result; no provider/network/dispatch required |

All cases remain obligations. Consumer source/model correctness and actual
physical observations are additional evidence owned by that consumer.

## Sources and decisions

The [research decision](https://github.com/wotex-project/wotex/blob/main/docs/architecture/consumer-profile-authoring-research.md)
pins the inspected standards/research and explains why consumer ownership,
schema-plus-semantic validation and optional generation were chosen. Draft-07
is a declared authoring serialization baseline, not a complete validator or
provider conformance claim. No AI provider is selected by this contract.


## Executable authoring freeze

Authoring Limits is a native value with exactly data; data is the five-field
map above. Contract has exactly data and sha256; data is its seven-field export.
Contract.new/1 revalidates a native Contract by rebuilding export and comparing
its supplied identity; a mismatch returns invalid_contract. Contract.encode/1
and identity/1 use that same revalidation. Serialized/native contracts compare
the entire producer/schema/rule artifact set with Artifacts.current/0 before
schema execution. Native reconstruction never establishes source authenticity.

Artifacts.current/0 returns producer, schemas and semantic_rules as compile-time
literal data. Producer id is urn:wotex:profiles:authoring, version 1.0.0, and
sha256 is the hash of wotex.profile.authoring-release@1 plus newline and core
sorted-key JSON of the four schemas and rule table. This semantic release
identity is separate from the exact source/archive digest retained by a consumer.
The four acyclic fragment-only schemas are frozen in priv/authoring; the
DataSchema description graph is finitely unrolled to eight levels. Existing
reader envelope/semantic checks remain authoritative; unrolling adds no reader
operator. The rule table covers source syntax, closed shape, value grammar,
exact references, DAG closure, installed mechanics and capture basis.

Finalized has exactly bundle_bytes, draft_sha256, bundle_sha256 and
contract_sha256. ValidationReport has exactly data; ValidationReport.to_map/2
and encode/2 revalidate safe report fields under the supplied Contract. Reports
are inert historical diagnostics, never current consumer admission. nil is the
only absent optional capture. Draft.finalize/2 returns a Finalized on success
or a ValidationReport with invalid disposition for an admitted invalid candidate;
API/contract/input/work/report resource failure returns Error. Validation.check/3
returns ValidationReport for both compatible and admitted invalid candidates.

The bounded shape evaluator consumes one step at entry to each schema node and
one per evaluated assertion keyword; local-reference traversal consumes one
additional step. Every alternative is evaluated, including branches that fail;
all visited steps count. Object properties use UTF-8 key order and arrays use
ascending indexes. The finalizer additionally spends one step for each first
definition visit and each exact/local reference expansion. Step exhaustion is
input_limit; all dependent stages stop. The separately bounded public reader
and compiler calls are not presented as metered instructions.

Structural diagnostics use rule INPUT_SHAPE, syntax SOURCE_SYNTAX, semantic
VALUE_GRAMMAR or EXACT_REFERENCES/DAG_CLOSURE as applicable, binding
INSTALLED_BINDING and capture CAPTURE_BASIS. The installed rule table is the
only source of rule identifiers. A pointer through additional/property-name
schemas reports the known parent; candidate keys never become pointer segments.
Diagnostics may collect independent structural failures; later dependent phases
stop at the first failure. Ordering/truncation follows WPF03-03. With supplied
capture, an earlier failure is not_checked; only a reached capture check can
produce matched/mismatch.

The CLI Mix task is mix wotex.profiles.validate --contract FILE --candidate FILE
with optional --capture FILE, and mix wotex.profiles.finalize --contract FILE
--candidate FILE --output FILE. Arguments are exact, duplicate/unknown/missing
arguments fail with exit 2. Adapters do bounded local file reads, invoke only
these public pure functions, and emit canonical JSON on stdout; they perform
no network or install. Finalize writes the derived bundle only after success.
Validation report exit meanings remain 0 compatible, 1 invalid and 2 failure.
CLI path/I/O errors emit only a fixed Error code, never a path or exception.

Independent draft-07 source is JSON Schema Test Suite revision
8568bcc477cc3aaeed5bc397c9c8648e631317fc. The selected files, exact digests and
MIT license are retained in test/support/draft7/manifest.json and LICENSE.
Only the declared bounded keyword cells are selected; this is not a complete
JSON Schema conformance claim. Byte/work boundaries, finalization identities,
report ordering and CLI parity require their own package vectors/tests.


The independent structural selection contains 462 test cells at the pinned
revision, with exact selected group/case indexes and upstream file digests in
the manifest. Unsupported keyword combinations and inputs outside the declared
numeric admission are not promoted to supported behavior. Resource limits fail
before a partial compatible result. A finalized bundle is checked in WPF.01
canonical set order; validation does not silently repair it. Finalization alone
normalizes a draft's declared set order while rejecting duplicates.


Executed contract/finalizer/validator, independent structural cells and actual
CLI archive correspondence is retained in
[the authoring milestone](../provenance/authoring-2026-10.md). Current consumer
admission and actual source/model qualification are outside that evidence.
