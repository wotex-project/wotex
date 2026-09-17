# Decision 0002: Revision-aware listing and explicit expiry

Status: accepted

## Decision

The supported query profile is the Discovery Things listing with a positive
`limit`, deterministic ascending Unicode code point order by identifier, and an
opaque keyset cursor carried across pages. JSONPath, XPath, and SPARQL profiles
return an explicit unsupported error.

The cursor binds the collection revision that issued it to the last identifier
of the page it continues. A repository selects the entries whose identifier is
greater than that identifier. The revision binds the repository mutation
generation: every insert, replace, delete, and entry-changing expiry batch
advances it exactly once, and a cursor whose revision is no longer current is
refused with `collection_changed`.

Membership that changed only because an entry reached absolute expiry does not
advance the revision and does not end a page chain. Keyset continuation remains
correct when the active view shrinks with time, so an entry that expires
between two page calls is simply absent from the following page. Listing
therefore requires no snapshot of active membership and no temporal table.

Expiry has two layers:

1. reads and listing evaluate activity against the injected clock, so an
   overdue entry is never returned as active merely because a sweep has not run;
2. `expire/3` invokes one bounded repository transaction using `purge` or an
   explicitly selected `retain` strategy.

Retention selects only due active entries and transitions each one to expired
once. Purge selects due active entries and due entries already retained as
expired. A batch that selects nothing does not advance collection revision; a
batch that changes entries advances it exactly once.

The consumer schedules expiry. The library starts no timer or worker.

## Rationale

Discovery pagination is expressed as a `next` link that carries every argument
needed to continue, not as a mandatory client-visible offset. An offset over an
active-only view is not implementable without temporal storage, because a
wall-clock expiry between two pages shifts every following offset; the previous
offset contract turned the common case into `collection_changed`. A keyset
cursor over the identifier order is implementable directly by an ETS table, a
SQLite statement, and an Ecto query, and it keeps the exact Discovery ordering
requirement as the only ordering the package claims.

Binding the mutation generation still prevents a page chain from silently
crossing two orderings, while an opaque cursor keeps the continuation token out
of the public value surface, so no consumer can construct a position by
arithmetic. Explicit unsupported profiles preserve accurate claims. Separating
activity evaluation from cleanup prevents scheduling delay from changing read
semantics. One-way retained expiry prevents repeated sweeps from creating
version and revision churn without a lifecycle change.

## Consequences

- Repository adapters must provide a monotonic collection revision and a keyset
  selection over identifiers; neither requires temporal tables.
- A mutation that advances the revision invalidates an outstanding cursor and
  requires a new first page.
- Wall-clock expiry between pages is not an error: the expired entry is absent
  from the following page.
- The cursor is opaque; the package owns its encoding and rejects an
  undecodable cursor before any port is invoked.
- Retention is available for consumers that need an expired state, while purge
  remains the default aligned with the Recommendation's cleanup guidance.
- A consumer may purge entries previously retained as expired without first
  reactivating them.
