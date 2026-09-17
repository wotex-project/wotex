# Package graph and boundaries

## Dependency graph

```text
                         wotex
                           |
      +-------------+------+------+----------------+
      v             v             v                v
wotex-runtime  wotex-directory  wotex-nx     wotex-continuum
      |
      +--> bindings:  wotex-binding-http, wotex-binding-mqtt
      +--> protocols: wotex-bacnet, wotex-ble, wotex-coap, wotex-matter,
                      wotex-modbus, wotex-opcua, wotex-thread

wotex-conformance      no WoTEx dependency

wotex-lab      --> wotex, wotex-nx; optional wotex-runtime, wotex-directory,
                   wotex-binding-http, wotex-binding-mqtt, wotex-continuum;
                   wotex-conformance in dev and test
```

No package depends on a binding or protocol adapter. `wotex-lab` is the only
package that depends on more than two siblings, and it is the family's
consumer laboratory: it proves that the other packages work as released
archives, not as path dependencies.

## What a change affects

| Changed package | Packages whose gate must run |
| --- | --- |
| `wotex` | every package |
| `wotex-runtime` | both bindings, all seven protocol adapters, `wotex-lab` |
| `wotex-directory`, `wotex-nx`, `wotex-continuum`, `wotex-conformance`, a binding | itself and `wotex-lab` |
| a protocol adapter | itself only |
| `wotex-lab` | itself only |
| repository-level files (`tooling/`, `.github/`, root configuration) | every package |

## Boundaries between packages

- A package uses only the public, documented API of a sibling: modules
  without `@moduledoc false`, functions without `@doc false`. A call into a
  sibling's hidden module compiles but is a boundary violation.
- Sibling dependencies are declared in `mix.exs` and resolved either from Hex
  (default) or, with `WOTEX_PATH_DEPS=1`, from `packages/<name>` for
  development, test and documentation builds only.
- Library packages start no process, read no application environment and
  perform no network or filesystem access on load. Long-lived work is returned
  to the consumer as child specifications.
- Transports implement `Wotex.Runtime.Transport`; credentials implement
  `Wotex.Runtime.Credentials`. Nothing is discovered from application
  environment or a global registry; the consumer passes implementations
  explicitly.
- Consumer products, companies and customers are never named. Integration
  boundaries say `consumer` or `consumer host`.

## Consumers outside the repository

Products and third-party adapters depend on published packages. Until
publication they depend on one commit of this repository, declaring every
WoTEx package they use with `git:` and `sparse: "packages/<name>"` at the same
`ref`, with `override: true`, or with path dependencies into
`../wotex/packages/<name>` for local development.
