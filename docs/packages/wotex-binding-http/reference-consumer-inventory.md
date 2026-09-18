# Exact archive and reference-consumer inventory

WBH-C04 proves the release-shaped package boundary with a generated consumer
outside every Wotex checkout. The executable authority is
`bin/check_archive.exs`, invoked by the mandatory `archive` tool in the
package gate (`mix pkg wotex-binding-http check --no-retry`).

The checker builds the exact `wotex`, `wotex_runtime`, and
`wotex_binding_http` archives once per invocation with `WOTEX_PATH_DEPS`
unset. It inspects the archive metadata and content allowlists before manually
extracting those same bytes. The external Mix consumer names only the three
extracted archives as Wotex dependencies. Its environment clears
`WOTEX_PATH_DEPS`, `ERL_LIBS`, `MIX_PATH`, `MIX_BUILD_PATH`, and
`MIX_DEPS_PATH`; executable assertions reject any compile source, BEAM, or code
path under a live checkout.

## Vector map

| Vector | Independent-consumer assertion |
|---|---|
| WBH-A01 | All three archives have exact names, versions and release requirements; no mutable dependency source, development/agent machinery, local task state or application callback is present; compiled sources and loaded BEAMs resolve only through the external consumer and extracted archives |
| WBH-A02 | A `readproperty` selected from a real TD crosses the public `ConsumedThing` API, credential port and HTTP client port and returns the decoded Runtime result with the accepted method, URI and limits |
| WBH-A03 | A returned redirect becomes one typed failure without a hidden second request; an Action-status URI and ephemeral credential reach the supplied client separately, whose audience rejection is redacted through Runtime |
| WBH-A04 | A finite JSON response is accepted at the configured byte ceiling and rejected one byte over through the public Runtime request API |
| WBH-A05 | A real consumer `Supervisor` owns the Runtime subscription child: the supplied client opens an SSE stream, an already-framed event is decoded and delivered, an oversized event becomes a typed Runtime delivery error, and explicit stop closes the exact handle |
| WBH-A06 | Nested returned client failures and raised client failures containing credential/process terms are redacted through the public Runtime error path |

Each successful invocation prints the three archive SHA-256 digests, exact
source revisions, external consumer lock digest, vector range, source-path
isolation result and application-callback result. The generated project,
archives, lock, build products and run receipt live only in a guarded temporary
directory and are removed after the check.

## Scope and nonclaims

This is deterministic reference-port interoperability, not a production HTTP
client or network certification. The supplied client in the external consumer
models finite responses and already-framed SSE events; it does not claim DNS,
TLS, proxy, redirect-following, framing, reconnection or backpressure behavior.
The redirect vector proves that this binding does not follow redirects and that
the client receives the inputs needed to enforce destination and credential
audience policy. It does not prove that arbitrary client code enforces that
policy. The response/event checks do not claim bounded total memory, and the
single pinned Elixir/OTP execution is not the declared compatibility matrix.
