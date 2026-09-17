# Wotex Continuum Contract

This file is the instruction contract for the `wotex-continuum` package.
Repository-wide rules are in the root `CLAUDE.md`.

## Scope

`WotexContinuum.*` owns inert, host-neutral continuum exchange values. It does
not own Thing Description semantics, canonical Thing state, identity, policy,
provider selection, dispatch, persistence, jobs, UI, or release supervision.

## W3C Web of Things vocabulary

Use Thing, Thing Description, Property, Action, Event, Consumer, Exposer,
interaction affordance, Form, and DataSchema exactly as defined by the cited
W3C Web of Things documents. Wotex public types and specifications are the
Elixir vocabulary authority. Consumer hosts import those terms and do not
redefine them.

Continuum fields are project-defined. Never represent them as W3C-standard
fields or imply W3C certification.

## Runtime rules

- No `Application.start/2` callback or dependency-start side effect.
- No hidden process, supervisor, registry, agent, task, network client, or
  mutable global state.
- No database, migration, filesystem authority, job system, web framework, or
  ambient application configuration.
- Constructors and codecs are deterministic, total over documented input, and
  return typed errors.
- Action intent and result remain data; no module dispatches an Action.
- Consumer hosts own clocks, identity, authorization, persistence, I/O,
  supervision, retries, and reconciliation.

## Dependency direction

The only Wotex-family compile dependency allowed is the `wotex` core package.
Never import a consumer host or a downstream library. External dependencies
must be small, justified, and included in provenance review.

## Change gate

Public wire changes update the owning WCT specification under
`docs/packages/wotex-continuum/specs/`, executable vectors, tests,
implementation, and compatibility classification atomically. Run
`WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-continuum` before
a local commit, then the gate of every dependent package.

## Public boundary

Consumer, company and customer names stay out of source, tests, documentation,
commit messages, package contents, and generated documentation, as do
credentials and non-public fixtures. Sibling packages are referenced by package
name; relative paths inside the repository are allowed, absolute machine paths
are not. Synthetic examples use `example` names and reserved URNs only.
