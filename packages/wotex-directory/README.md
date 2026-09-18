# Wotex Directory

**Storage-neutral W3C WoT Thing Description Directory mechanics for Elixir.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_directory.svg)](https://hex.pm/packages/wotex_directory)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_directory)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_directory.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-directory/LICENSE)

[Installation](#installation) · [Quick start](#quick-start) ·
[Consumer ports](#consumer-ports) · [Discovery semantics](#discovery-semantics) ·
[Boundary](#boundary) · [Development](#development)

---

This development checkout has an unstable public API. Package publication
requires a separately reviewed release.

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

Wotex Directory 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual:

```elixir
def deps do
  [{:wotex_directory, "~> 0.1"}]
end
```

The only production dependency is `wotex ~> 0.1.0`, which owns Thing
Description values and validation.

Until publication, depend on one commit of the
[WoTEx repository](https://github.com/wotex-project/wotex) and select each
package directory with `sparse:`. Declare Wotex Directory and `wotex` at the
same `ref` with `override: true`, as the
[consumer guide](https://github.com/wotex-project/wotex/blob/main/docs/guides/consumer.md)
describes:

```elixir
@wotex_ref "<commit>"

{:wotex,
 git: "https://github.com/wotex-project/wotex.git",
 ref: @wotex_ref,
 sparse: "packages/wotex",
 override: true},
{:wotex_directory,
 git: "https://github.com/wotex-project/wotex.git",
 ref: @wotex_ref,
 sparse: "packages/wotex-directory",
 override: true}
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_directory, path: "../wotex/packages/wotex-directory", override: true}
```

## Quick start

This configuration sketch requires the caller-owned port modules, state,
principal, and Thing Description values shown below.

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

## Consumer ports

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

Port state and returned failure reasons are opaque. Returned adapter failures
become stable `Wotex.Directory.Error` values without retaining unknown reasons.
Adapters must handle their own exceptions; the facade does not rescue them.

## Discovery semantics

The 0.1 series targets the W3C WoT Discovery Recommendation dated 2023-12-05
and Thing Description 1.1. Supported behavior is recorded in
[`WTD.01`](../../docs/packages/wotex-directory/specs/WTD.01-directory-contract.md).
This package does not claim W3C certification and does not implement JSONPath,
XPath, or SPARQL profiles.

Listing is a bounded keyset page chain. `Wotex.Directory.Page` carries its
entries, the repository-defined collection revision, and an opaque
`next_cursor` that a transport host places in the Discovery `next` link. A
cursor binds the revision that issued it to the last listed identifier, so a
mutation ends the chain with `collection_changed` while an entry that reaches
expiry between pages is omitted from the following page. There is no
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

The [specification catalogue](../../docs/packages/wotex-directory/specs/catalogue.yaml)
and [completion contract](../../docs/packages/wotex-directory/plans/wotex-directory-completion.md)
define the work packages, gates and remaining claims. Local execution records
are not part of the published contract.

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-directory test test/wotex/directory/directory_test.exs  # one test file
mix check.fast --package wotex-directory                              # compile, format, Credo, tests
mix pkg wotex-directory check --no-retry                              # full gate
```

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-directory`, and runs in the `test` environment. It compiles
with warnings as errors, checks the lock and unused dependencies, formatting,
`mix deps.audit` and `mix hex.audit`, strict Credo, Doctor,
`mix docs --warnings-as-errors` (in `MIX_ENV=docs`), tests with the coverage
floor (`mix coveralls`), Dialyzer, the consumer-neutral source scan
(`elixir bin/check_boundary.exs`), the package archive
(`bin/check_archive.exs`), the application-free check
(`bin/check_application_free.exs`) and `git diff --check`.

The external release-evidence manifest uses an explicit runner:

```console
mix pkg wotex-directory run --no-start bin/check_release_evidence.exs
```

The runner resolves the locked dependency cohort and executes the same
checks, writing `release-evidence.json` only after every command
succeeds. The archive check builds one Directory archive outside the
repository, compiles an isolated consumer from that archive and an exact core
archive, and runs the repository, interleaving and independent reference-port
suites against two test consumers. It prints both archive SHA-256 digests and
the consumer lock cohort. This establishes archive-only interoperability for
those configured consumers, not production adapter compatibility,
certification or publication to Hex.

`mix pkg wotex-directory package` (inside the package,
`WOTEX_PATH_DEPS=1 mix package`) runs that archive check on its own. The explicit
development switch selects the core source only for building its archive; it
is cleared before both archive construction and consumer execution. To supply
an existing core archive instead, set `WOTEX_CORE_ARCHIVE` to its absolute
path. Set `WOTEX_DIRECTORY_ARCHIVE` as well to repeat the complete archive
verification against an existing Directory artifact without rebuilding it.
No sibling package directory or previously compiled module is a fallback.
Generated consumer files are temporary. The printed artifact directory retains
the archives and consumer lock outside the repository.

The explicit release runner writes an external `release-evidence.json`
manifest after all checks succeed. It binds source and dependency inputs,
runtime, commands, the exact archives, consumer lock and test outcome. The
[claim and compatibility matrix](../../docs/packages/wotex-directory/plans/claim-compatibility-matrix.md)
defines its schema and the reviewed 0.1.0 compatibility baseline. A dirty-tree
run is qualified explicitly; neither a manifest nor a passing gate authorizes
publication or establishes a stable API.

The [repository port evidence contract](../../docs/packages/wotex-directory/plans/repository-port-evidence.md)
defines the reusable adapter suite, its fixture interface, and the exact
callback, authorization, isolation, pagination, expiry, and contention evidence.
The adapters under `test/support/` are test consumers and are not packaged
production storage implementations.

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](https://github.com/wotex-project/wotex/blob/main/CONTRIBUTING.md), and
[security policy](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-directory/security.md).

## License

Wotex Directory is released under Apache-2.0. See
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-directory/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-directory/NOTICE).
