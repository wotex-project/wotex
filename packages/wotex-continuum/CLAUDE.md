# Wotex Continuum Contract

This file is the canonical repository instruction contract.

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

The only Wotex-family compile dependency allowed is the Wotex core. Never
import a consumer host or a downstream library. External dependencies must be
small, justified, and included in provenance review.

## Change gate

Public wire changes update the owning WCT specification, executable vectors,
tests, implementation, and compatibility classification atomically. Run every
verification command in `README.md` before committing.

## Public boundary

Source, tests, documentation, commit messages, package contents, and generated
documentation must contain no consumer brand, organization-internal path,
credential, or non-public fixture. Synthetic examples use `example` names and
reserved URNs only.

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package; or create equivalent remote state. Only
the human maintainer performs publication.

Every local commit uses `Tobias Bohwalli <hi@futhr.io>` as both author and
committer. Never substitute an agent, tool, bot, or shared contributor identity.
