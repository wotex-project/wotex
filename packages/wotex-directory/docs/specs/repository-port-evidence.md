# Repository port evidence contract

This document maps the reusable repository tests to WTD.01 version 1.1.0 and
completion work item WTD-C01. It adds executable evidence for the existing
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

## Verification and evidence boundary

The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/directory/scoped_memory_repository_contract_test.exs test/wotex/directory/table_repository_contract_test.exs
```

`WOTEX_PATH_DEPS=1 mix check --no-retry` runs the full library gate. A path
dependency run identifies only that source cohort. The suite establishes
callback-level behavior for the configured adapters; it is not Discovery
certification, a production storage implementation, or archive-only consumer
installation.

WTD-C02 adds controlled interleavings between public fetch/validation/mutation
stages and interrupted-consumer scenarios. Its acceptance must prove that
public expected-version writes have one winner, failed/interrupted operations
produce no successful mutation, and resumed pagination distinguishes a changed
mutation generation from expiry-only membership changes. The basic callback
contention scenarios here provide its prerequisite rather than claim those
multi-stage scenarios complete. WTD-C03 and WTD-C04 retain archive and
independent reference-consumer obligations.
