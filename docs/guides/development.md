# Development workflow

This guide explains how to work on WoTEx packages without building or testing
the whole repository. The command reference is in
[CONTRIBUTING.md](../../CONTRIBUTING.md#command-reference); the agent-facing summary is the
root [`CLAUDE.md`](../../CLAUDE.md).

## Setup

```sh
mise install        # Erlang, Elixir, Rust and Dexter pinned in mise.toml
mix setup           # dependencies for the root, every package and its hosts, Dexter index
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
| 0 | While editing | `mix pkg <name> test <files>`, `mix impact Module fun --run`; `mix native.lint --package <name>` for C, C++ or Rust | The tests next to the change; native formatting and Rust lint |
| 1 | A package change is ready | `mix check.fast --package <name>` | Compile with warnings as errors, format check, Credo strict, the package's tests, for a package with native code `mix native.lint`, and for a package with host applications (`hosts:` in `tooling/packages.yaml`) the same compile, format, Credo and test steps in each host |
| 2 | Before a commit | `mix check` | `mix workspace`, then the full gate for changed packages and the fast gate for their dependents (`mix check.affected`) |
| 3 | Repository-wide change, CI, explicit request | `mix check.all` | Workspace checks and every package's full gate |

Benchmarks are outside the tiers and run only when invoked; see
[Benchmarks](#benchmarks).

A package's full gate is its `.check.exs`, run by `mix check --no-retry`:
locked dependencies, compilation, formatting, Credo, Doctor, dependency
audits, ExDoc with warnings as errors, tests with the 95% coverage floor,
Dialyzer, the archive check and, where present, the boundary scan
(`bin/check_boundary.exs`) and the application-free check. wotex-lab's gate
also compiles the package without its optional dependencies
(`optional_deps`: `mix compile --no-optional-deps --warnings-as-errors` in
`MIX_ENV=docs` and its own build path, `_build/no_optional_deps`, followed
by `bin/check_optional_deps.exs`, which checks the typed errors of the
features whose dependency is absent) and runs the complete gates of its
reference hosts, `hosts/workbench` and `hosts/nerves` (host target), separate
Mix projects with their own locks. The hosts are declared under `hosts:` in
`tooling/packages.yaml`, so `mix setup` fetches their dependencies and
`mix check.fast --package wotex-lab` compiles, format-checks, lints and tests
them too. A
package with native code adds `native_format`, `native_lint` and
`native_test` (see [Native code](#native-code)), so a green gate means its
Elixir and its C, C++ or Rust code are formatted, linted and tested. `mix check` at the root
means the same for everything a change reaches; `mix check --base REF`
passes the base to `check.affected`.

### Dialyzer

Each package keeps its own PLT (in `priv/plts/` where its `mix.exs` sets
`plt_file`, otherwise under its `_build/`; both are ignored), so after the
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

## Native code

First-party C, C++ and Rust code is formatted, linted and tested like the
Elixir code. Vendored and digest-pinned files are listed in
`.clang-format-ignore` and are never formatted or analysed.

| Step | C and C++ | Rust |
| --- | --- | --- |
| Format | clang-format with the root `.clang-format`, on changed lines | `cargo fmt --check` |
| Lint | clang-tidy with the root `.clang-tidy` | `cargo clippy --all-targets --all-features --locked -- -D warnings` |
| Test | the package's native tests (CTest, test executables, native ExUnit suites) | `cargo test --all-features --locked` |

```sh
mix native.lint --package wotex-coap          # format check on changed lines, rustfmt, clippy
mix native.lint --fix --package wotex-coap    # apply clang-format to the changed lines, cargo fmt
mix native.lint --tidy --package wotex-coap   # add clang-tidy (builds the native workspace)
mix native.test --package wotex-coap          # native tests
```

- **Changed lines.** The C and C++ sources predate `.clang-format`, and
  formatting them whole would rewrite about a fifth of their lines, so the
  check applies to the lines a change touches since the merge base with
  `origin/main` (or `--base REF`), and to new files in full. Lines older than
  the commit that introduced `.clang-format` are not reported until a change
  touches them. `.h` files are C headers and `.hpp` files C++ headers.
- **Tools.** clang-format and clang-tidy 22 or later (CI pins LLVM 23):
  `brew install llvm` on macOS; on Debian or Ubuntu the `clang-format-23`
  and `clang-tidy-23` packages from apt.llvm.org. `CLANG_FORMAT` and
  `CLANG_TIDY` name other executables. Rust comes from `rust-toolchain.toml`
  (`mise install`).
- **Suites.** Each native package declares `native_check` suites in
  `tooling/packages.yaml`: the build task whose workspace provides SDK headers
  and libraries, the compile commands clang-tidy uses, and the test commands.
  Every first-party translation unit needs a compile command from some suite.
- **Workspaces.** A suite's build runs in a cached workspace outside the
  repository, `$WOTEX_NATIVE_CACHE` or `wotex-native` in the system temporary
  directory, keyed by a digest of the package's files other than Markdown
  and by the suite's name and build task: the first run builds, later runs
  of the same sources reuse it, and a workspace the build task refuses is
  rebuilt. `--workspace /abs/dir` names the build task's workspace instead,
  for example one built by `mix native.build`.
- **Linux suites on another host.** A suite that needs Linux (the BlueZ
  D-Bus host and the OpenThread SDK host) runs natively on Linux, as in CI.
  On macOS or another host with a running Docker daemon it runs in the Linux
  container built from `tooling/native/docker/linux.Dockerfile` (Ubuntu
  24.04 with GCC 13, LLVM 23 and the current lane's Elixir, base image pinned
  by digest; the image tag is a digest of the Dockerfile, so the first run
  builds it). The repository is mounted read-only and the native cache
  writable, both at their host paths; Mix keeps the container's dependencies
  and build output in `<cache>/linux-container`. The suite's build, its
  clang-tidy run and its tests run there and report their status to the
  host. Without Linux and without Docker the suite fails with a message
  naming both options. A suite that needs Docker (the Matter SDK build, the
  BACnet and Modbus peers) fails on a host without it. Nothing is skipped
  silently.
- **Suite containers.** A suite may declare a `container` (the Matter `sdk`
  suite does): its prepare and test commands and clang-tidy run in an image
  built from `tooling/native/docker/<name>.Dockerfile`, with volumes that
  map the build's container paths to the workspace and the package. The
  Matter SDK-bound sources are analysed in the image their build runs in
  (`matter-sdk.Dockerfile`, which adds clang-tidy 23) on the compile
  commands ninja exports from that build.
- **Cached results.** clang-tidy results are cached per translation unit in
  the native cache, keyed by the unit's content, its compile command, the
  package's first-party headers, `.clang-tidy` and the clang-tidy version
  (and the image, for a container). A clean unit whose key is unchanged is
  not analysed again; a unit with findings is analysed on every run.
- **Findings.** clang-tidy findings fail the check. A false positive gets a
  `NOLINTNEXTLINE(check)` or `NOLINTBEGIN`/`NOLINTEND` comment with the
  reason; `.clang-tidy` lists each disabled check with its reason.

### Benchmarks

`mix bench` runs a package's Elixir benchmarks (`bench/*_bench.exs`) and
`mix native.bench` its C, C++ and Rust benchmarks, which the package declares
under `native_bench` in `tooling/packages.yaml`. No gate runs either. Each
benchmark writes one Markdown report to the package's `bench/output/`, which
its HexDocs include: the title, a description, the system and toolchain, and
the results.

```sh
mix bench --package wotex                               # Elixir, bench/output/<topic>.md
mix native.bench --package wotex-opcua                  # C, C++, Rust: bench/output/native-<id>.md
mix native.bench --package <name> --bench <id>          # one benchmark
mix native.bench --package <name> --workspace /tmp/wotex-native-<name>   # adds the Elixir benchmarks over the native build
```

- **nanobench.** A C++ driver, `bench/native/<id>.cpp`, includes
  `<nanobench.h>`, measures with `ankerl::nanobench::Bench` and prints
  nanobench's Markdown tables to standard output; first-party C headers are
  included inside `extern "C"`. The benchmark's `compile` rules name the
  driver and the package sources it links, each with its flags; the runner
  adds `-O2 -DNDEBUG`, compiles nanobench's implementation itself (a driver
  does not define `ANKERL_NANOBENCH_IMPLEMENT`) and uses the `clang` and
  `clang++` beside the clang-tidy of the native checks, so the benchmarks
  and the static analysis share one LLVM. nanobench 4.6.0 is vendored in
  `tooling/native/nanobench/`, pinned by commit and SHA-256 in its
  `source.json` and verified before every build. The driver is first-party
  code: clang-format checks it, and clang-tidy analyses it with the
  benchmark's flags (the compile-only suite `bench-<id>`).
- **criterion.** A crate `bench/native/<id>/`, separate from the shipped
  crate so that the shipped manifest and lock stay unchanged, reaches the
  shipped code through a path dependency on its library target (or, for a
  binary-only crate, by including its modules with `#[path]`), commits its
  own `Cargo.lock` and declares `harness = false` benchmarks.
  `cargo bench --benches --locked` runs them with the native cache's target
  directory and a fresh `CRITERION_HOME`; the report tabulates criterion's
  mean, median and standard deviation, and the throughput a benchmark
  declares. rustfmt and clippy check the crate with the package's others.
- **Elixir over the native build.** A script `bench/native/<id>_bench.exs`
  runs with `mix run` in `dev` after the package's `native_task` built the
  `--workspace`, with the benchmark's `env` (the `native_check` placeholders,
  `{workspace}` included) and `WOTEX_BENCH_OUTPUT`, `WOTEX_BENCH_TITLE` and
  `WOTEX_BENCH_DESCRIPTION`. The script writes the report itself, for example
  with Benchee's Markdown formatter (`file:` the output path, `title:` `"# "`
  and the title). Without `--workspace` these benchmarks are skipped, and
  `mix native.bench` says so.
- **Where they run.** As for the suites: a benchmark that requires only
  Linux runs in the Linux container on another host with Docker, and its
  report records that container's system; the container has no Rust
  toolchain, so a criterion benchmark that requires Linux needs a Linux
  host. Build products and scratch files live in the native cache, below
  `<cache>/<package>/bench/<id>`.

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

- **Manifest**: reads the toolchain lanes and the native packages from
  `tooling/packages.yaml` and the Rust toolchain from `rust-toolchain.toml`
  (with `yq`); every other job takes them from its outputs, so the workflow
  repeats none of them.
- **Affected**: `mix wotex.affected --json` selects packages.
- **Workspace**: root compile, format, Credo, tests, catalogue drift, docs
  links, native source pins, `mix native.lint --all` (clang-format on the
  changed lines of every package, rustfmt, clippy) with LLVM 23 from
  apt.llvm.org and Rust 1.97.1, `cargo test` of the Rust crate, the
  sibling-API boundary, and shared-file and LICENSE checks.
- **Check**: every affected package's gate on each lane of
  `tooling/packages.yaml`, minimum (Elixir 1.18.4, OTP 27.3.4.15) and current
  (Elixir 1.20.2, OTP 29.0.4). The minimum lane skips static analysis whose
  results depend on the compiler version, the native tools and wotex-lab's
  host gates (`lanes.minimum.skip`): the hosts are applications built with the
  current toolchain, and the minimum lane verifies library compatibility. It
  still runs wotex-lab's `optional_deps` step. The current lane runs everything,
  including clang-tidy and the native tests, with native build workspaces
  cached per package. The runners are Linux, so the Linux suites run natively; Matter's
  SDK build and its clang-tidy run in Docker.
- **Archive**: package archives and their consumers.
- **Native**: the native and software-profile lanes of every native package
  in `tooling/packages.yaml`, nightly, on dispatch, or on pull requests
  labelled `native`; after the native build it runs `mix native.lint --tidy`
  and `mix native.test` against that build.

## Adding a package

`mix wotex.new <name> --depends-on wotex,wotex-runtime` scaffolds
`packages/<name>/`, `docs/packages/<name>/{specs,plans,provenance}/` (with a
catalogue skeleton and a completion contract) and the manifest entry, then
re-renders `docs/catalogue.yaml`. The package gets the `WOTEX_PATH_DEPS`
switch (sibling path dependencies with `env: :dev`, refused outside
development, test and docs), HexDocs extras and source links at its release
tag, the standard full
gate with archive, application-free and boundary scripts, a `CLAUDE.md`
package contract and a `README.md` with installation and development
sections. Then run `mix pkg <name> deps.get` and
`mix pkg <name> check --no-retry`, and add the package to the package tables
of the root README and `docs/README.md`. A package that gains C, C++ or Rust
code sets `native: true`, declares its `native_check` suites in
`tooling/packages.yaml` and adds the `native_format`, `native_lint` and
`native_test` tools of a native package's `.check.exs` to its own.
