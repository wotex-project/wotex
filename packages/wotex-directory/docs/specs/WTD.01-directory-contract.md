---
wotex:
  document_type: specification
  document_version: 1
specification:
  id: WTD.01
  title: Storage-neutral Thing Description Directory contract
  status: accepted
  version: 0.1.0
  target_revision: 2023-12-05
---

# WTD.01: Storage-neutral Thing Description Directory contract

## 1. Purpose

This specification defines the public, storage-neutral values and mechanics for
a W3C Web of Things Thing Description Directory. It covers registration,
retrieval, replacement, JSON Merge Patch, deletion, bounded listing, a listing
query profile, registration expiry, and well-known Introduction.

The target standards are the W3C WoT Discovery Recommendation and Thing
Description 1.1, both published 2023-12-05. Requirement words in this document
apply to this package. W3C requirements are cited separately so package choices
cannot be mistaken for Recommendation text.

## 2. Authority and dependency boundary

The `wotex` core package is the sole authority for:

- Thing Description value construction and validation;
- Thing Description `id` semantics;
- DataSchema, Form, security-scheme, Property, Action, and Event affordances;
- JSON-compatible map conversion;
- extension-term preservation; and
- lossless and canonical serialization.

This package consumes only the public `Wotex.ThingDescription` facade. It does
not inspect or construct core struct fields.

This package owns:

- Discovery registration information;
- directory entry and operation result values;
- operation ordering across authorization, clock, core validation, and the
  repository port;
- optimistic version expectations;
- RFC 7396 JSON Merge Patch orchestration;
- bounded listing and collection-revision continuity;
- explicit expiry evaluation and caller-invoked expiry batches; and
- the value returned by the well-known Introduction surface.

The consumer owns persistence, repository transactions, actor policy,
authentication, scheduling, process supervision, transport routes, HTTP status
mapping, credentials, monitoring, and deployment.

## 3. Non-goals and non-claims

The package does not provide:

- a database, filesystem store, or authoritative in-memory production store;
- an HTTP server or router;
- background expiry scheduling;
- a credential store or policy engine;
- JSONPath, XPath, or SPARQL search;
- an event stream, event persistence, replay, or transport encoding;
- alternate RDF serializations;
- Thing provisioning or canonical Thing state; or
- W3C certification.

Unsupported query profiles return a typed `unsupported_query_profile` error.
They are never treated as an empty result.

## 4. W3C baseline and implementation choices

| Concern | W3C baseline | Package choice |
|---|---|---|
| Collection | Discovery requires listing at a Things API | Transport-neutral `list/3` and `query/3` values |
| Named creation | Discovery uses PUT and treats an existing target as update | `register/4` is an atomic-intent upsert; result is `created` or `replaced` |
| Anonymous creation | Discovery uses POST and requires a directory-local identifier | Identifier port supplies an absolute IRI before repository insertion |
| Retrieval | Discovery retrieves one Thing Description by identifier | `get/3` returns an enriched entry value |
| Replacement | Discovery PUT replaces a complete Thing Description | `replace/5` requires an existing entry and an optional version precondition |
| Partial update | Discovery requires RFC 7396 for PATCH | `patch/5` merge-patches the enriched JSON value, then validates before write |
| Deletion | Discovery deletes by identifier | `delete/4` is conditional on the observed or supplied version |
| Validation | Discovery recommends at least TD minimal validation | Every write must pass the core Thing Description 1.1 validator |
| Listing order | Discovery requires ascending Unicode code point order by identifier when paginated | Every page is checked for that order |
| Pagination | Discovery defines optional `limit`, zero-based `offset`, `next`, and canonical collection revision information | Listing uses bounded offset pages and an immutable collection-revision token that detects both mutations and wall-clock expiry changes |
| Expiry | Discovery defines `ttl` and `expires`, and recommends purging expired registrations | Reads reject expired entries; consumer-invoked bounded expiry defaults to purge and may explicitly transition an active entry once into retained expired state |
| Introduction | Discovery allows `/.well-known/wot` and requires the directory's own Thing Description there when used | `introduction/1` returns that value without entry repository access |
| Events | Discovery optionally defines three lifecycle events over SSE | `Event.from_mutation/2` derives transport-neutral type and data; the consumer owns publication and delivery |
| Search | JSONPath and XPath are informative; SPARQL is optional | No search profile is implemented |

The implementation does not own HTTP. A transport host maps values to the exact
Discovery endpoints, methods, media types, Link headers, and Problem Details.

## 5. Public values

### 5.1 Service

`Wotex.Directory.Service` is immutable configuration for one directory
instance:

```elixir
Wotex.Directory.Service.new(
  repository: {RepositoryModule, repository_state},
  authorization: {AuthorizationModule, authorization_state},
  clock: {ClockModule, clock_state},
  identifier: {IdentifierModule, identifier_state},
  introduction: directory_thing_description,
  default_page_limit: 50,
  maximum_page_limit: 200,
  default_expiry_batch_limit: 100,
  maximum_expiry_batch_limit: 1_000,
  expiry_strategy: :purge,
  maximum_patch_depth: 64,
  maximum_patch_nodes: 100_000,
  thing_description_options: []
)
```

Every dependency is explicit. Construction validates callback availability and
bounds, and returns `{:ok, service}` or a typed error. It performs no I/O.

### 5.2 Request context

`Wotex.Directory.Context` carries:

- an opaque, non-nil `principal` for authorization;
- opaque `authorization` context; and
- opaque `repository` context.

The library assigns no meaning to consumer scope identifiers. A consumer may
bind a repository state to one security boundary or interpret the opaque
context in its adapter.

### 5.3 Registration information

`Wotex.Directory.Registration` represents the Discovery terms:

- `created`: server-assigned `DateTime`;
- `modified`: server-assigned `DateTime`;
- `expires`: optional absolute `DateTime`;
- `ttl`: optional unsigned 32-bit lifetime in seconds; and
- `retrieved`: optional server-assigned retrieval `DateTime` on returned values.

When `ttl` is present, `expires` is calculated as `modified + ttl` and a client
assignment to `expires` is ignored. `created`, `modified`, and `retrieved` are
read-only. Stored entries must have `retrieved: nil`.

Registration information is embedded under `registration` only when producing
an enriched Thing Description. That value includes the exact Discovery context
`https://www.w3.org/2022/wot/discovery` without removing existing contexts.

### 5.4 Entry

`Wotex.Directory.Entry` contains:

- `identifier`: the Thing Description identifier;
- `thing_description`: a validated core Thing Description value;
- `registration`: registration information;
- `version`: a positive optimistic-concurrency integer; and
- `state`: `active` or `expired`.

The identifier must equal the core Thing Description `id`. Directory version
and state are package mechanics and are not emitted as W3C terms.

### 5.5 Mutation

`Wotex.Directory.Mutation` identifies the operation outcome:

- operation: `register`, `replace`, `patch`, or `delete`;
- status: `created`, `replaced`, `patched`, or `deleted`; and
- the affected entry value.

The value is transport-neutral. In particular, it does not contain an HTTP
status or route.

### 5.6 Event

`Wotex.Directory.Event.from_mutation/2` projects a successful mutation into
one of the Discovery lifecycle event types:

- a created registration becomes `thing_created`;
- named registration replacement, complete replacement, and patch become
  `thing_updated`; and
- deletion becomes `thing_deleted`.

The default event data is the enriched Thing Description for create and update
events. `payload: :identifier` returns the minimum Partial TD containing only
`id`. Deletion always returns that minimum form. The value deliberately has no
SSE event ID: durable ordering, IDs, replay, filtering, authorization, and
transport encoding belong to the consumer that publishes the optional Events
API.

### 5.7 Query and page

`Wotex.Directory.Query` contains:

- profile: `listing`;
- zero-based `offset`;
- positive `limit`;
- format: `array` or `collection`; and
- optional `collection_revision` from a preceding page.

`Wotex.Directory.Page` contains ordered entries, offset, limit, optional next
offset, and a non-empty collection revision. `Page.next_query/2` carries the
same limit, format, and collection revision forward.

If a repository cannot honor the supplied collection revision because the
collection changed, it returns `collection_changed`; it must not silently return
a page from a different ordering snapshot. The active collection can change
without a repository mutation when an entry reaches its absolute expiry. A
revision therefore binds both the repository mutation generation and the active
membership observed for the first page. An adapter must return
`collection_changed` if the supplied revision no longer identifies the same
active membership at the new `active_at` value.

### 5.7 Introduction

`Wotex.Directory.Introduction` contains:

- path: `/.well-known/wot`;
- media type: `application/td+json`; and
- the validated Thing Description of the directory itself.

It contains no directory entry and no authorization or repository context.

## 6. Consumer ports

Port state is supplied in `Service` and passed back unchanged. Callbacks must
not depend on application-global configuration.

### 6.1 Repository

```elixir
fetch(state, identifier, repository_context)
insert(state, entry, repository_context)
replace(state, entry, expected_version, repository_context)
delete(state, identifier, expected_version, repository_context)
list(state, query, active_at, repository_context)
expire_due(state, cutoff, limit, strategy, repository_context)
```

Repository requirements:

- `insert` is atomic and reports `already_exists` on collision.
- `replace` and `delete` compare `expected_version` atomically and report
  `conflict` on mismatch.
- `list` excludes expired entries at `active_at`, orders by identifier in
  ascending Unicode code point order, honors the requested collection revision,
  returns no more than `limit` entries, and reports `collection_changed` when
  wall-clock expiry changed active membership since the revision was issued.
- `expire_due` is a bounded transaction. `retain` selects only due active
  entries, atomically changes each selected entry to `expired`, and advances
  each selected entry's version once. `purge` removes due active entries and due
  entries previously retained as expired.
- An expiry batch that changes no entry does not advance the collection
  revision. A batch that changes one or more entries advances it exactly once,
  independently of the number of selected entries.
- Adapter errors never cause the library to retry implicitly.

### 6.2 Authorization

```elixir
authorize(state, principal, operation, target, authorization_context)
```

The operation is one of `register`, `get`, `replace`, `patch`, `delete`, `list`,
or `expire`. The target is `collection` or `{:entry, identifier}`.

Authorization runs before repository access for the target. Denial returns the
same typed error whether or not an entry exists. Introduction is deliberately
outside this port and returns only the directory's own Thing Description.

### 6.3 Clock

```elixir
now(state)
```

The callback returns `{:ok, DateTime.t()}`. All timestamps and expiry decisions
use this clock. A replacement, patch, or named registration update rejects a
time earlier than the stored `modified` time as `clock_regression`.

### 6.4 Identifier

```elixir
generate(state)
```

The callback returns an absolute IRI string for an anonymous registration. The
library rejects an empty, relative, or invalid value before repository access.
Collision is reported explicitly; the library does not hide it behind a random
retry count.

## 7. Operation contracts

### 7.1 Register

`register(service, thing_description, context, options \\ [])`:

1. validates the public request shape;
2. authorizes `register` on the collection;
3. validates and normalizes the Thing Description through the core facade;
4. extracts and validates Discovery registration input;
5. obtains the current time from the clock;
6. obtains and inserts an identifier when the Thing Description is anonymous;
7. authorizes a named registration target before any repository fetch;
8. fetches a named identifier to select create or replacement semantics;
9. preserves `created`, assigns `modified`, recalculates relative expiry, and
   advances the version on replacement; and
10. invokes one conditional repository mutation.

The result status is `created` or `replaced`. Registration never creates a
canonical Thing outside the directory.

### 7.2 Get

`get(service, identifier, context)` authorizes before fetch. Missing entries
return `not_found`. An entry whose state is expired or whose `expires` value is
not later than the injected current time returns `expired`. A successful value
sets only the returned registration's `retrieved` time.

### 7.3 Replace

`replace(service, identifier, thing_description, context, options \\ [])`
requires an existing active entry. The incoming Thing Description identifier
must equal the target. The complete value is core-validated before a conditional
repository replacement. The optional `if_version` precondition is checked both
against the fetched entry and atomically by the repository.

### 7.4 Patch

`patch(service, identifier, merge_patch, context, options \\ [])` requires a
JSON-compatible map. It:

1. authorizes and fetches the active entry;
2. renders its enriched JSON-compatible map;
3. rejects client writes to `registration.created`, `registration.modified`,
   or `registration.retrieved`;
4. applies RFC 7396 recursively within configured depth and node bounds;
5. extracts the resulting registration information;
6. rebuilds and validates the base Thing Description through the core facade;
7. rejects identifier removal or mismatch;
8. assigns server timestamps and relative expiry; and
9. conditionally replaces the observed version.

No repository write occurs if merge, registration, identifier, or core
validation fails.

### 7.5 Delete

`delete(service, identifier, context, options \\ [])` authorizes, fetches, and
conditionally deletes the observed or supplied version. It never deletes a
Thing outside the directory.

### 7.6 List and query

`list(service, context, options \\ [])` builds the supported listing query.
`query(service, query, context)` executes an already constructed query. Both
authorize the collection, read the clock, and invoke one repository list call.

The library validates page size, offset, result count, entry state, identifier
order, next offset, and collection revision. Returned entries receive one shared
`retrieved` timestamp without altering persisted values. Each repository-defined
revision is opaque to the library and remains unchanged across its page chain.
If active membership changes because an entry reaches expiry between calls, the
repository returns `collection_changed` rather than an offset into the changed
collection.

### 7.7 Expire

`expire(service, context, options \\ [])` authorizes `expire`, obtains the clock
time, validates the bounded batch limit and selected strategy, and invokes one
`expire_due` repository operation. It starts no timer, process, or job. The
consumer schedules and supervises calls. Retention transitions a due active
entry once; a later retention batch does not select it again. Purge may remove a
previously retained expired entry. A no-op batch leaves collection revision
unchanged.

### 7.8 Introduction

`introduction(service)` returns the configured Introduction value. It invokes no
authorization, repository, clock, or identifier callback. A transport host may
serve the value at the standardized path.

## 8. Error contract

Every public failure is `{:error, %Wotex.Directory.Error{}}`. The stable `code`
set is:

| Code | Meaning |
|---|---|
| `invalid_service` | A required port, callback, bound, or Introduction value is invalid |
| `invalid_context` | Principal or context value is invalid |
| `invalid_request` | Identifier, options, registration input, patch, or query is invalid |
| `invalid_thing_description` | Core Thing Description validation failed |
| `identifier_mismatch` | Target and Thing Description identifiers differ |
| `not_found` | Repository reports no entry |
| `expired` | Entry is not active at the injected clock time |
| `forbidden` | Authorization denied without existence disclosure |
| `conflict` | Insert collision or optimistic version conflict |
| `collection_changed` | A later page cannot honor the requested mutation generation or active-membership snapshot |
| `unsupported_query_profile` | Query asks for an unimplemented profile |
| `invalid_page` | Repository returned an invalid page contract |
| `authorization_failure` | Authorization adapter failed rather than denied |
| `repository_failure` | Repository adapter returned an unknown failure |
| `clock_failure` | Clock adapter failed or returned an invalid value |
| `clock_regression` | Mutation time precedes stored registration history |
| `identifier_failure` | Identifier adapter failed or returned an invalid IRI |

Messages are deterministic and exclude Thing Description bodies, principals,
port states, credentials, and unknown adapter terms. HTTP consumers map these
codes to Problem Details without changing library behavior.

## 9. Security invariants

- No entry repository access precedes authorization for that target.
- Introduction cannot enumerate or retrieve entries.
- Thing Description bodies and principals do not appear in error messages.
- Invalid or identifier-mismatched Thing Descriptions never reach a write port.
- Patch work is bounded by depth and node count before persistence.
- List and expiry work is bounded by consumer-configured maxima.
- Optimistic versions prevent silent lost updates across independent callers.
- Retained expiry is a one-way active-to-expired transition and cannot create
  unbounded version or revision churn on repeated sweeps.
- The library stores security-scheme declarations as part of the Thing
  Description value but never accepts or resolves credentials.
- Loading the package performs no I/O and starts no process.

## 10. Compatibility

The 0.x line may change public types only with a specification, tests, and a
minor version change. Once 1.0 is released:

- adding optional struct fields or error detail keys is backward-compatible;
- adding a required port callback, changing callback result shapes, removing an
  error code, or changing operation ordering is breaking;
- supporting a new query profile requires a separate specification and is not a
  patch release; and
- a new W3C target revision requires explicit vectors and a compatibility
  decision rather than silent reinterpretation.

## 11. Acceptance evidence

| Requirement | Executable evidence |
|---|---|
| No application callback or load-time process | application contract test |
| Consumer ports and callback validation | service tests |
| Named and anonymous registration | directory registration tests |
| Update semantics and optimistic conflict | replacement and conflict tests |
| Retrieval and `retrieved` metadata | retrieval tests |
| RFC 7396 plus validation-before-write | merge patch and patch tests |
| Stable deletion semantics | deletion tests |
| Bounded, ordered, revision-aware listing | query, page, mutation-change, and wall-clock-expiry tests |
| Explicit unsupported search | query-profile test |
| Relative, absolute, retained, purged, and no-op expiry | registration and expiry tests |
| Introduction isolation | Introduction test |
| Deterministic redacted errors | error tests |
| Public archive contents | `mix hex.build` and archive inspection |

## 12. Primary sources

- W3C WoT Discovery Recommendation, 2023-12-05:
  <https://www.w3.org/TR/2023/REC-wot-discovery-20231205/>
- W3C WoT Thing Description 1.1 Recommendation, 2023-12-05:
  <https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/>
- RFC 7396, JSON Merge Patch: <https://www.rfc-editor.org/rfc/rfc7396>
- RFC 3339, date and time on the Internet:
  <https://www.rfc-editor.org/rfc/rfc3339>
- RFC 8288, Web Linking: <https://www.rfc-editor.org/rfc/rfc8288>

Retrieval and interpretation details are recorded in
`docs/provenance/w3c-sources.md`.
