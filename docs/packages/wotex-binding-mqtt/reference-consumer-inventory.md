# Exact archive and reference-consumer inventory

WBM-C04 proves the release-shaped package boundary with a generated consumer
outside every Wotex checkout. The executable authority is
`bin/check_archive.exs`, invoked by the mandatory `archive` tool in the default
repository gate.

The checker builds the exact `wotex`, `wotex_runtime`, and
`wotex_binding_mqtt` archives once per invocation with `WOTEX_PATH_DEPS`
unset. It inspects metadata and content allowlists before manually extracting
those same bytes. The external Mix consumer names only the three extracted
archives as Wotex dependencies. Its environment clears `WOTEX_PATH_DEPS`,
`ERL_LIBS`, `MIX_PATH`, `MIX_BUILD_PATH`, and `MIX_DEPS_PATH`; executable
assertions reject any compile source, BEAM, or code path under a live checkout.

## Vector map

| Vector | Independent-consumer assertion |
|---|---|
| WBM-A01 | All three archives have exact names, versions and release requirements; no mutable dependency source, development/agent machinery, local task state or application callback is present; compiled sources and loaded BEAMs resolve only through the external consumer and extracted archives |
| WBM-A02 | A `writeproperty` selected from a real TD crosses the public `ConsumedThing` API, credential port and supplied MQTT client and returns `accepted` with the exact PUBLISH topic, QoS and encoded payload |
| WBM-A03 | A retained `readproperty` receives the finite configured timeout and returns a matching retained delivery with decoded Runtime payload and metadata |
| WBM-A04 | A real consumer `Supervisor` owns a Runtime observation child; paired observe/unobserve Forms open the supplied client, decode an already-framed delivery in the owner, and close the exact opaque handle on explicit stop |
| WBM-A05 | Exact/one-over JSON bytes, 65,535-byte Topic Name, and 256-filter cardinality behavior survives archive construction and isolated compilation |
| WBM-A06 | Nested returned failures and raised failures containing credential/process terms are redacted through the public Runtime error path even though the supplied client receives the immediate credential |

Each successful invocation prints the three archive SHA-256 digests, exact
source revisions, external consumer lock digest, vector range, source-path
isolation result, and application-callback result. The generated project,
archives, lock, build products, and run output live only in a guarded OS-temp
directory and are removed after the check.

## Scope and nonclaims

This is deterministic reference-port interoperability, not a production MQTT
client or broker certification. The supplied client models accepted publication,
a retained read, and an already-framed delivery. It does not open a socket or
claim DNS, TLS, authentication, ACL, MQTT framing, QoS handshake, retained-value
freshness, Session Expiry, Clean Start, reconnection, ordering, duplicate/loss,
or backpressure behavior. The checks do not claim bounded total memory or
broader platform compatibility. Public registry availability and a named real
broker/client cohort remain release-candidate inputs rather than consequences
of this local exact-archive proof.
