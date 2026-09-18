# Development workflow

This guide explains how to work on WoTEx packages without building or testing
the whole repository. The command reference is in the root
[README](../../README.md#working-on-a-package); the agent-facing summary is the
root [`CLAUDE.md`](../../CLAUDE.md).

## Setup

```sh
mise install        # Erlang, Elixir and Dexter pinned in mise.toml
mix setup           # dependencies for the root and every package, Dexter index
```

The root project is a tooling project. It never loads package code; every
package command runs in the package's own Mix process with `WOTEX_PATH_DEPS=1`,
so sibling packages resolve from `packages/`.

## Finding code and its reach

[Dexter](https://github.com/remoteoss/dexter) indexes every package, its tests
and its dependencies. The root commands wrap it and print paths relative to
the repository root:

| Question | Command |
| --- | --- |
| Where is it defined? | `mix def Wotex.Runtime.ConsumedThing read_property` |
| Who calls it, in every package? | `mix refs Wotex.Runtime.ConsumedThing read_property` |
| Which tests cover a change to it? | `mix impact Wotex.Runtime.ConsumedThing read_property` |

`mix impact` lists the test files that reference the function, plus the test
files that reference the library modules calling it, grouped by package;
`--run` runs exactly those files. `mix refs` and `mix impact` refresh the index
for changed files first. `mix index --force` rebuilds it.

Dexter is navigation. It does not type-check and does not replace Dialyzer or
tests.

## Validation tiers

| Tier | When | Command | Runs |
| --- | --- | --- | --- |
| 0 | While editing | `mix pkg <name> test <files>`, `mix impact Module fun --run` | The tests next to the change |
| 1 | A package change is ready | `mix check.fast --package <name>` | Compile with warnings as errors, format check, Credo strict, the package's tests |
| 2 | Before a commit | `mix check.affected` | The full gate for changed packages; the fast gate for their dependents |
| 3 | Repository-wide change, CI, explicit request | `mix check.all` | Workspace checks and every package's full gate |

A package's full gate is its `.check.exs`, run by `mix check --no-retry`:
locked dependencies, compilation, formatting, Credo, Doctor, dependency
audits, ExDoc with warnings as errors, tests with the 95% coverage floor,
Dialyzer, the archive check and, where present, the application-free check.

### Dialyzer

Each package keeps its own PLT under `priv/plts/` (ignored), so after the
first build a package's Dialyzer run is incremental. Run it explicitly with
`mix dialyzer.pkg <name>` when a typespec, callback or inferred return type
changed; otherwise tier 2 runs it for changed packages only. There is no
repository-wide Dialyzer run.

### What a change reaches

- A protocol adapter, binding, `wotex-nx`, `wotex-directory`,
  `wotex-continuum` or `wotex-conformance` change reaches that package (and
  `wotex-lab` for the non-adapters).
- A `wotex` or `wotex-runtime` change reaches every dependent. Use
  `mix impact` to run the dependents' tests that actually touch the changed
  function before the tier-2 gate.
- Root tooling, `tooling/packages.yaml`, `mise.toml`, root `mix.exs` or CI
  reach every package.

`mix affected --detail` shows the selection and why.

## Explicit lanes

Native builds, software profiles, interop suites and containment lanes need
external tools (C/C++ toolchains, Docker, SDK sources) and a disposable
absolute workspace. They never run implicitly:

```sh
mix native.build --package wotex-opcua --workspace /tmp/wotex-native-opcua
mix pkg wotex-coap wotex.coap.software.run --workspace /tmp/wotex-coap-software
mix native.sources                # verify pinned native source digests
mix native.advisories             # OSV advisories for pinned native sources
```

Each package's `CLAUDE.md` and README list its lanes and prerequisites.

## Continuous integration

`.github/workflows/ci.yml` runs one workflow:

- **Affected**: `mix wotex.affected --json` selects packages.
- **Workspace**: root compile, format, Credo, tests, catalogue drift, docs
  links, native source pins, the sibling-API boundary, and shared-file and
  LICENSE checks.
- **Check**: every affected package's gate on two lanes, minimum
  (Elixir 1.18.4, OTP 27.3.4.15) and current (Elixir 1.20.2, OTP 29.0.4). The
  minimum lane skips static analysis whose results depend on the compiler
  version (`lanes.minimum.skip` in `tooling/packages.yaml`); the current lane
  runs everything.
- **Archive**: package archives and their consumers.
- **Native**: the native and software-profile lanes, nightly, on dispatch, or
  on pull requests labelled `native`.

## Adding a package

`mix wotex.new <name> --depends-on wotex,wotex-runtime` scaffolds
`packages/<name>/`, `docs/packages/<name>/` and the manifest entry, with the
standard gate, `CLAUDE.md` template and WOTEX_PATH_DEPS switch.
