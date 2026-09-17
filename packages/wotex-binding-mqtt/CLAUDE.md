# Wotex MQTT Binding Contract

Wotex core owns W3C Web of Things values and terminology. Wotex Runtime owns
interaction mechanics. This package owns only the MQTT binding values, mapping,
JSON payload boundary, and Runtime transport adapter. Repository-wide rules
are in the root `CLAUDE.md`.

- Keep every file consumer-neutral: consumer, company and customer names stay
  out. Say `consumer` or `consumer host`. Sibling packages are referenced by
  package name; relative paths inside the repository are allowed, absolute
  machine paths are not.
- Do not add an OTP Application callback, process, supervisor, connection
  manager, MQTT client implementation, database, or framework dependency.
- The consumer supplies the MQTT client port, its connection ownership, policy,
  deadlines, credentials, and supervision.
- Commands, broker values, errors, delivery values, and package configuration
  remain immutable and credential-free. Credentials cross only an immediate
  client-port call through `Wotex.Runtime.ExecutionContext`.
- Preserve the exact `mqv:retain`, `mqv:controlPacket`, `mqv:qos`, `mqv:topic`,
  and `mqv:filter` terms from the dated editor's draft. Do not put a topic or
  filter in the broker href.
- Do not claim W3C conformance. The referenced MQTT binding and Binding Registry
  remain works in progress at the documented observation date.
- One module per `.ex` file. Public functions have docs and types. Test modules
  use `@moduledoc false` followed by a blank line.
- `WOTEX_PATH_DEPS=1` is the only local source switch. Normal package identity
  uses released `wotex` and `wotex_runtime` versions.

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-binding-mqtt`
before a local commit, then the gate of every dependent package. Run
`elixir bin/check_boundary.exs` for the public boundary.

## Local execution state

Mutable completion/audit trackers belong only under the ignored root
`docs/tasks/local/wotex-binding-mqtt/` and must never enter Git, package
archives or generated documentation. Durable specifications and the completion
plan `docs/packages/wotex-binding-mqtt/plans/wotex-binding-mqtt-completion.md`
remain tracked; do not create an optional tracker beneath publishable
documentation. Package/archive checks must prove the tracker remains excluded.
