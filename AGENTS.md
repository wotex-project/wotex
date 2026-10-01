# WoTEx repository contract

This is the canonical repository contract for the WoTEx package family: 18
independent Mix projects under `packages/` and a root tooling project. Read
`packages/<name>/AGENTS.md` before changing a package or its documentation;
it owns package-specific boundaries, source locations and test selection.

## Skills and discovery

Shared skills live in tracked `.agents/skills/<name>/SKILL.md`. The AI selects
and reads matching skills automatically from their descriptions as the task,
changed mechanism or delivery stage requires. The user does not invoke skills
or choose slash commands. Keep implicit invocation enabled. Clients without
native skill discovery must inspect these descriptions and read matching
`SKILL.md` files themselves. Load supporting material only when relevant.

Codex discovers `.agents/skills` natively. Claude Code discovers individual
skill directories under `.claude/skills`; local entries for repository skills
are relative directory symlinks to `.agents/skills`. Keep `.claude/` entirely
ignored, preserve unrelated local entries and client settings, and repair
repository-owned dangling links without creating aliases. Use native
`AGENTS.md` discovery; clients that do not load it must read it explicitly.
Do not add instruction wrappers, agent hooks, denial scripts, session markers,
tracked client settings or agent setup helpers.

## Working loop

Run commands from the repository root. Use the `monorepo-workflow` skill to
choose validation for code changes. `mix setup` provisions dependencies and
the Dexter index when setup is needed; do not repeat it on a prepared checkout
or install dependencies for guidance-only work.

- Locate definitions and callers with `mix def Module [fun]` and
  `mix refs Module [fun]`. Before changing a public function, inspect callers
  and `mix impact Module [fun]`; `--run` runs identified package tests.
  Dexter is navigation, not type checking or proof of behavior. Text search
  can locate literal references and configuration, but cannot prove semantics.
- While editing, run focused tests with `mix pkg <name> test <files>`.
  When package code is ready, run `mix check.fast --package <name>`.
  Run `mix dialyzer.pkg <name>` when a typespec, callback or inferred return
  type changes; otherwise the full package gate covers it.
- Before committing code, run `mix check`: the root self-check, full gate for
  changed packages and fast gate for their dependents. Inspect the affected
  set and use a comparison base that covers the work being validated.
  Guidance and documentation changes need metadata, references, links and
  relevant tooling tests; do not impose unrelated application suites.
- For C, C++ or Rust changes, use `mix native.lint --package <name>` while
  editing (`--fix` formats changed lines). The full native package gate adds
  clang-tidy and native tests. Never reformat vendored or pinned files listed
  in `.clang-format-ignore`; a clang-tidy false positive needs a reason beside
  its `NOLINTNEXTLINE(check)` comment.
- Never run every package's gate or Dialyzer across packages for a bounded
  change. `mix check.all` is for a repository-wide code or toolchain change
  or an explicit request. Native builds, software profiles, interop and
  containment lanes run only when requested, with their documented
  prerequisites and disposable absolute workspace.
- Benchmarks run only when requested: `mix bench --package <name>` or
  `mix native.bench --package <name>`. Reports belong in `bench/output/`.
- Report actual commands, test files, results and skipped checks in chat.
  A declaration, planned test or lexical scan is not executed evidence.

## Layout and ownership

- `packages/<name>/` is a normal Mix library or application. Never add an
  umbrella (`apps_path`), root release or root project dependency on a package.
  The root tooling only runs package Mix processes.
- Keep package directory names. `WOTEX_PATH_DEPS=1` is the only sibling
  switch, allowed in `dev`, `test` and `docs`; unset means Hex requirements.
  Sibling paths use `{app, path: Path.expand("../<name>", __DIR__),
  env: :dev, override: true}` and resolve inside `packages/`. `env: :dev`
  satisfies the sibling's own source-switch guard. Never discover a sibling
  or backend from neighbouring directories or loaded modules.
- `tooling/packages.yaml` owns the package graph, CI toolchain lanes and
  native tasks. `mise.toml` pins the current local lane.
- Libraries have no application callback or dependency-load side effect.
  Pure values take explicit configuration and immutable input; they do not
  consult ambient application environment, clocks or random sources. Public
  input boundaries return structured errors and enforce bounds. Retries and
  fallback behavior are explicit. Long-lived operations have consumer-owned
  startup, ports, identities, deadlines, supervision and cleanup. Reference
  hosts own their application callbacks and framework integrations.
- Use one module per `.ex` file. Public contracts have useful documentation,
  types and specs. Test and test-support modules use `@moduledoc false`
  followed by a blank line. Do not turn untrusted strings into atoms.
- `docs/` is for people. Runtime fixtures, schemas, vectors and machine-read
  provenance belong in `packages/<name>/priv/` or `test/support/`; code does
  not read `docs/`. The exception is Lab's documentation-backed development
  features: the knowledge graph and MCP resources read it as their subject
  only through `Wotex.Lab.Documentation`, and report it unavailable in a
  released archive. No other package gets this exception.
- `docs/packages/<name>/` owns its specifications, completion contracts,
  decisions and provenance. Its `specs/catalogue.yaml` owns implementation
  status. `docs/catalogue.yaml` is generated by `mix wotex.catalogue`; never
  edit it by hand.
- Machine-local notes, consumer-specific details and execution state belong
  only in ignored `docs/tasks/local/<name>/`. They do not enter Git, package
  archives or generated documentation. Do not add worker coordination,
  claims, leases, shared execution trackers or a coordination service.

## Public boundaries and claims

- Use W3C Web of Things terms exactly: Thing, Thing Description, Property,
  Action, Event, DataSchema, Form, Interaction Affordance, security scheme,
  ConsumedThing and ExposedThing. Thing Description 1.1 is the production
  baseline; label drafts and group notes as such. Package extension terms
  are not W3C-standard fields. Never fetch remote JSON-LD contexts.
- Form selection does not authorize an operation. Transport completion does
  not establish a physical effect or canonical Property truth. Numerical
  outputs and Action proposals are inert and grant no authority.
- Use only public, documented sibling APIs. Calling `@moduledoc false`
  modules or `@doc false` functions crosses the package boundary even if it
  compiles; `mix wotex.boundary` checks this.
- Keep consumer product, company and customer names, private namespaces,
  credentials, customer data and non-public source out of source, fixtures,
  documentation, history and metadata. Say `consumer` or `consumer host` at
  integration boundaries. Reference siblings by package name and repository
  files by relative paths, never machine-specific absolute paths. Review
  meaning as well as lexical findings; do not encode private names in a
  public denylist. Imported material needs provenance and a compatible notice.
- Standards claims pin the exact revision and executable evidence. Fixture
  presence, valid schemas and unrelated passing tests do not establish
  interoperability, certification or complete conformance.
- Specifications and completion plans are versioned contracts. Change their
  version and package catalogue when obligations or public seams change.
  Distinguish implemented behavior, planned work and executed evidence.
  Evidence names the repository commit and package path; evidence for moved
  or changed inputs is stale. Renew it by running the owning checks, never
  by editing digests or promoting a historical snapshot by hand.

## Package contents and release metadata

Package archives ship code, `priv/`, `README.md`, `usage-rules.md`,
`CHANGELOG.md`, `LICENSE` and `NOTICE`. Include native sources and test assets
only when shipped Mix tasks need them; the package's `bin/check_archive.exs`
or `bin/check_package.exs` is the authority for its exact file list. Lab ships
the Rust containment launcher source, never a launcher binary. Do not ship
repository instructions, client settings, shared skills, governance, check
scripts or the documentation tree. Notes within a shipped native tree belong
to that tree; specifications reach consumers through HexDocs.

`usage-rules.md` is concise consumer guidance for the completed normative
specification and completion contract. The catalogue separately records the
current checkout's implementation status. Keep repository contributor policy
out of the consumer file.

Each package owns its version and `CHANGELOG.md`. Release tooling alone
maintains changelogs; never edit or format them manually. Root `git_ops.json`
owns release configuration; packages have none. Tags use
`<package>-v<version>`. Only the human maintainer prepares or publishes a
release; automated agents do not invoke release tasks.

## Git authority

Preserve unrelated changes. Local commits use a GitOps/conventional prefix
and a natural sentence, without specification or work-package identifiers,
and the contributor's configured identity. No agent, tool or bot is author,
committer or co-author; no "Generated with" attribution. Never configure,
add, change or remove remotes; push; tag; publish; change visibility; or create
equivalent remote state.
