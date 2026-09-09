# Repository Contract

This repository contains the public `wotex_directory` Mix library. It owns
storage-neutral W3C Web of Things Discovery values and Thing Description
Directory mechanics. It is a normal library, not an application host.

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
generated documentation remain consumer-neutral. Do not include consumer brand
names, consumer namespaces or policy, organization-internal paths, non-public
fixtures, credentials, customer data, or copied proprietary prose. Examples use
`consumer`, `consumer host`, reserved URNs, and synthetic values.

## Delivery

Implement accepted repository specifications with tests first. Before a local
commit run formatting, warning-free compilation, tests, documentation, the
package archive build, and a boundary scan. Commits use conventional lowercase
subjects without specification identifiers or automation attribution. Never
perform a remote action from an agent session.

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Release metadata

`CHANGELOG.md` is maintained only by GitOps. Never edit it directly. Because
the initial changelog already exists, once GitOps is configured, the human maintainer prepares the first
release with `mix git_ops.release --override 0.1.0` and later releases with
`mix git_ops.release`. Automated agents must not invoke either release task.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package or release; or create equivalent remote
state. Only the human maintainer performs publication. Never change repository
visibility.

Local commits use the identity already configured by the contributor running
Git. Automated agents must never set or override Git identity; record an agent,
tool, or bot as an author, committer, or co-author; invent a contributor
identity; or remove attribution supplied by a human contributor.
