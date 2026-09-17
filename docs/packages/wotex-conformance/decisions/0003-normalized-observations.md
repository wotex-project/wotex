# Decision: normalize observations and declare vector projections

## Status

Accepted.

## Context

Protocol revision `1.0` described the request and response envelope but left
the observation opaque. Each vector expected whatever shape its author had in
mind, so two vectors for the same operation could expect unrelated values. An
independent adapter could not satisfy a vector from the request alone; it had
to know the hidden expectation, which is exactly the coupling the external
target protocol exists to prevent.

Early vectors also expected invented rejection identifiers. A code that no
Thing Description or Thing Model implementation emits cannot classify a
subject; it only measures agreement with this repository.

## Decision

Document operations use one normalized observation. An accepted document is
reported as `{"accepted": true, "document": …}` and a rejected document as
`{"accepted": false, "errors": […]}` with unique `code`, `phase`, and `path`
members sorted by path and code.

Each vector declares a projection: a list of RFC 6901 JSON Pointers naming the
members its observation reports. The projection travels to the target inside
`vector.input`, so the adapter derives the whole observation from the
operation, the document, and the projection. An empty projection declares the
whole accepted document.

Rejection identifiers name codes an implementation actually emits for the cited
clause. Messages and details stay out of observations because messages are
explicitly unstable, while codes, phases, and paths are matching interfaces.

The runner rejects a non-normalized observation as `infrastructure_error`
rather than `fail`, because a protocol violation is not subject evidence.

## Consequences

- An independent adapter can pass a vector without reading the corpus
  expectation, which is what makes cross-implementation evidence meaningful.
- Projections keep observations small and bounded while remaining explicit
  about which members are claimed.
- Absence is observable: a declared pointer that does not resolve is omitted,
  so a vector can claim that a member does not survive parsing.
- Adding an operation family requires a normalized shape before vectors, not
  after.
- The shapes are a compatibility boundary. Changing them changes every vector
  digest and corpus digest and requires a schema and protocol decision.
