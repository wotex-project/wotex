# Wotex Directory package contract

Wotex Directory (`packages/wotex-directory`, Hex `wotex_directory`) is a
normal library, not an application host. It owns storage-neutral W3C Web of
Things Discovery values and Thing Description Directory mechanics:
registration, retrieval, replacement, bounded JSON Merge Patch, deletion,
keyset listing, explicit expiry, the well-known Introduction and lifecycle
Event values, behind consumer-supplied repository, authorization, clock and
identifier ports. Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Use the public `wotex` value contracts; do not redefine Thing Description,
  DataSchema, Form, security-scheme, Property, Action or Event semantics
  locally. Physical hardware may be called hardware when that distinction
  matters. Wire field names retain their standardized spelling.
- Do not add an `Application.start/2` callback, supervision tree, singleton,
  process registry, queue, scheduler, database, filesystem store, HTTP server,
  credential store, policy engine, or global configuration.
- The consumer owns process lifetime, persistence, authorization policy,
  scheduling of `expire/3`, transport routing, credentials, and deployment.
- Runtime dependencies may point only to the public `wotex` core package.
- Persistence, authorization, time, and identifier generation enter through
  explicit ports and explicit per-instance state. `Wotex.Directory.Clock.System`
  is the only shipped port implementation and is never installed implicitly.
- Loading the library must not start a process or perform network, filesystem,
  or persistence I/O.
- Public functions return deterministic tagged results. Do not hide failures or
  rescue broad exceptions; adapters handle their own exceptions.
- Authorization precedes storage; patch admission precedes writes;
  expected-version conflicts never retry silently; a failed mutation never
  yields a successful mutation or Event value.
- Keep one module per `.ex` file.
- Distinguish Discovery Recommendation requirements from package choices.
  Report unsupported search profiles and transport features explicitly. This
  library provides no certification.
- Examples use `consumer`, `consumer host`, reserved URNs and synthetic values;
  no non-public fixtures, credentials, customer data or copied proprietary
  prose.
- Implement accepted specifications with tests first. Public signature, port,
  expiry or error changes need a WTD.01 compatibility decision first.

## Where things are

- `lib/wotex/directory.ex`: the public operations (`register`, `get`,
  `replace`, `patch`, `delete`, `list`, `query`, `expire`, `introduction`).
- `lib/wotex/directory/service.ex`: immutable per-instance configuration and
  port validation.
- `lib/wotex/directory/{repository,authorization,clock,identifier}.ex`: the
  consumer ports; `clock/system.ex`: the explicit UTC system clock.
- `lib/wotex/directory/{context,entry,registration,mutation,expiry}.ex`:
  request context, stored entry, Discovery registration information and
  operation results.
- `lib/wotex/directory/{query,cursor,page}.ex`: bounded keyset listing.
- `lib/wotex/directory/event.ex`: `thing_created`, `thing_updated`,
  `thing_deleted` values from a mutation.
- `lib/wotex/directory/introduction.ex`: the well-known Introduction value.
- `lib/wotex/directory/merge_patch.ex`: bounded RFC 7396 merge;
  `thing_descriptions.ex`: conversion between core Thing Descriptions and
  Discovery-enriched documents; `error.ex`: the redacted stable error.
- `bin/check_archive.exs` (alias `mix package`), `bin/package_mirror.exs`,
  `bin/archive_consumer.exs`, `bin/archive_consumer_test.exs`: archive build,
  exclusion mirror and isolated consumer; `bin/check_release_evidence.exs`,
  `bin/evidence.exs`, `bin/check_evidence.exs`, `bin/check_compiler.exs`: the
  release-evidence manifest; `bin/check_application_free.exs`,
  `bin/check_boundary.exs`: application-free and consumer-neutral checks.
- Specifications: `docs/packages/wotex-directory/specs/` (WTD.01, the
  repository port evidence contract and the claim and compatibility matrix;
  `catalogue.yaml` owns status). Completion plan:
  `docs/packages/wotex-directory/plans/wotex-directory-completion.md`.
  Decisions 0001 and 0002 in `docs/packages/wotex-directory/decisions/`.
- Test support in `test/support/wotex/directory/`: `Fixtures` builds Thing
  Descriptions; `RepositoryContract`, `PublicOperationContract` and
  `ReferenceConsumerContract` are the reusable port suites; the memory,
  scoped-memory, table, failure, stub and barrier repositories and the test
  and reference authorization, clock and identifier ports are test consumers.
  The archive consumer copies the files listed in `@support` in
  `bin/check_archive.exs`; a support file the contract suites need must be
  listed there.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-directory test test/wotex/directory/<file>_test.exs`, or `mix impact Wotex.Directory register --run` |
| 1 | `mix check.fast --package wotex-directory` |
| 2 | `mix check.affected` (full gate here, fast gate in `wotex-lab`) |

The full gate alone is `mix pkg wotex-directory check --no-retry`
(equivalently `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-directory`); it adds dependency audits, Doctor, docs, the
coverage floor, Dialyzer, the archive check with its archive-only
repository-port suites, and the application-free check. Run
`mix dialyzer.pkg wotex-directory` in tier 1 when a typespec, a port callback
or an inferred return type changed.

Tests by area, all under `test/wotex/directory/`:

- Public operations end to end: `directory_test.exs`.
- Registration times, ttl and expiry precedence: `registration_test.exs`.
- Merge Patch: `merge_patch_test.exs`. Events: `event_test.exs`.
- Service configuration and the system clock: `service_test.exs`.
- Values (identifier, context, Introduction, cursor, page):
  `value_contract_test.exs`; doctests: `documentation_test.exs`.
- Error codes, malformed input and redaction: `error_contract_test.exs`,
  `robustness_test.exs`; internal boundaries: `internal_contract_test.exs`.
- Accepted 0.1.0 compatibility baseline: `compatibility_test.exs`.
- Port contract suites against two adapters:
  `scoped_memory_repository_contract_test.exs`,
  `table_repository_contract_test.exs`; change the suites themselves in
  `test/support/wotex/directory/*_contract.ex`.
- Passive load: `library_contract_test.exs`. Decimal boundary:
  `dependency_security_test.exs`.
- Package inputs, exclusion mirror and evidence manifests (`bin/`):
  `archive_contract_test.exs`, `package_mirror_test.exs`,
  `evidence_contract_test.exs`, then the full gate for the archive check.

`wotex-lab` is the only package that calls this package's public API: its
directory adapters under `lib/wotex/lab/adapters/directory/` implement the
repository, authorization, clock and identifier ports. Before changing a
public function or port callback, list its callers with
`mix refs Wotex.Directory.Module fun` and the tests to run with
`mix impact Wotex.Directory.Module fun`.

Explicit-only lanes: the release-evidence manifest,
`mix pkg wotex-directory run --no-start bin/check_release_evidence.exs`
(a fresh Directory build; leave `WOTEX_DIRECTORY_ARCHIVE` unset), and the
supplied-archive check,
`WOTEX_CORE_ARCHIVE=/abs/core.tar WOTEX_DIRECTORY_ARCHIVE=/abs/directory.tar mix package`
inside the package. There is no native build, software profile or container
lane.
