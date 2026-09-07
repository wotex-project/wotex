# Wotex Directory

**Storage-neutral W3C WoT Thing Description Directory mechanics for Elixir.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_directory.svg)](https://hex.pm/packages/wotex_directory)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_directory)
[![CI](https://github.com/wotex-project/wotex-directory/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-directory/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-directory/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-directory)
[![License](https://img.shields.io/github/license/wotex-project/wotex-directory.svg)](LICENSE)

[Installation](#installation) · [Quick Start](#quick-start) ·
[Consumer Ports](#consumer-ports) · [Discovery Semantics](#discovery-semantics) ·
[Boundary](#boundary) · [Development](#development)

---

`wotex_directory` implements the deterministic application mechanics of a W3C
Web of Things Discovery Thing Description Directory: registration, retrieval,
replacement, bounded JSON Merge Patch, deletion, stable listing, expiry, and
the well-known Introduction. Successful mutations can also be projected into
the three lifecycle event values defined by the optional Discovery Events API.

The library is deliberately storage-neutral. A consumer supplies repository,
authorization, clock, and identifier ports; the library owns validation,
operation ordering, optimistic concurrency semantics, and normalized errors.
Every failure is a `Wotex.Directory.Error` with a stable `code`, the `phase`
that refused the request, an optional JSON Pointer `path`, a deterministic
`message`, and `details` carrying the directory operation.

## Installation

```elixir
def deps do
  [{:wotex_directory, "~> 0.1.0"}]
end
```

The only production dependency is `wotex ~> 0.1`, which owns Thing Description
values and validation. For coordinated source development, set
`WOTEX_PATH_DEPS=1` before fetching dependencies to select the sibling checkout
explicitly. Normal builds always resolve the Hex package.

## Quick Start

```elixir
alias Wotex.Directory

{:ok, directory} =
  Wotex.Directory.Service.new(
    repository: {ConsumerRepository, repository_state},
    authorization: {ConsumerAuthorization, authorization_state},
    clock: {ConsumerClock, clock_state},
    identifier: {ConsumerIdentifier, identifier_state},
    introduction: directory_thing_description
  )

context = Wotex.Directory.Context.new!(principal, repository: request_scope)

{:ok, mutation} = Directory.register(directory, thing_description, context)
{:ok, entry} = Directory.get(directory, mutation.entry.identifier, context)
```

`Wotex.Directory.Service` is immutable configuration, not a process. Keep it in
consumer-owned state or pass it explicitly to request handlers.

## Consumer Ports

Nine callbacks form the complete effect boundary:

| Port | Callback | Responsibility |
|------|----------|----------------|
| `Authorization` | `authorize/5` | Decide access before repository reads or writes. |
| `Clock` | `now/1` | Supply every registration, retrieval, listing, and expiry instant. |
| `Identifier` | `generate/1` | Generate an absolute identifier for anonymous registration. |
| `Repository` | `fetch/3` | Fetch one entry without interpreting consumer scope. |
| `Repository` | `insert/3` | Atomically reject identifier collisions. |
| `Repository` | `replace/4` | Atomically enforce the expected entry version. |
| `Repository` | `delete/4` | Atomically delete the expected entry version. |
| `Repository` | `list/5` | Return a bounded keyset page tied to a collection revision. |
| `Repository` | `expire_due/5` | Purge or retain a bounded, ordered set of due entries. |

`Wotex.Directory.Clock.System` is the one port implementation this package
ships: a stateless UTC system clock selected explicitly with
`clock: {Wotex.Directory.Clock.System, nil}`. Nothing installs it implicitly,
and a consumer that owns time supplies its own module. Every other port is
consumer-owned.

Port state and failure reasons are opaque. Adapter failures become stable
`Wotex.Directory.Error` values so infrastructure details do not leak across the
library boundary.

## Discovery Semantics

The 0.1 series targets the W3C WoT Discovery Recommendation dated 2023-12-05
and Thing Description 1.1. Supported behavior is recorded in
[`WTD.01`](docs/specs/WTD.01-directory-contract.md). This package does not claim
W3C certification and does not implement JSONPath, XPath, or SPARQL profiles.

Listing is a bounded keyset page chain. `Wotex.Directory.Page` carries its
entries, the repository-defined collection revision, and an opaque
`next_cursor` that a transport host places in the Discovery `next` link. A
cursor binds the revision that issued it to the last listed identifier, so a
mutation ends the chain with `collection_changed` while an entry that reaches
expiry between pages is simply absent from the following page. There is no
public offset.

`Wotex.Directory.Event.from_mutation/2` derives `thing_created`,
`thing_updated`, or `thing_deleted` data without starting an SSE stream. The
consumer owns event IDs, durable ordering, replay, filtering, authorization,
and transport encoding; those concerns must share the consumer transaction or
outbox boundary when lossless notification is required.

PATCH uses RFC 7396 JSON Merge Patch. `null` removes a member, arrays replace as
whole values, and the merged document is revalidated as a Thing Description
before persistence. Server-owned registration members (`created`, `modified`,
and `retrieved`) cannot be assigned or removed by a patch. Consumers should not
treat Merge Patch as an element-wise array update language.

## Boundary

The consumer owns the database, transactions behind repository callbacks,
supervision, adapter lifetimes, HTTP routing, authentication, authorization
policy, and scheduling of `expire/3`. This package starts no process, defines no
application callback, reads no global application configuration, and owns no
database, filesystem, endpoint, credential, or job.

## Development

```console
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
```

`mix check` is the single local gate: warnings-as-errors compilation, formatting,
unused dependencies, strict Credo, 95% coverage, dependency audits, Doctor,
Dialyzer, HexDocs, boundary checks, Hex archive construction, out-of-tree
archive compilation, and verification that no application callback exists.

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), and
[SECURITY.md](SECURITY.md). Licensed under Apache-2.0; see [LICENSE](LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex-directory/blob/main/NOTICE).
