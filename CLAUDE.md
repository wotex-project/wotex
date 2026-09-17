# WoTEx Repository Contract

This repository holds the WoTEx package family. Each directory under
`packages/` is an independent Mix project with its own contract in
`packages/<name>/CLAUDE.md`; that file governs work inside the package. This
file governs the repository as a whole and applies everywhere.

## Layout invariants

- `packages/<name>/` is a normal Mix library or application. Never add an
  umbrella (`apps_path`), a root release, or a root project that depends on a
  package.
- Package directories keep their names; sibling path dependencies are
  `Path.expand("../<name>", __DIR__)` and resolve inside `packages/`.
- `WOTEX_PATH_DEPS=1` is the only sibling switch, allowed in `dev`, `test`
  and `docs`. Unset means Hex requirements. Never add another mechanism.
- `docs/` is for people. Code never reads from `docs/`. Fixtures, schemas,
  vectors and machine-read provenance live in `packages/<name>/priv/` or
  `test/support/`.
- `docs/packages/<name>/` mirrors the package it documents: `specs/` (with
  `catalogue.yaml` as the normative status owner), `plans/`, `decisions/`,
  `provenance/`. Family-level documents live in `docs/architecture/`,
  `docs/decisions/` and `docs/guides/`.
- Machine-local execution state (trackers, progress notes, patches, receipts
  in progress) lives only in the ignored `docs/tasks/local/<name>/`. It never
  enters Git, package archives or generated documentation.
- Hex tarballs ship code, `priv/`, `README.md`, `CHANGELOG.md`, `LICENSE` and
  `NOTICE`. They do not ship Markdown documentation, governance files, agent
  files or check scripts; specifications reach consumers through HexDocs.

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
  violation even though it compiles.

## Gates

- Work inside `packages/<name>` and run that package's gate before a local
  commit: `WOTEX_PATH_DEPS=1 mix check --no-retry`.
- Then run the gate of every package that depends on the one you changed. A
  change in `wotex` or `wotex-runtime` affects all dependents; a change in a
  protocol adapter affects only that adapter.
- Never run every package's gate for a one-package change. Native builds,
  software profiles and container lanes run only when invoked explicitly with
  a disposable absolute workspace.
- Documentation-only changes need no build, but every relative link must
  resolve.

## Specifications and evidence

- Every standards claim pins the exact revision and executable evidence.
- Completion plans are versioned contracts; a changed obligation needs a new
  plan version. Execution status stays in `docs/tasks/local/`.
- Recorded evidence names the source commit of this repository and the
  package path. Evidence recorded before a move of the files it covers is
  stale and must be re-run.

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

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors
and deterministic verification commands. It does not own worker coordination,
claims, leases, attempts, programme state, accepted outcomes or remote
publication policy. Do not add a coordination daemon, graph database,
shared-workspace application or tool-specific project metadata.
