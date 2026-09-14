# Directory claim and compatibility matrix

This matrix reviews WTD.01 version 1.1.0 against the 0.1.0 public library
contract. It defines reusable evidence, not a release receipt. Its standards
baseline is the WoT Discovery Recommendation and Thing Description 1.1
Recommendation, both dated 2023-12-05, plus RFC 7396. The normative source
register is [Standards provenance](../provenance/w3c-sources.md).

Directory implements package-level values and operation mechanics. A passing
row does not establish an HTTP, SSE, RDF, search, or certification claim.
RFC 3339 evidence concerns registration timestamps. RFC 8288 is limited here
to the continuation arguments a transport host must carry; wire Link headers
and Problem Details remain outside the library.

## Evidence index

References below use `prefix:source marker`. Markers identify a named test or
a reusable `verify/2` scenario. The evidence contract test checks that every
reference resolves to its source; the full gate executes the tests. A source
marker is not itself proof that an assertion passes.

| Prefix | Source |
|---|---|
| D | `test/wotex/directory/directory_test.exs` |
| V | `test/wotex/directory/value_contract_test.exs` |
| S | `test/wotex/directory/service_test.exs` |
| G | `test/wotex/directory/registration_test.exs` |
| M | `test/wotex/directory/merge_patch_test.exs` |
| E | `test/wotex/directory/error_contract_test.exs` |
| B | `test/wotex/directory/robustness_test.exs` |
| N | `test/wotex/directory/event_test.exs` |
| C | `test/wotex/directory/compatibility_test.exs` |
| R | `test/support/wotex/directory/repository_contract.ex` |
| P | `test/support/wotex/directory/public_operation_contract.ex` |
| F | `test/support/wotex/directory/reference_consumer_contract.ex` |
| A | `bin/check_archive.exs` |
| L | `bin/archive_consumer.exs` |

R, P and F run against the independent Agent-map and ETS compare-and-swap
consumers. The archive check repeats them against the same unpacked Directory
and core archives and runs C there as well. Detailed race, callback and
interruption assertions are defined in the
[repository port evidence contract](repository-port-evidence.md).

## Bounded claim-to-test matrix

The first column names the owning WTD.01 clauses. Positive evidence covers an
accepted value or successful transition. Refusal evidence covers invalid,
denied, conflicting, expired or interrupted outcomes. For a non-goal, the
boundary assertion is the evidence; no invented successful operation applies.

| Clauses | Bounded claim | Positive evidence | Refusal or boundary evidence |
|---|---|---|---|
| 2, 5.1, 6 | Explicit service ports, validated bounds and consumer state | `S:requires every explicit port and a valid Introduction Thing Description`; `F:verify(:authority` | `S:rejects inverted, zero, and unknown service configuration`; `C:default bounds and caller-selected time` |
| 5.1, 9 | Only the core limit vocabulary controls TD admission | `S:accepts the core limit vocabulary and rejects every invalid limit` | `E:core limits bound admission before any repository write` |
| 5.2, 6.1, 6.2 | Opaque principal/auth/repository context separation | `S:constructs context values without interpreting opaque consumer state`; `R:verify(:isolation` | `F:verify(:isolation`; `B:every operation rejects malformed service, context, and options deterministically` |
| 2, 4, 7.1, 9 | Core TD validation and extension preservation | `F:verify(:lifecycle`; `D:owns Discovery registration input and emits an enriched Thing Description` | `E:rejects invalid core values and bounded merge patches without repository writes`; `D:rejects registration metadata without the Discovery context` |
| 5.3, 7.1 | Server times, unsigned TTL and TTL precedence | `G:assigns server times and gives ttl precedence over absolute expiry`; `G:accepts both exact unsigned 32-bit ttl endpoints` | `G:rejects client assignment to server fields and invalid ttl`; `E:registration rejects ambiguous out-of-band and enriched metadata` |
| 5.3, 6.3 | Absolute RFC 3339 time and refresh history | `G:accepts RFC 3339 offsets and normalizes absolute time`; `G:refresh preserves creation and recalculates relative expiry` | `G:reports clock regression deterministically`; `F:verify(:time_and_pages` |
| 5.3, 7.2, 7.6 | Return-only retrieval enrichment | `G:retrieved is return-only and expiry is inclusive`; `R:verify(:public_order` | `F:verify(:lifecycle`; `P:verify(:paging_expiry` |
| 5.4 | Entry identifier equality, positive version and valid state | `V:validates identifier equality, versions, registration type, and state` | `V:expired state is inactive independently of absolute expiry`; `B:constructors reject malformed values at each public seam` |
| 5.5, 5.6 | Mutation outcomes and all three lifecycle Event projections | `N:derives full creation data from a created registration`; `N:maps every successful update outcome to thing_updated`; `N:supports minimum Partial TD event data` | `N:deletion never exposes a removed Thing Description`; `N:rejects impossible mutation outcomes, malformed entries, and options`; `F:verify(:authority` |
| 5.7, 7.6 | Bounded listing, array/collection formats and opaque keyset | `V:constructs defaults and validates every public query bound`; `V:encodes and decodes opaque keyset cursors`; `V:validates ordered active pages and produces the next query` | `V:rejects malformed, inconsistent, stale, unordered, and inactive pages`; `R:verify(:invalid_pages`; `C:the accepted public value fields contain no offset or stream authority` |
| 5.7, 6.1 | Collection generation, Unicode ordering and committed page snapshots | `R:verify(:listing`; `R:verify(:revisions`; `P:verify(:paging_snapshot` | `P:verify({:paging_mutation`; `D:rejects a malformed cursor before any port is invoked` |
| 5.7, 7.6 | Expiry-only membership drift does not invalidate continuation | `P:verify(:paging_expiry`; `P:verify(:paging_empty` | `F:verify(:time_and_pages`; `P:verify({:paging_mutation` |
| 6.1 fetch/insert | Committed fetch and atomic conditional creation | `R:verify(:fetch_insert`; `R:verify(:insert_contention` | `P:verify(:create_race`; `R:verify(:failures` |
| 6.1 replace | One atomic expected-version replacement | `R:verify(:replace`; `R:verify(:replace_contention` | `P:verify({:competing`; `R:verify(:failures` |
| 6.1 delete | One atomic expected-version deletion | `R:verify(:delete`; `R:verify(:delete_contention` | `P:verify({:competing`; `R:verify(:failures` |
| 6.1 list | One bounded active snapshot and decoded-cursor contract | `R:verify(:listing`; `P:verify(:paging_snapshot` | `R:verify(:invalid_pages`; `P:verify({:paging_mutation` |
| 6.1 expire_due | Atomic bounded expiry; one revision per nonempty batch | `R:verify(:expiry`; `R:verify(:expiry_contention` | `D:an expiry batch with no due entries does not advance collection revision`; `P:verify({:interrupted` |
| 6.1, 9 | No hidden retry, compensation or multi-callback transaction | `P:verify(:create_race`; `P:verify({:competing` | `P:verify({:interrupted`; `P:verify({:failed_reply` |
| 6.2, 7, 9 | Authorization precedes target storage and hides existence on denial | `R:verify(:public_order` | `R:verify(:denial`; `F:verify(:isolation`; `F:verify(:failed_ports` |
| 6.3 | Frozen caller-selected clock, including explicit system-clock opt-in | `V:system clock returns a UTC DateTime without state`; `F:verify(:time_and_pages` | `S:the shipped system clock is selected explicitly and never implicitly`; `F:verify(:failed_ports` |
| 6.4, 7.1 | Anonymous absolute identifier, explicit generation and collision | `D:assigns an identifier to an anonymous Thing Description before insert`; `F:verify(:authority` | `V:accepts absolute IRIs and rejects relative, blank, control, and non-string values`; `F:verify(:failed_ports` |
| 7.1 | Named create/update outcomes and preserved registration history | `D:creates and then replaces a named registration with explicit outcomes`; `F:verify(:lifecycle` | `P:verify(:create_race`; `D:named register authorizes its target before checking existence` |
| 7.2 | Active retrieval with distinct missing and expired errors | `D:retrieval assigns returned metadata without mutating storage` | `D:expired and missing entries have distinct deterministic results`; `F:verify(:isolation` |
| 7.3 | Validated full replacement with identity/version preconditions | `D:replacement validates identifier and optimistic version`; `F:verify(:lifecycle` | `P:verify({:competing`; `F:verify(:lifecycle` |
| 7.4 | Bounded RFC 7396 map merge, removal and whole-array replacement | `M:implements recursive RFC 7396 replacement, insertion, and removal`; `M:replaces a non-object target member when patching it with an object`; `M:replaces whole arrays without retaining previous elements`; `D:patch merges and core-validates before conditional persistence` | `M:rejects non-object roots, non-string keys, and bounded-work violations`; `M:reports the JSON Pointer of an offending nested member`; `P:verify(:invalid_patch` |
| 7.4 | Patch cannot change identity or server-owned registration times | `D:empty patch refreshes a relative expiry`; `F:verify(:lifecycle` | `D:patch cannot assign or remove server registration fields`; `D:invalid patch leaves the stored entry unchanged` |
| 7.5 | Delete returns only its committed removed entry | `D:deletes only the observed version and returns the removed entry` | `P:verify({:competing`; `P:verify({:interrupted` |
| 7.7, 9 | Explicit retain/purge, inclusive cutoff, bounded batches and idempotence | `D:purges only a bounded sorted set of due entries`; `D:purge removes due active and retained expired entries in one bounded batch` | `D:retain processes a due active entry only once`; `B:invalid registration and expiry controls fail before persistence`; `P:verify({:interrupted` |
| 5.8, 7.8 | Introduction is only the configured directory TD and invokes no port | `D:Introduction bypasses all consumer ports and contains no entry`; `F:verify(:authority` | `V:Introduction requires a validated Thing Description with an absolute identifier`; `E:public operations reject invalid service and request shapes deterministically` |
| 8, 9 | Stable error code/phase/message/path/details and redacted failures | `C:every accepted error code retains its deterministic message and value shape`; `E:every public failure carries the family error shape` | `B:repository result variants are normalized and never escape`; `F:verify(:failed_ports`; `R:verify(:failures` |
| 2, 3, 9 | No library application, process/store/configuration authority or packaged development state | `A:inspect_directory!`; `L:Application.spec(app, :mod)` | `L:effect_modules`; `L:source is outside the archive consumer`; `F:verify(:authority` |
| 3, 4 | Only listing is supported; search, offset and stream transport are not emulated | `C:the accepted directory facade and required callback arities remain explicit` | `F:verify(:time_and_pages`; `F:verify(:authority`; `C:default bounds and caller-selected time` |

## Compatibility review

`compatibility_test.exs` checks the 15 exported facade arities, nine required
port callbacks, fields of all 12 public value structs, default service/query
bounds, and all 17 stable error messages. It runs both in the library suite and
against the exact archive. Constructors, malformed callback returns, operation
order and temporal semantics remain covered by the matrix above. No production
signature, field, return shape, error code, dependency requirement or operation
ordering is changed by this evidence work.

The review boundaries are:

- The core dependency is the normal `wotex ~> 0.1.0` package. A source-development
  run records the explicitly selected source cohort separately from the exact
  archive cohort; it does not substitute for archive consumption.
- Context and port state remain opaque. Callback return normalization is not
  exception handling: a consumer adapter owns its exceptions, atomicity and
  acknowledgement-loss recovery. No failure promises rollback after commit.
- Versions are entry preconditions; collection revisions are opaque mutation
  generations. Clients cannot construct offsets or depend on cursor bytes.
  Decision 0002's keyset model is not a promise to decode an earlier offset
  representation. Only the WTD.01 1.1.0 cursor contract is reviewed here.
- Time is injected per call. Pure time passage does not mutate registration,
  versions or generations. Retention changes an active entry once; purge may
  remove retained entries. Backwards mutation time is rejected, not clamped.
- Unknown TD and registration extension terms remain values, not locally
  interpreted standards claims. Retrieval metadata is response-only.
- Facade errors are redacted. The low-level `Error.new/4` constructor requires
  callers to supply valid phases/operations and safe details; it does not
  sanitize arbitrary caller-owned data.
- Event values have no durable identifier, replay cursor, subscription or
  publication authority. Expiry has no scheduler. Introduction has no access
  policy or enumeration side effect.

WTD.01 section 10 still governs changes. Public type changes in the 0.x line
require a specification, tests and a minor version change. Removing an error,
requiring another callback, changing callback results or operation order is a
breaking change once the API reaches 1.0. Additive optional fields still require
review even where that policy permits them. The exact-field tests intentionally
force that review rather than silently accepting a changed value surface.

This is an unstable 0.1.0 compatibility baseline, not a stable-API designation,
full Discovery conformance or external certification. Production adapters and
wire profiles require their own evidence. No publication is authorized.

## Release-evidence manifest

Plain `WOTEX_PATH_DEPS=1 mix check --no-retry` is the complete authoritative
gate. Its coverage command runs the library tests once. The archive check runs
133 isolated tests: 64 contract scenarios for each repository consumer, the
minimal operation sequence and four compatibility tests. There is no separate
release profile or reduced default gate.

Each gate invocation allocates a system temporary artifact directory. The
initial input record and compiler exit status, archives, consumer lock,
`archive-evidence.json` and `release-evidence.json` remain there. Generated
consumer files and compiled modules are removed. None of these outputs is a
source or package input.

The release manifest has schema version `1.0.0`:

| Field | Evidence |
|---|---|
| `verification_source` | Source commit and cleanliness, per-file SHA-256 for code/tests/specifications/gate configuration/lock/provenance, runtime versions, and the explicit path-dependency source commit/input hashes when selected. |
| `archive` | Directory/core versions and input mode, archive and consumer-lock SHA-256, locked Hex versions/checksums, archive-consumer commands and actual test totals with zero failures/exclusions/skips. |
| `checks` | Every preceding authoritative check's command, explicit environment override and successful exit code. |
| `specification` | WTD.01 1.1.0 and its 2023-12-05 target revision. |
| `claims` | Bounded Directory mechanics and two test consumers; no transport conformance, certification or stable API. |
| `publication_authorized` | Always false. |

The finalizer runs only after every non-compiler check succeeds. ExCheck runs
its compiler outside that dependency pipeline, so a wrapper runs the same
warning-free compile once and records its actual exit status; the finalizer
also requires that status to be zero. A skipped or failed prerequisite cannot
produce a complete manifest. Source, dependency and runtime inputs must still
match the initial record, and artifact checksums are revalidated before output.

The manifest is local execution evidence, not a signed attestation or release
approval. Invoking the finalizer manually is not a substitute for the gate.
Dirty-tree manifests describe working-tree inputs and cannot identify those
bytes solely by their source commit. A candidate review requires a fresh gate
from the intended clean commit and must retain the printed manifest and exact
archives. The package-exclusion sentinel acceptance in WTD-C06 and human
publication review remain separate obligations.
