# Wotex Modbus Repository Contract

Wotex owns W3C Web of Things terminology and core Thing Description semantics.
This normal Mix library owns Modbus values, bounded protocol operations,
Form mapping and a neutral compatibility adapter. Consumers own policy,
credentials, supervision, connection configuration and canonical Property truth.

- Keep source, tests, docs, fixtures, metadata and history consumer-neutral.
  Say `consumer` or `consumer host`; never name a consumer or its local paths.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  application callback, framework integration or automatic network activity.
- Loading the dependency starts no process and performs no runtime filesystem
  access. Stateful transports start only through explicit calls or child specifications.
- Pure values never consult application environment, clocks or random sources.
  Transport time, identifiers, deadlines and ports have explicit ownership.
- Never fetch remote JSON-LD contexts. Preserve unknown Form extensions.
- Use W3C terms exactly. TD 1.1 is the baseline. Label binding drafts as drafts;
  a mapped Form proves neither authorization nor a physical effect.
- Public functions have documentation and types. One module per `.ex` file.
  Test modules use `@moduledoc false` followed by a blank line.
- Errors are structured, input and allocation limits explicit, security modes
  fail closed, and write requests are never silently retried.
- `WOTEX_PATH_DEPS=1` is the sole local dependency switch and is development-only.
  Normal package identity uses released Wotex dependencies.

Run `WOTEX_PATH_DEPS=1 mix check` before every local commit. The gate includes
formatting, compilation, tests, documentation and unpacked archive inspection.
Apply `.claude/skills/spec-delivery/SKILL.md` for public behavior and standards
claims and `.claude/skills/release-readiness/SKILL.md` for compatibility claims.
Consumer-neutrality is a review obligation; never add a consumer denylist.

## External automation boundary

Keep durable specifications and acceptance criteria tracked. Mutable audit
notes belong only in ignored `docs/tasks/local/`. No coordination daemon,
worker assignments, shared-workspace state or tool-specific project metadata.

## Release metadata

`CHANGELOG.md` is reserved for GitOps release metadata; never edit it directly.
Once GitOps tooling and configuration are installed, the human maintainer
prepares the first release with `mix git_ops.release --override 0.1.0` because
the initial changelog already exists. Later releases use `mix git_ops.release`.
These are future human release steps, not a claim that tooling is configured
or a release is ready. Automated agents must not invoke either release task.

## Git authority

Never configure, add, change or remove a Git remote; push; create a tag; publish
a package or release; or create equivalent remote state. Publication is manual.
Never change repository visibility.

Local commits use the identity already configured by the contributor running
Git. Automated agents must never set or override Git identity; record an agent,
tool, or bot as an author, committer, or co-author; invent a contributor
identity; or remove attribution supplied by a human contributor.
