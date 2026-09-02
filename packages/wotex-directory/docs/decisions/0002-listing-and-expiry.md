# Decision 0002: Revision-aware listing and explicit expiry

Status: accepted

## Decision

The supported query profile is the Discovery Things listing with positive
`limit`, zero-based `offset`, deterministic identifier order, and a collection
revision carried across pages. JSONPath, XPath, and SPARQL profiles return an
explicit unsupported error. The revision binds the repository mutation
generation and the active membership observed for the first page. If an entry
reaches absolute expiry between page calls, the repository returns
`collection_changed` rather than applying the next offset to a changed active
collection.

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

Offset pagination is the exact Discovery pagination vocabulary. A collection
revision prevents pages from silently crossing different collection orderings,
including an ordering whose membership changed only because time passed.
Explicit unsupported profiles preserve accurate claims. Separating activity
evaluation from cleanup prevents scheduling delay from changing read semantics.
One-way retained expiry prevents repeated sweeps from creating version and
revision churn without a lifecycle change.

## Consequences

- Repository adapters must provide atomic collection revision behavior.
- A mutation or wall-clock expiry that changes active membership returns
  `collection_changed` and requires a new first page.
- Retention is available for consumers that need an expired state, while purge
  remains the default aligned with the Recommendation's cleanup guidance.
- A consumer may purge entries previously retained as expired without first
  reactivating them.
