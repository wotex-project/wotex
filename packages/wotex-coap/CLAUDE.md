# Wotex CoAP Package Contract

Wotex owns W3C Web of Things terminology and core Thing Description semantics.
This normal Mix library owns CoAP values, bounded protocol operations,
Form mapping and a neutral compatibility adapter. Consumers own policy,
credentials, supervision, connection configuration and canonical Property truth.

Repository-wide rules are in the root `CLAUDE.md`.

- Keep source, tests, docs, fixtures, metadata and history consumer-neutral.
  Say `consumer` or `consumer host`. Consumer, company and customer names stay
  out; sibling packages are referenced by package name; relative paths inside
  the repository are allowed; absolute machine paths are not.
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

Native protocol execution uses BEAM/OTP and the explicitly specified native SDK
Port, where applicable. Build and test orchestration uses Mix/ExUnit. No Python
runtime or target orchestration dependency is part of this contract.

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-coap` before a
local commit, then the gate of every dependent package. The gate includes
formatting, warnings-as-errors compilation, and the default test suite.
Apply the root `.claude/skills/spec-delivery/SKILL.md` for public behavior and
standards claims and the root `.claude/skills/release-readiness/SKILL.md` for
compatibility claims. Consumer-neutrality is a review obligation; never add a
consumer denylist.

## External automation boundary

Keep durable specifications and acceptance criteria tracked under
`docs/packages/wotex-coap/`. Mutable audit notes belong only in the ignored root
`docs/tasks/local/wotex-coap/`. No coordination daemon, worker assignments,
shared-workspace state or tool-specific project metadata.
