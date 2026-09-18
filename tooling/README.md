# Repository tooling

`tooling/` holds repository-level scripts and data that no package ships.

| Path | Contents |
| --- | --- |
| `packages.yaml` | The package manifest: the dependency graph, lane metadata and the globs that select every package. |
| `import/` | The one-time monorepo import scripts and commit maps (see `docs/architecture/monorepo-import.md`). |

The root Mix project (`mix.exs` at the repository root, app `:wotex_workspace`)
implements the `mix wotex.*` tasks that read the manifest. It is not an
umbrella and depends on no package; it runs each package's own Mix project in
a separate OS process with `WOTEX_PATH_DEPS=1`. `mix help wotex.affected`
and the other `mix help wotex.*` pages document each task.

## `packages.yaml`

```yaml
schema_version: "1.0.0"
lanes:
  minimum: { elixir: "1.18.4-otp-27", otp: "27.3.4.15" }
  current: { elixir: "1.20.2-otp-29", otp: "29.0.4" }
select_all_on:
  - ".github/**"
  - "tooling/**"
  - "mix.exs"
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
```

| Key | Meaning |
| --- | --- |
| `schema_version` | Version of this file's format. |
| `lanes.<name>.elixir`, `lanes.<name>.otp` | Toolchain lanes the package gates run on in CI. `mix wotex.check --lane NAME` prints a lane and warns when the running Elixir differs; CI selects the toolchain. |
| `select_all_on` | Repository-relative globs (`**` spans directories, `*` stays within a segment). A changed path matching any of them selects every package. |
| `packages.<name>` | One entry per directory under `packages/`. The key is the directory name. |
| `app` | The OTP application and Hex package name. |
| `depends_on` | The WoTEx packages this package requires directly. Dependents are derived; a change in a package selects it and every transitive dependent. The graph must be acyclic and every name must exist. |
| `native` | `true` when the package builds or vendors native code. `mix wotex.native.sources` and `mix wotex.native.advisories` cover native packages only. |
| `native_task` | The package's own build task, dispatched by `mix wotex.native.build --package NAME --workspace /abs/dir`. |
| `software_task` | The package's own software-profile task, if any (informational; run explicitly inside the package). |

`mix wotex.new NAME` appends a manifest entry; the manifest is validated
whenever a task loads it.

## Affected packages

`mix wotex.affected` derives the changed paths from `git diff --name-only
<base>...HEAD` plus the working tree, then applies these rules:

- `packages/<name>/...` selects `<name>` and every transitive dependent;
- `docs/packages/<name>/...` selects nothing (documentation only) unless
  `--docs` is given;
- a path matching `select_all_on` selects every package.

The result is always in topological order, so `mix wotex.check` runs a
package after the packages it depends on.

## Family catalogue

`mix wotex.catalogue` renders `docs/catalogue.yaml` from every
`docs/packages/<name>/specs/catalogue.yaml`. Paths follow the convention in
`docs/README.md`, "Catalogue paths": `docs/...` is relative to
`docs/packages/<name>/`, anything else to `packages/<name>/`. Every resolved
path must exist. `mix wotex.catalogue --check` fails when the committed file
is stale.
