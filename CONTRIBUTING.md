# Contributing

WoTEx is a family of independent packages in one repository. Each package has
its own contract in `packages/<name>/CLAUDE.md` and its own specifications
under `docs/packages/<name>/specs/`. Read both before changing a package.

## Repository layout

| Path | Contents |
| --- | --- |
| `packages/<name>/` | One Mix project per package: `lib`, `test`, `priv`, `bin`, `mix.exs`, `README.md`, `CHANGELOG.md` |
| `docs/packages/<name>/` | The package's specifications (`specs/` with its `catalogue.yaml`), plans, decisions and provenance |
| `docs/architecture/`, `docs/guides/` | Family architecture and cross-package guides |
| `docs/tasks/local/` | Ignored; the only place for machine-local execution state |
| `tooling/` | The package manifest (`packages.yaml`), the images of the native checks and the vendored nanobench of the native benchmarks |
| `.claude/` | Shared agent rules and skills; each `packages/<name>/CLAUDE.md` stays that package's contract |
| `.clang-format`, `.clang-tidy`, `.clang-format-ignore`, `rust-toolchain.toml` | Native formatting, static analysis, exclusions and the Rust toolchain |

`docs/` is for people. Code never reads from `docs/`: fixtures, schemas and
machine-read provenance live in each package's `priv/`. The one exception is
wotex-lab's knowledge graph and MCP resources, which read the documentation
tree as their subject (see `CLAUDE.md`).

## Setup

```sh
mise install        # Erlang, Elixir, Rust and Dexter pinned in mise.toml
mix setup           # dependencies for the root and every package, Dexter index
```

Every command runs from the repository root. The root Mix project
(`:wotex_workspace`, not an umbrella, depending on no package) reads
`tooling/packages.yaml` and runs each package in its own Mix process with
`WOTEX_PATH_DEPS=1`, which resolves sibling packages from `packages/` (allowed
in `dev`, `test` and `docs` only; unset, every package declares Hex
requirements).

## Validation

Validation is proportional to the change:

| When | Command |
| --- | --- |
| While editing | `mix pkg <name> test <files>`, or `mix impact Module fun --run` |
| C, C++ or Rust edited | `mix native.lint --package <name>` (`--fix` formats the changed lines) |
| A package change is ready | `mix check.fast --package <name>` |
| Before a commit | `mix check` (root self-check, full gate for changed packages, fast gate for dependents) |
| Repository-wide change only | `mix check.all` |
| Performance-relevant change, explicit only | `mix bench --package <name>`; `mix native.bench --package <name>` for C, C++ or Rust |

A package's full gate covers its native code: clang-format on changed lines,
clang-tidy and the native tests for C and C++, rustfmt, clippy and `cargo
test` for Rust. `mise.toml` pins the current toolchain (Elixir 1.20.2, OTP
29.0.4, Rust 1.97.1); CI also verifies the declared minimum (Elixir 1.18.4,
OTP 27.3.4.15) and pins LLVM 23 for clang-format and clang-tidy. See the
[development guide](docs/guides/development.md) for Dexter, Dialyzer, native
code, the explicit native lanes and CI.

Benchmarks are not part of any gate. They write Markdown reports to the
package's `bench/output/`, which its HexDocs include.

The full gate of one package is `mix pkg <name> check --no-retry`, the same
as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/<name>`. Add tests
beside the package tests, not in repository-level tooling.

## Command reference

| Command | What it does |
| --- | --- |
| `mix setup` | `deps.get` for the root and every package, then builds the Dexter index. |
| `mix affected [--base REF] [--docs] [--all] [--json] [--detail]` | Changed packages plus their transitive dependents, in dependency order; `--docs` also selects a package whose `docs/packages/<name>/` changed; `--detail` marks each `changed` or `dependent`. |
| `mix pkg NAME ARGS...` | Runs any Mix task inside `packages/NAME` with `WOTEX_PATH_DEPS=1`, e.g. `mix pkg wotex-coap test test/wotex/coap/codec_test.exs`. |
| `mix def MODULE [FUN]` | Dexter lookup; prints the repository-relative `path:line`. |
| `mix refs MODULE [FUN]` | Dexter references, grouped by package and `lib`/`test`, repository-relative. Reindexes changed files first. |
| `mix impact MODULE [FUN] [--run]` | The test files to run for a change: test files referencing the target plus test files referencing the modules that reference it (one hop), grouped by package; `--run` runs them per package. |
| `mix test.affected [--base REF] [--package NAME]... [FILES...]` | Given repository-relative `FILES`, runs them in their packages; otherwise `mix test --stale` in the changed packages and their dependents. |
| `mix check.fast [--package NAME]...` | Inner-loop gate for the selected (default: changed) packages: compile with warnings as errors, format check, `credo --strict`, `mix test`, `mix native.lint` for packages with native code, and the same four Mix steps in each host application a package declares in `tooling/packages.yaml` (wotex-lab's Workbench and Nerves hosts). |
| `mix check [--base REF]` | Pre-commit gate: `mix workspace`, then `mix check.affected` (the arguments go to `check.affected`). |
| `mix check.affected [--base REF]` | The full `mix check --no-retry` for changed packages, `check.fast` for dependents. |
| `mix check.all` | CI-equivalent: workspace checks plus every package's full gate. Heavy; only for repository-wide changes or on explicit request. |
| `mix workspace` | Root self-check: compile, format, credo, root tests, catalogue drift, documentation links, sibling-API boundary of changed packages. |
| `mix format.all [--check] [--all]` | `mix format` in the root and every changed package (`--all`: every package). |
| `mix lint [--package NAME]...` | `credo --strict` in the changed (or named) packages. |
| `mix dialyzer.pkg NAME` | Dialyzer for one package (its PLT is cached per package: in `priv/plts/` where its `mix.exs` sets `plt_file`, otherwise under its `_build/`). Explicit only. |
| `mix docs.check` | Link check over every tracked Markdown file (relative links, main-branch repository URLs, relative links HexDocs cannot resolve, absolute machine paths) plus `mix wotex.catalogue --check`. |
| `mix docs.pkg NAME` | Builds one package's HexDocs, in `MIX_ENV=docs` where the package declares that environment. |
| `mix index [--force]` | Builds or refreshes the Dexter index in `.dexter/`. |
| `mix native.build --package NAME --workspace /abs/dir` | Runs a package's native build task in a disposable absolute workspace. Explicit only. |
| `mix native.sources` | Lists pinned native sources and verifies the digests of files present locally. |
| `mix native.advisories [--offline]` | Queries OSV for advisories against the pinned native sources. |
| `mix native.lint [--all] [--package NAME]... [--base REF] [--fix] [--tidy [--workspace /abs/dir]] [--no-format] [--no-clippy]` | First-party native code of the selected (default: changed) packages: clang-format on the C and C++ lines changed since the merge base (`--fix` applies it), rustfmt and clippy; `--tidy` adds clang-tidy with the compile commands of the package's native build. Vendored files (`.clang-format-ignore`) are skipped. Needs LLVM 22 or later (`brew install llvm`, or `clang-format-23`/`clang-tidy-23` from apt.llvm.org). |
| `mix native.test [--all] [--package NAME]... [--workspace /abs/dir]` | Native tests of the selected packages: `cargo test`, CTest and the test executables of each `native_check` suite in `tooling/packages.yaml`, after its build task. |
| `mix bench [--package NAME]... [--base REF] [--all]` | Elixir benchmarks of the selected (default: changed) packages: each `bench/*_bench.exs` with `mix run` in `dev`, writing `bench/output/<topic>.md`. Explicit only. |
| `mix native.bench --package NAME [--bench ID]... [--workspace /abs/dir]` | C, C++ and Rust benchmarks of one package, declared under `native_bench` in `tooling/packages.yaml`: nanobench drivers built with the LLVM of the native checks, criterion crates with `cargo bench`, and Elixir scripts over the package's native build, which need `--workspace` and are skipped without it. Writes `bench/output/native-<id>.md`. Explicit only. |
| `mix wotex.*` | The underlying tasks remain available: `wotex.affected`, `wotex.check`, `wotex.archive`, `wotex.boundary`, `wotex.catalogue`, `wotex.new` and one task per command above; `mix help wotex.<task>` documents each. |

The default selection of `check`, `boundary` and `archive` is the affected
set. See [tooling/README.md](tooling/README.md) for the manifest format.

## Documentation

- `docs/packages/<name>/specs/` holds the normative specifications and the
  package catalogue (`catalogue.yaml`), which records each specification's
  implementation status.
- `docs/packages/<name>/plans/` holds the versioned completion contract.
- `docs/packages/<name>/provenance/` holds standards provenance and recorded
  evidence.
- Generated HexDocs for a package include its specifications; build them
  with `mix docs.pkg <name>` from the repository root.

## Changes

Begin a behavior change with a normative specification or an accepted issue
that identifies the affected requirement and its evidence vector. Use exact
W3C Web of Things terminology. A standards claim must identify the exact
revision, operation, assumptions, fixture digest and result. Unsupported cells
remain absent rather than documented as planned support.

Do not add a database, application callback, hidden process, consumer-specific
namespace, credential store, transport connection or physical-state authority
to a library package. Do not add an umbrella project. Do not make code read
from `docs/`.

Commits use a conventional prefix and a natural sentence, without
specification or work-package identifiers, and carry the contributor's own
identity. Open an issue before a compatibility-affecting change.
