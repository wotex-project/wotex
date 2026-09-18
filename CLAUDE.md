# WoTEx repository contract

This repository holds the WoTEx package family: 16 independent Mix projects
under `packages/` and a root tooling project that drives them. Each
`packages/<name>/CLAUDE.md` is that package's contract and governs work inside
it. This file governs the repository as a whole and applies everywhere.

## Working loop

Every command runs from the repository root. Validation is proportional to the
change; see `.claude/rules/affected-validation.md` and the `monorepo-workflow`
skill.

| Step | Command |
| --- | --- |
| Once | `mix setup` (dependencies for root and packages, Dexter index) |
| Find a definition | `mix def Module [fun]` |
| Find callers in every package | `mix refs Module [fun]` |
| Tests that cover a change | `mix impact Module [fun]` (`--run` runs them) |
| Run anything in a package | `mix pkg <name> <task> [args]`, e.g. `mix pkg wotex-coap test test/wotex/coap/blockwise_test.exs` |
| Package ready | `mix check.fast --package <name>` (includes `mix native.lint` for native packages) |
| C, C++ or Rust changed | `mix native.lint --package <name>` (`--fix` formats); `--tidy` and `mix native.test --package <name>` before the commit |
| Benchmarks (explicit only) | `mix bench --package <name>`; `mix native.bench --package <name>` for C, C++ and Rust (`--workspace /abs/dir` adds the Elixir benchmarks over the native build) |
| Before a commit | `mix check` (root self-check, full gate of changed packages, fast gate of dependents) |
| Repository-wide change only | `mix check.all` |

- Never run every package's gate, Dialyzer across packages, or the native,
  software-profile, interop or containment lanes for a bounded change.
  Benchmarks run only on request; reports land in the package's
  `bench/output/`.
- A package gate (`mix check` inside the package) formats, lints and tests
  its first-party C, C++ and Rust code too: `native_format`, `native_lint`
  (clang-tidy, clippy) and `native_test` run the root `mix native.lint` and
  `mix native.test`, which build into a cached workspace outside the
  repository. Format checks apply to changed lines; vendored and pinned files
  (`.clang-format-ignore`) are never reformatted.
- Run `mix dialyzer.pkg <name>` when a typespec, callback or inferred return
  type changed; otherwise the pre-commit gate runs Dialyzer for changed
  packages only.
- Use `mix refs`/`mix impact` before changing a public function; other packages
  may depend on it (`docs/architecture/package-graph.md`).
- Inside a package the plain commands work too:
  `WOTEX_PATH_DEPS=1 mix test`, `WOTEX_PATH_DEPS=1 mix check --no-retry`.

## Layout invariants

- `packages/<name>/` is a normal Mix library or application. Never add an
  umbrella (`apps_path`), a root release, or a root project that depends on a
  package. The root project only runs package Mix processes.
- Package directories keep their names; sibling path dependencies are
  `{app, path: Path.expand("../<name>", __DIR__), env: :dev, override: true}`
  and resolve inside `packages/`. `env: :dev` keeps a sibling's own
  `WOTEX_PATH_DEPS` guard satisfied when it is built as a dependency.
- `WOTEX_PATH_DEPS=1` is the only sibling switch, allowed in `dev`, `test` and
  `docs`. Unset means Hex requirements. Never add another mechanism.
- `tooling/packages.yaml` is the single source of the package graph, the CI
  toolchain lanes and each package's native tasks. `mise.toml` pins the local
  toolchain and must match the current lane.
- `docs/` is for people. Code never reads from `docs/`. Fixtures, schemas,
  vectors and machine-read provenance live in `packages/<name>/priv/` or
  `test/support/`. The one exception is wotex-lab's documentation-backed
  development features (the knowledge graph and its MCP resources): they read
  the documentation tree as their subject, only through
  `Wotex.Lab.Documentation`, and report it unavailable in a released archive.
  No other package code may read `docs/`.
- `docs/packages/<name>/` mirrors the package it documents: `specs/` (with
  `catalogue.yaml` as the normative status owner), `plans/`, `decisions/`,
  `provenance/`. `docs/catalogue.yaml` is generated (`mix wotex.catalogue`);
  never edit it by hand.
- Machine-local execution state (trackers, progress notes, patches, receipts
  in progress) lives only in the ignored `docs/tasks/local/<name>/`. It never
  enters Git, package archives or generated documentation.
- Package archives ship code, `priv/`, `README.md`, `CHANGELOG.md`, `LICENSE`
  and `NOTICE` and, only where the package's shipped Mix tasks need them, its
  native sources and the test assets those tasks run (today native sources in
  wotex-ble, wotex-coap, wotex-matter, wotex-opcua and wotex-thread, test
  assets in wotex-coap and wotex-matter). wotex-lab also ships the Rust source
  of its containment launcher (`priv/conformance/native/`), which a consumer
  of the containment profile builds and pins itself; the archive carries no
  launcher binary. The package's archive check (`bin/check_archive.exs`, or
  `bin/check_package.exs`) is the authority for its exact contents. Archives
  never ship Markdown documentation, governance files, agent files or check
  scripts; notes inside a shipped native source tree are part of that tree.
  Specifications reach consumers through HexDocs.

## Naming and neutrality

- Use W3C Web of Things terms exactly: Thing, Thing Description, Property,
  Action, Event, DataSchema, Form, Interaction Affordance, security scheme,
  ConsumedThing, ExposedThing.
- No consumer product, company or customer names appear in source, tests,
  docs, fixtures, history or metadata. Say `consumer` or `consumer host` at
  integration boundaries.
- Sibling packages are referenced by package name. Relative paths inside this
  repository are allowed; absolute machine paths are not.
- A package uses only the public, documented API of a sibling package. Calling
  a sibling's `@moduledoc false` module or `@doc false` function is a boundary
  violation even though it compiles; `mix wotex.boundary` rejects it.

## Specifications and evidence

- Every standards claim pins the exact revision and executable evidence.
- Specifications and completion plans are versioned contracts; a changed
  obligation or public seam needs a new version, mirrored in the package
  `catalogue.yaml`. Execution status stays in `docs/tasks/local/`.
- Recorded evidence names the commit of this repository and the package path.
  Evidence recorded before the files it covers moved or changed is stale and
  must be re-run, never re-digested by hand.

## Release metadata

Each package keeps its own `CHANGELOG.md` and version. Changelogs are
maintained only by the release tooling; never edit them directly. Tags use the
form `<package>-v<version>`. Only the human maintainer prepares or publishes a
release; automated agents never invoke a release task.

## Git authority

Automated agents never configure, add, change or remove a Git remote; push;
create a tag; publish a package; change repository visibility; or create
equivalent remote state. Local commits use a GitOps/conventional prefix and a
natural sentence, never a specification or work-package identifier, and use
the identity already configured by the contributor. Never record an agent,
tool or bot as author, committer or co-author, and never add "Generated with"
or similar attribution.

## Automation boundary

Agent guidance is part of the repository: `CLAUDE.md` files, `AGENTS.md`,
`.claude/` rules and skills, and the root `mix` commands. The repository does
not own worker coordination, claims, leases, attempts, programme state,
accepted outcomes or remote publication policy; do not add a coordination
daemon, graph database, shared-workspace service or tracked execution state.
