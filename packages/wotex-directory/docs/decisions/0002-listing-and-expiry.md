# Decision 0002: Revision-aware listing and explicit expiry

Status: accepted

## Decision

The supported query profile is the Discovery Things listing with positive
`limit`, zero-based `offset`, deterministic identifier order, and a collection
revision carried across pages. JSONPath, XPath, and SPARQL profiles return an
explicit unsupported error.

Expiry has two layers:

1. reads and listing evaluate activity against the injected clock, so an
   overdue entry is never returned as active merely because a sweep has not run;
2. `expire/3` invokes one bounded repository transaction using `purge` or an
   explicitly selected `retain` strategy.

The consumer schedules expiry. The library starts no timer or worker.

## Rationale

Offset pagination is the exact Discovery pagination vocabulary. A collection
revision prevents pages from silently crossing different collection orderings.
Explicit unsupported profiles preserve accurate claims. Separating activity
evaluation from cleanup prevents scheduling delay from changing read semantics.

## Consequences

- Repository adapters must provide atomic collection revision behavior.
- A changed collection can return `collection_changed` and require a new first
  page.
- Retention is available for consumers that need an expired state, while purge
  remains the default aligned with the Recommendation's cleanup guidance.
