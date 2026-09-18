# Consuming WoTEx packages

WoTEx packages are independent Hex packages that happen to live in one
repository. A consumer depends on packages, never on the repository as a
whole.

## Published packages

Once a package is on hex.pm, depend on it as usual:

```elixir
{:wotex, "~> 0.1"},
{:wotex_runtime, "~> 0.1"}
```

Publication order follows the package graph: `wotex` first, then
`wotex_runtime`, then bindings and adapters. Nothing is published yet.

## Before publication: one repository commit

Until publication, depend on one commit of this repository and select the
package directory with `sparse:`. Declare every WoTEx package you use,
directly or transitively, at the same `ref`, with `override: true`, because
the packages' own `mix.exs` files declare Hex requirements for their
siblings:

```elixir
@wotex_ref "<commit>"

{:wotex, git: "https://github.com/wotex-project/wotex.git", ref: @wotex_ref,
  sparse: "packages/wotex", override: true},
{:wotex_runtime, git: "https://github.com/wotex-project/wotex.git", ref: @wotex_ref,
  sparse: "packages/wotex-runtime", override: true},
{:wotex_binding_http, git: "https://github.com/wotex-project/wotex.git", ref: @wotex_ref,
  sparse: "packages/wotex-binding-http", override: true}
```

Record the commit in one place and move all packages together.

## Local development beside a checkout

With this repository checked out next to your project, path dependencies
point into `packages/`:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true}
```

Path dependencies prove nothing about a released artifact; they are for
development only.

## What a consumer owns

Every package is passive: it starts no process, reads no application
environment and performs no I/O on load. The consumer owns canonical Thing
state, identifiers, credentials, policy, endpoint selection, persistence,
supervision, retries and proof of physical effects. Transports and credential
resolvers are passed explicitly (`Wotex.Runtime.Transport`,
`Wotex.Runtime.Credentials`); nothing is discovered from a registry.

## Documentation

Each package's specifications are published with its HexDocs and live in
this repository under `docs/packages/<name>/`. Package archives do not
contain Markdown documentation.
