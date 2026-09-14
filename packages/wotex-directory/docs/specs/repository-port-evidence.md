# Repository port evidence contract

This document maps the reusable repository tests to WTD.01 version 1.1.0 and
completion work items WTD-C01, WTD-C02 and WTD-C03. It adds evidence for the existing
contract without changing callback signatures, return values, public types,
operation order, or the W3C baseline. Discovery and Thing Description 1.1
remain the Recommendations dated 2023-12-05. Package choices are specified
by WTD.01 and decisions 0001 and 0002.

## Existing and reusable evidence

The operation tests in `test/wotex/directory/directory_test.exs` cover
registration, retrieval, replacement, patch, deletion, keyset paging, expiry,
and Introduction against `MemoryRepository`. The error and robustness tests
exercise malformed and failed port returns through `StubRepository`;
registration, service, value, and event tests cover their own value boundaries.
Those tests remain the detailed evidence for malformed request admission and
the package's return normalization.

`test/support/wotex/directory/repository_contract.ex` adds the reusable
`Wotex.Directory.RepositoryContract` suite. Its assertions use the public
repository callbacks, directory facade, and public values. They do not inspect
adapter storage, import private directory mechanics, or impose a production
storage technology. The test-only probe records callback order and injects
failure returns before delegation. It creates no production port or runtime
dependency.

| Owning requirement | Reusable scenario | Additional evidence |
|---|---|---|
| WTD.01 6.1 `fetch/3`, `insert/3` | `fetch_insert` | Absence accepts either documented return; insert/fetch preserve full entry and extension values; duplicate create refuses overwrite and preserves the generation. |
| WTD.01 6.1 `replace/4` | `replace` | Missing and stale versions fail without mutation; successful replacement preserves the exact accepted entry and advances one generation. |
| WTD.01 6.1 `delete/4` | `delete` | Missing/stale versions fail; one successful delete removes only its expected version and advances one generation. |
| WTD.01 5.7, 6.1 `list/5` | `listing`, `revisions` | Unicode identifier ordering, unique bounded pages, decoded keyset continuation, active-only results, expiry at the exact cutoff, stable reads, and invalidation by every mutation kind. |
| WTD.01 6.1 `expire_due/5`, 7.7 | `expiry` | Sorted bounded retain/purge, inclusive cutoff, one entry-version transition, one generation per nonempty batch, unchanged empty batches, and retained-entry purge. |
| WTD.01 5.2, 6.1 | `isolation` | The same identifier has independent values and generations in two contexts; all six callbacks preserve that separation. |
| WTD.01 6.2, 7.1–7.8, 9 | `public_order`, `denial` | Public operations forward explicit principal/auth/repository contexts, authorize the target before its callback, keep retrieval timestamps out of storage, and expose no repository callback or existence information on denial. Introduction invokes no observed port. |
| WTD.01 6.1, 8, 9 | `failures`, `invalid_pages` | Failure and malformed returns are redacted; each failing callback is invoked once; failed mutations leave entries/generations unchanged; unordered, duplicate, inactive and oversized pages fail at the public facade. |
| WTD.01 6.1 atomic callbacks | `insert_contention`, `replace_contention`, `delete_contention`, `expiry_contention` | Eight callers wait at an explicit start barrier; conditional mutations have one winner, and concurrent retained-expiry batches never select the same entry twice. |

## Consumer fixture interface

A test module uses `ExUnit.Case` and `Wotex.Directory.RepositoryContract`.
Its `setup` callback supplies `repository_fixture` with these fields:

| Field | Test requirement |
|---|---|
| `repository` | `{module, state}` implementing all six public repository callbacks. State is passed unchanged. |
| `scope`, `other_scope` | Two distinct opaque repository contexts with initially empty, isolated collections. |
| `generation` | A consumer test function mapping the public opaque collection revision to its mutation generation. Both collections start at zero. This projection belongs only to the test fixture; clients must continue to treat cursors and revision strings as opaque. |
| `identifier` | An explicitly supervised `TestIdentifier` instance with at least two synthetic anonymous identifiers available. |

Each test gets a new fixture. Its consumer owns process/table lifetime and
cleanup. The suite requires no application configuration, network, database,
filesystem store, wall-clock wait, or globally registered process. The ready/go
barrier uses a bounded timeout solely to fail a stalled test.

The checked-in fixtures demonstrate two independent transaction mechanisms:

- `ScopedMemoryRepositoryContractTest` routes each context to its own existing
  Agent-backed `MemoryRepository`; that consumer serializes callbacks over a
  map. `ScopedMemoryRepository` performs only explicit context routing.
- `TableRepositoryContractTest` uses an unnamed test-owned ETS table. Each
  context holds a generation and a list of entries in one row. A mutation
  computes a new row and commits it using `:ets.select_replace/2`; a competing
  generation causes the adapter to repeat its internal compare-and-swap step.
  No failed public directory operation is retried. This implementation does
  not delegate mutation, listing, expiry, or storage to `MemoryRepository`.

These fixtures are test-only consumer implementations, excluded from the
package archive. A different consumer can supply its own fixture and run the
same suite from the source distribution. The generation projection makes the
exactly-once counter assertion explicit without prescribing a public revision
encoding or inspecting adapter internals.

## Public-operation interleaving evidence

`Wotex.Directory.PublicOperationContract` uses the same fixture interface and
both test consumers. Its 44 scenarios per consumer exercise public directory
operations across repository callback boundaries. It does not call private
directory functions or inspect adapter storage.

| Owning requirement | Reusable scenario | Evidence |
|---|---|---|
| WTD.01 6.1, 7.1, 7.3–7.5, 9 | `{:competing, winner, loser}` | All 16 ordered pairs of named registration update, replacement, patch and deletion fetch the same committed version. Both reach their conditional write before the selected winner commits. The loser returns `conflict`, or `not_found` after deletion, without refetch, retry or a successful Mutation/Event value. The winner alone advances the generation. |
| WTD.01 7.1 | `create_race` | Two named registrations observe absence before either insert. One creates; the other reports conflict. Only an explicit repeated call follows replacement semantics. |
| WTD.01 7.4, 9 | `invalid_patch` | A patch resumes from an earlier fetched value after a competing patch commits. Core validation refuses the invalid merged Thing Description without a write callback or a successful Mutation/Event value. |
| WTD.01 6.1, 7.1, 7.3–7.5, 7.7 | `{:interrupted, operation, phase}` | Each of create, named update, replacement, patch, deletion, retained expiry and purge is interrupted before delegation or after a successful callback has committed. No result reaches the interrupted consumer. Before delegation, state and generation remain unchanged; after commit, they retain exactly that one committed transition. Explicit repetition observes the documented version, absence, registration-update or no-op expiry outcome. |
| WTD.01 6.1, 8 | `{:failed_reply, phase}` | An injected failure before replacement delegation leaves state unchanged. A fault that discards a committed replacement's acknowledgement yields a redacted repository error, not a successful Mutation/Event value, retry or compensation. A subsequent expected-version call detects the committed version. |
| WTD.01 5.7, 6.1, 7.6 | `{:paging_mutation, operation}` | A saved continuation waits before its list callback while each of the seven mutation kinds commits. Resumption reports `collection_changed`; a new first page observes the new collection. |
| WTD.01 5.7, 7.6, decision 0002 | `paging_expiry`, `paging_empty` | New callers resume the opaque query across exact expiry cutoffs without a sweep. Entries before and after the keyset position expire without skipped active entries or generation changes. The chain may end with an empty page. Query limit/format and returned retrieval timestamps remain correct; storage remains unchanged. |
| WTD.01 6.1 `list/5` | `paging_snapshot` | A committed page snapshot is held while another caller mutates the collection. The first caller may return that original snapshot; continuation then rejects its old generation. A page is not silently upgraded to a newer snapshot. |

`RepositoryBarrier` is a test-only port decorator. Explicit messages pause a
caller before delegation or after the decorated callback returns. A fetch
checkpoint exposes the committed value already read; a mutation-entry
checkpoint occurs after library admission and before the adapter's atomic
step. An after-callback checkpoint proves only that the configured adapter
returned, not any internal database commit protocol. The adapter contract suite
separately establishes atomic callback behavior for these consumers.

Monitored callers and per-checkpoint references make each interleaving explicit.
Tests wait for a checkpoint before permitting the competing operation, and
confirm caller termination before checking results and callback counts. Test
cleanup stops any caller left waiting after a failed assertion. The five-second
timeouts fail stalled tests; they do not schedule races or emulate elapsed time.
Expiry uses the explicitly injected clock without sleeps.

An interrupted caller is not evidence that a repository transaction rolled
back. A callback may commit before its caller receives the result. Likewise, a
faulty consumer adapter can lose a successful acknowledgement after committing.
The library cannot undo or safely retry that outcome. These tests establish
that it produces no successful result from an error, performs no implicit
retry or compensation, and permits a fresh caller to observe the committed
state. Recovery, durable event delivery and any transaction spanning storage
and publication remain consumer responsibilities.

## Verification and evidence boundary

The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/directory/scoped_memory_repository_contract_test.exs test/wotex/directory/table_repository_contract_test.exs
```

`WOTEX_PATH_DEPS=1 mix check --no-retry` runs the full library gate. A path
dependency test run identifies only that source cohort. The suites establish
the configured adapters' tested behavior; they do not provide Discovery
certification or production storage.

### Archive-only consumer

`WOTEX_PATH_DEPS=1 mix package` and the full gate's archive check execute
`bin/check_archive.exs`. The check builds exactly one Directory archive in a
new system temporary directory. It validates the Hex envelope checksum,
package identity/version, declared files, the normal `wotex ~> 0.1.0`
dependency and the public package boundary before compilation. Package inputs
allowlist individual documents. Development instructions, test consumers,
builds, dependencies and task state are absent from the archive.

The core input is either the archive explicitly named by `WOTEX_CORE_ARCHIVE`
or an archive built from the dependency source explicitly selected by
`WOTEX_PATH_DEPS=1`. This is a build-input choice, not a consumer fallback.
Archive construction clears that switch. The generated consumer clears it
again, along with inherited dependency, build and BEAM code-path overrides.
Its Directory and core dependencies point only to unpacked archives under its
own temporary directory. The only remaining dependencies are the locked Hex
cohort of `decimal`, `ex_json_schema` and `jason`. Their versions and Hex
checksums are copied from the declared development lock and cannot change
during the consumer run.

`bin/archive_consumer.exs` compiles dependencies from scratch, then explicitly
recompiles the Directory and core archives with warnings as errors. This
second compile is necessary because Mix disables warnings-as-errors for its
ordinary dependency compilation. The verifier checks that dependency source
paths and loaded library modules belong to the isolated consumer, that neither
library has an OTP application callback, and that loading the modules starts
no library application. It then runs the 15 reusable repository scenarios plus
a public registration/retrieval/patch/list/expiry sequence with invalid,
conflict, expired, missing and repeated-expiry outcomes. No library source or
compiled module is copied from a checkout. The explicitly copied test suite
and test-only ports are verification inputs, not packaged storage products.

The check prints Directory/core archive SHA-256 digests, the consumer lock
digest, and the full Hex lock cohort. It retains both archives and the lock in
the printed external artifact directory; the generated consumer and its build
are removed. These files are evidence outputs, never package inputs or
checked-in completion state.

The callback and public-operation suites establish the configured consumers'
behavior at the tested boundaries. They do not prove crash recovery inside an
arbitrary storage transaction, durable event delivery, a global resource bound,
or interoperability of a production adapter. WTD-C04 retains independent
reference-consumer obligations against an exact archive.
