# Wotex MQTT Binding Contract

Wotex core owns W3C Web of Things values and terminology. Wotex Runtime owns
interaction mechanics. This package owns only the MQTT binding values, mapping,
JSON payload boundary, and Runtime transport adapter.

- Keep every file consumer-neutral and free of names or details owned by a
  consumer host. Say `consumer` or `consumer host`.
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

Run `WOTEX_PATH_DEPS=1 mix check` before local commits.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package or release; or create equivalent remote
state. Only the human maintainer performs publication.

Every local commit uses `Tobias Bohwalli <hi@futhr.io>` as both author and
committer. Never substitute an agent, tool, bot, or shared contributor identity.
