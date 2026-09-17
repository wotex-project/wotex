# Decision 0001: Consumer-owned runtime and authority

Status: accepted

## Decision

The library is a normal Mix dependency with no application callback, process,
database, filesystem store, scheduler, HTTP server, policy engine, or global
configuration. A `Service` value receives repository, authorization, clock, and
identifier ports with explicit state. The consumer owns and supervises every
adapter.

Thing Description semantics come only from the public `wotex` core facade. The
directory package owns the Discovery registration layer and orchestration but
does not inspect core struct internals.

## Rationale

Persistence isolation, actor policy, time control, and identifier generation
vary by consumer and deployment. Encoding any one of them in the package would
turn a standards mechanic into a host architecture. Explicit values also allow
multiple independent directory instances in one BEAM without singleton names or
application-global state.

## Consequences

- The consumer must supply four small ports and schedule expiry explicitly.
- The package can be tested deterministically without a network or database.
- Transport mapping and operational availability are consumer evidence, not
  package claims.
- Port callback changes are compatibility-sensitive.
