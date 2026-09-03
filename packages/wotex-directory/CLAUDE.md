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

## Delivery

Implement accepted repository specifications with tests first. Before a local
commit run formatting, warning-free compilation, tests, documentation, the
package archive build, and a boundary scan. Commits use conventional lowercase
subjects without specification identifiers or automation attribution. Never
configure or push a remote from an agent session.
+

## Git authority

Automated agents must never configure, add, change, or remove a Git remote and
must never run `git push` or any equivalent publication command. Only the human
owner publishes repository history.

Every local commit must use the repository-configured human owner identity from
`git config user.name` and `git config user.email`. Never substitute an agent,
tool, bot, or shared contributor identity.
