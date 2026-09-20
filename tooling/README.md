# Repository tooling

`tooling/` holds repository-level scripts and data that no package ships.

| Path | Contents |
| --- | --- |
| `packages.yaml` | The package manifest: the dependency graph, lane metadata and the globs that select every package. |
| `native/docker/` | The images of the native checks: `linux.Dockerfile` (Linux-only suites and benchmarks on another host), `matter-sdk.Dockerfile` (clang-tidy for the Matter SDK build), and the entry point and Mix wrapper of the Linux container (`suite.sh`, `bin/mix`). |
| `native/nanobench/` | nanobench 4.6.0 (MIT), the single-header C++ benchmark library of `mix native.bench`: `nanobench.h`, its `LICENSE` and `source.json`, which pins the upstream commit and the SHA-256 of each file. `mix native.sources` verifies the digests and `mix native.advisories` queries OSV for the pin; `.clang-format-ignore` excludes the directory. |

The root Mix project (`mix.exs` at the repository root, app `:wotex_workspace`)
implements the `mix wotex.*` tasks that read the manifest. It is not an
umbrella and depends on no package; it runs each package's own Mix project in
a separate OS process with `WOTEX_PATH_DEPS=1`. `mix help wotex.affected`
and the other `mix help wotex.*` pages document each task.

The root `mix.exs` aliases give the tasks their short names (`mix setup`,
`mix affected`, `mix impact`, `mix check.fast`, ...); the table in
`CONTRIBUTING.md`, "Command reference", is the command set. Mix appends an
alias's arguments to its last task, so every alias ends in the `wotex.*` task
that takes them.

## Toolchain and code index

The root `mise.toml` pins Erlang/OTP, Elixir, Rust and Dexter. Its `erlang`
and `elixir` versions equal `lanes.current` in `packages.yaml`, and its `rust`
version equals the channel of `rust-toolchain.toml` (with rustfmt and
clippy); workspace tests assert both, so change them together. Run
`mise install` once, then `mix setup`. clang-format and clang-tidy (LLVM 22
or later; CI pins 23) come from the system: `brew install llvm`, or the
`clang-format-23` and `clang-tidy-23` packages from apt.llvm.org.
`mix native.bench` compiles with the `clang` and `clang++` in the directory
of that clang-tidy (`clang-23` from apt.llvm.org). The images
in `native/docker/` pin their base images by digest and install the same
LLVM major; the Linux image carries the current lane's Elixir and OTP.
Workspace tests assert that these pins agree with `packages.yaml`,
`.github/workflows/ci.yml` and the Matter SDK build image.

The root `.clang-format`, `.clang-tidy` and `.clang-format-ignore` configure
the native checks of every package (`mix native.lint`, `mix native.test`;
see the development guide, "Native code"). A change to any of them, to
`rust-toolchain.toml` or to `mise.toml` selects every package.

Dexter's index lives in the ignored `.dexter/`. `mix index` builds it (`dexter
init .`) or refreshes it (`dexter reindex`, changed files only); `--force`
rebuilds it. `mix def`, `mix refs` and `mix impact` refresh it before every
query and print repository-relative paths. `mix impact MODULE [FUN]` selects:

- test files that reference the target;
- one hop away, test files that reference the module enclosing each library
  or test-support reference (found by parsing that file);
- `mix test --stale` for a package with library references, or the
  definition, but no selected test file.

References in `deps/`, `_build/`, root files and package files outside `lib/`
and `test/` select nothing.

## Validation tiers

| Tier | When | Command |
| --- | --- | --- |
| 0 | While editing | `mix pkg NAME test FILES` or `mix impact MODULE [FUN] --run`; `mix native.lint --package NAME` for C, C++ or Rust |
| 1 | Change ready in one package | `mix check.fast --package NAME` |
| 2 | Before a commit | `mix check`: `mix workspace`, then `mix check.affected` (the full gate for changed packages, the fast gate for dependents) |
| 3 | CI, repository-wide changes, explicit request | `mix check.all`, native lanes |

The fast gate runs `compile --warnings-as-errors`, `format
--check-formatted`, `credo --strict` and `test` with `MIX_ENV=test`, and for a
package with native code `mix native.lint --package NAME` in the root,
stopping at the first failure. Dialyzer, clang-tidy and the native tests run
in the full gate: a native package's `.check.exs` runs the root `mix
native.lint --no-clippy` (`native_format`), `mix native.lint --tidy
--no-format` (`native_lint`) and `mix native.test` (`native_test`), so the
full gate needs the root dependencies (`mix setup`).

Benchmarks are outside the tiers: `mix bench --package NAME` (Elixir) and
`mix native.bench --package NAME` (C, C++ and Rust) run only when invoked,
and each writes its Markdown reports to the package's `bench/output/`.

## `packages.yaml`

An excerpt:

```yaml
schema_version: "1.0.0"
native_artifact:
  schema_version: "1.0.0"
  matrix_limit: 32
  max_slices: 16
  toolchains: {}
  systems: {}
  targets: {}
  smoke: []
lanes:
  minimum:
    elixir: "1.18.4-otp-27"
    otp: "27.3.4.15"
    skip: [formatter, credo, doctor, dialyzer, ex_doc, mix_audit, hex_audit, diff, api_surface]
  current: { elixir: "1.20.2-otp-29", otp: "29.0.4" }
select_all_on:
  - ".github/**"
  - "tooling/**"
  - "mix.exs"
  - "lib/**"
packages:
  wotex:
    app: wotex
    depends_on: []
  wotex-coap:
    app: wotex_coap
    depends_on: [wotex, wotex-runtime]
    native: true
    native_task: wotex.coap.native.build
    software_task: wotex.coap.software.run
    native_artifacts:
      - profile: production
        descriptor: priv/native-artifacts/production.json
```

| Key | Meaning |
| --- | --- |
| `schema_version` | Version of this file's format. |
| `native_artifact` | Closed native artifact inventory. It declares admitted toolchains, systems, target tuples, planner bounds and smoke cells; package descriptors may refer only to these names. |
| `lanes.<name>.elixir`, `lanes.<name>.otp` | Toolchain lanes the package gates run on in CI. `mix wotex.check --lane NAME` prints a lane and warns when the running Elixir differs; CI selects the toolchain. |
| `lanes.<name>.skip` | `mix check` tools the lane does not run; CI and `mix wotex.check --lane NAME` pass each as `--except TOOL`. The minimum lane skips static analysis whose results depend on the compiler and OTP version. |
| `select_all_on` | Repository-relative globs (`**` spans directories, `*` stays within a segment). A changed path matching any of them selects every package. |
| `packages.<name>` | One entry per directory under `packages/`. The key is the directory name. |
| `app` | The OTP application and Hex package name. |
| `depends_on` | The WoTEx packages this package requires directly. Dependents are derived; a change in a package selects it and every transitive dependent. The graph must be acyclic and every name must exist. |
| `native` | `true` when the package builds or vendors native code. `mix native.sources` and `mix native.advisories` cover native packages only. |
| `native_task` | The package's own build task, dispatched by `mix native.build --package NAME --workspace /abs/dir`. |
| `software_task` | The package's own software-profile task, if any. The CI native lane runs it with `--workspace`; locally it runs only when invoked explicitly, e.g. `mix pkg NAME TASK --workspace /abs/dir`. |
| `native_artifacts` | Explicit profile-to-descriptor admissions. Filesystem discovery never creates artifact profiles. `mix native.inspect` inspects one package by default; `mix native.inspect --all` is required for the complete inventory. |
| `native_check` | Suites for `mix native.lint --tidy` and `mix native.test`: `suite` (name), `requires` (`linux`, `docker`, `tun`), `build` (a package task run with `--workspace`), `prepare` (commands), `compile_commands` (databases the build or `prepare` wrote), `compile` (`files` globs and `flags` for files compiled outside a build system), `test` (commands) and `container` (`dockerfile`, `platform`, `volumes`: run `prepare`, `test` and clang-tidy in that image). Strings take the placeholders `{package}`, `{root}`, `{workspace}` and `{scratch}`; a flag `pkg-config:NAME` expands to `pkg-config --cflags NAME`. On a host that is not Linux, a suite that requires only `linux` (optionally with `tun`, a tun device and `CAP_NET_ADMIN`, which the container is given) runs in the Linux container (`native/docker/linux.Dockerfile`) when Docker is available. See `Wotex.Workspace.NativeSuite` and `Wotex.Workspace.NativeContainer`. |
| `native_bench` | Benchmarks for `mix native.bench`, each reported in `bench/output/native-<id>.md` of the package: `bench` (the id: lowercase letters, digits and underscores), `kind`, `title` and `description` (the report's heading and first paragraph), `requires` and `env` (the environment of the benchmark process), and for `nanobench` also `compile` (`files` globs and `flags`) and `link` (linker flags). The kind fixes the source: `nanobench` a C++ driver `bench/native/<id>.cpp`, which `compile` must match, built with the package sources `compile` names and the vendored nanobench; `criterion` a Cargo crate `bench/native/<id>/` with a committed `Cargo.lock`, run with `cargo bench`; `elixir` a script `bench/native/<id>_bench.exs`, run with `mix run` after the package's `native_task` built `--workspace` (the package must declare one). Strings take the `native_check` placeholders, `{workspace}` in the `elixir` kind only; `pkg-config:NAME` expands to `--cflags` in `compile` and to `--libs` in `link`. A `nanobench` or `elixir` benchmark that requires only Linux, optionally with `tun`, runs in the Linux container on another host; the container has no Rust toolchain. Each driver also gives clang-tidy its compile commands, as the compile-only suite `bench-<id>`. The package must be `native: true`. See `Wotex.Workspace.NativeBench` and `Wotex.Workspace.NativeBenchRunner`. |

`mix wotex.new NAME` appends a manifest entry; the manifest is validated
whenever a task loads it.

`mix native.plan` refines the existing affected-package graph into deterministic
package/profile/target/toolchain/system cells. It performs no build or network
access. Use `--json` for CI, `--count` to inspect expansion and `--all` only for
an explicit repository-wide plan. An unavailable diff reports its smoke-cohort
fallback instead of returning an apparently empty plan.

## Affected packages

`mix wotex.affected` derives the changed paths from `git diff --name-only
<base>...HEAD` plus the working tree, then applies these rules:

- `packages/<name>/...` selects `<name>` (marked `changed`) and every
  transitive dependent (marked `dependent`);
- `docs/packages/<name>/...` selects nothing (documentation only) unless
  `--docs` is given;
- a path matching `select_all_on` selects every package, each marked
  `changed`.

The result is always in topological order, so `mix wotex.check` runs a
package after the packages it depends on. `--json` prints a flat list of
names (CI reads it); `--detail` adds the marks. `mix check.fast`, `mix lint`,
`mix format.all`, `mix native.lint` and `mix native.test` default to the
`changed` packages; `mix check.affected` and `mix test.affected` use both
marks.

## Documentation links

`mix docs.check` reads every Markdown file Git tracks and checks each link
(inline links, images and reference definitions, outside code):

- a relative target must exist; anchors are stripped and not checked;
- a `https://github.com/wotex-project/wotex/blob/main/...` (or
  `/tree/main/...`) URL must name a path that exists in the working tree;
- in `docs/packages/<name>/**` and `packages/<name>/README.md`, which HexDocs
  publishes, a relative link to a `.md` file outside the package's two trees
  is reported with the main-branch URL to use instead.

Other URLs are skipped. It also reports absolute machine paths (a user home
or a system temporary directory), prints each finding as `file:line: ...`
and runs `mix wotex.catalogue --check`.

## Family catalogue

`mix wotex.catalogue` renders `docs/catalogue.yaml` from every
`docs/packages/<name>/specs/catalogue.yaml`. Paths follow the convention in
`docs/README.md`, "Catalogue paths": `docs/...` is relative to
`docs/packages/<name>/`, anything else to `packages/<name>/`. Every resolved
path must exist. `mix wotex.catalogue --check` fails when the committed file
is stale.
