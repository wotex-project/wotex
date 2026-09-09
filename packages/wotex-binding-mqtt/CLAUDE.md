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

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Release metadata

`CHANGELOG.md` is reserved for GitOps release metadata; never edit it directly.
Once GitOps tooling and configuration are installed, the human maintainer
prepares the first release with `mix git_ops.release --override 0.1.0` because
the initial changelog already exists. Later releases use `mix git_ops.release`.
These are future human release steps, not a claim that tooling is configured
or a release is ready. Automated agents must not invoke either release task.

## Git authority

Mutable completion/audit trackers belong only under ignored `docs/tasks/local/`
and must never enter Git, package archives or generated documentation. Durable
specifications and completion plans remain tracked. Follow
`docs/plans/wotex-binding-mqtt-completion.md`; do not create an optional tracker beneath
publishable documentation outside its declared ignored path. Package/archive
checks must prove the tracker remains excluded.

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package or release; or create equivalent remote
state. Only the human maintainer performs publication. Never change repository
visibility.

Local commits use the identity already configured by the contributor running
Git. Automated agents must never set or override Git identity; record an agent,
tool, or bot as an author, committer, or co-author; invent a contributor
identity; or remove attribution supplied by a human contributor.
