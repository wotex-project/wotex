# Wotex Lab contract

This is an independent consumer laboratory for the WoTEx family, with Nx as
the primary numerical adoption path. Dependencies point from Lab to public
libraries. Do not copy private package implementations or change WoT meaning.

Repository-wide rules are in the root `CLAUDE.md`.

- Loading Lab starts no Lab process. Consumers explicitly place its child spec.
- Processes, stores and simulated effects belong to an explicit Lab instance.
  No singleton, auto-discovery, implicit backend change or application callback.
- Keep one module per `.ex`. Tests have `@moduledoc false` and a blank line.
- Use structured errors, explicit options, bounded work and public package APIs.
- No model download, Action dispatch or verification pool starts implicitly.
- Numerical output and formal-model results are inert; neither grants authority.
- PromEx/BeamLens/Phoenix belong to an explicit reference host. GreptimeDB is
  a supplied/local service, not embedded BEAM storage. No implicit LLM calls,
  introspection, database connection or public metrics listener.
- The workbench is neutral LiveView/HEEx with base semantic tokens. No mandatory
  UI framework, ELK stack or infrastructure dependency for the first tensor.
- `WOTEX_PATH_DEPS=1` is the only workspace switch, restricted to dev/test/docs.
  It never proves artifact adoption. Release paths use Hex or verified archives.
- Specs and completion contracts describe the entire accepted programme; do not
  create a deferred backlog, TODO modules or fake successful adapters.
- Distinguish implemented source, evidence coverage and artifact adoption.
  Unbuilt accepted contracts have `implementation_status: planned`.
- Preserve sibling ownership. Evidence references do not close sibling work
  items or authorize edits to their catalogues.
- Publish only consumer-neutral fixtures and allowlisted documentation.
  Consumer, company and customer names stay out; sibling packages are
  referenced by package name; relative paths inside the repository are allowed;
  absolute machine paths are not. No secrets, coordination daemons or shared
  execution trackers. The root `docs/tasks/local/wotex-lab/` is ignored and
  excluded from packages.

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-lab` before a
local commit, then the gate of every dependent package. Publication is
maintainer-owned.
