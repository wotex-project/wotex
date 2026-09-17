# Wotex Directory Package Contract

This package is the public `wotex_directory` Mix library. It owns
storage-neutral W3C Web of Things Discovery values and Thing Description
Directory mechanics. It is a normal library, not an application host.
Repository-wide rules are in the root `CLAUDE.md`.

## Required language

W3C Web of Things vocabulary is canonical in code, documentation, tests, and
commits:

| Meaning | Required term |
|---|---|
| Described entity | Thing |
| State affordance | Property |
| Invokable affordance | Action |
| Asynchronous affordance | Event |
| Description document | Thing Description |

Physical hardware may be called hardware when that distinction matters. Wire
field names retain their standardized spelling.

Consumers use the public `Wotex` value contracts and do not redefine Thing
Description, DataSchema, Form, security-scheme, Property, Action, or Event
semantics locally.

## Library boundary

- Do not add an `Application.start/2` callback, supervision tree, singleton,
  process registry, queue, scheduler, database, filesystem store, HTTP server,
  credential store, policy engine, or global configuration.
- The consumer owns process lifetime, persistence, authorization policy,
  scheduling, transport routing, credentials, and deployment.
- Runtime dependencies may point only to the public `wotex` core package.
- Persistence, authorization, time, and identifier generation enter through
  explicit ports and explicit per-instance state.
- Loading the library must not start a process or perform network, filesystem,
  or persistence I/O.
- Public functions return deterministic tagged results. Do not hide failures or
  rescue broad exceptions.
- Keep one module per `.ex` file.

## Standards claims

Pin every W3C claim to an exact published revision and distinguish Recommendation
requirements from package choices. Unsupported search profiles and transport
features must be reported explicitly. This library provides no certification.

## Public boundary

Source, tests, specifications, documentation, commits, package contents, and
generated documentation remain consumer-neutral. Consumer, company and customer
names stay out, as do consumer namespaces or policy, non-public fixtures,
credentials, customer data, and copied proprietary prose. Sibling packages are
referenced by package name; relative paths inside the repository are allowed,
absolute machine paths are not. Examples use `consumer`, `consumer host`,
reserved URNs, and synthetic values.

## Documentation and local state

Specifications, the completion plan, decisions and provenance live under
`docs/packages/wotex-directory/`; `docs/packages/wotex-directory/specs/catalogue.yaml`
owns normative status. Machine-local execution records live only in the
ignored root `docs/tasks/local/wotex-directory/`.

## Delivery

Implement accepted package specifications with tests first. Commits use
conventional lowercase subjects without specification identifiers. Never
perform a remote action from an agent session.

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-directory`
before a local commit, then the gate of every dependent package. It compiles
with warnings as errors, checks formatting, dependencies, Credo, Doctor,
ex_doc, coverage, Dialyzer, the package archive with its archive-only
repository-port suites, and the application-free boundary. The external
release-evidence manifest is written separately by
`bin/check_release_evidence.exs`. This evidence covers the configured
consumers, not arbitrary production adapters.

## External automation boundary

This package exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-package
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral package contract.
