# Decision 0001: One repository of independent packages

Status: accepted

## Decision

The WoTEx packages live in one Git repository as independent Mix projects under
`packages/<name>/`. There is no umbrella project. Each package keeps its own
`mix.exs`, lock file, version, changelog, Hex package name and gate, and is
published on its own with tags of the form `<package>-v<version>`.

A root tooling project (`:wotex_workspace`) depends on no package. It reads the
package graph from `tooling/packages.yaml` and runs each package's Mix in its
own operating-system process. Sibling packages resolve from `packages/` only
when `WOTEX_PATH_DEPS=1` is set in `dev`, `test` or `docs`; unset, every
package declares Hex requirements.

Documentation for people lives in one tree, `docs/`, with one directory per
package under `docs/packages/<name>/`. Code never reads from `docs/`.

The full history of every former package repository was imported linearly
under its package directory; `docs/architecture/monorepo-import.md` records the
source revisions and the commit maps.

## Rationale

- The packages were changed together far more often than apart: before the
  move, 211 of 1,120 commits repeated a subject across three or more
  repositories, copied check scripts had diverged, and CI verified siblings in
  two incompatible ways.
- Independent Mix projects keep the package boundary real: separate lock
  files, separate compilation, separate archives and a package-level gate. An
  umbrella would share configuration and a build and hide boundary violations.
- One tree lets a change and its consumers be reviewed and verified together,
  and lets tooling compute what a change reaches.

## Consequences

- A package may call only the public, documented API of a sibling;
  `mix wotex.boundary` enforces this.
- Validation is proportional: tooling selects changed packages and their
  dependents (`mix affected`) and the tests that reach a changed function
  (`mix impact`). CI runs every package on the minimum and current toolchain
  lanes.
- Hex packages cannot include files outside their directory, so archives ship
  code, `priv/`, `README.md`, `CHANGELOG.md`, `LICENSE` and `NOTICE`;
  specifications are published through HexDocs.
- Consumers outside the repository depend on published packages, or on one
  commit of this repository with `sparse: "packages/<name>"` until
  publication (`docs/guides/consumer.md`).
