# WLB.04: Runtime and real reference transports

Specification version: 1.1.0. Contract: accepted. Source status: the loopback
transport, simulated Thing host, NoSec and StaticRef credential adapters are
implemented; Req/SSE and EMQTT lanes remain planned.

## Public seams and chosen implementations

| Seam | Lab owner | Exact contract |
| --- | --- | --- |
| Runtime transport | Loopback adapter; network binding transports | `c:Wotex.Runtime.Transport.request/3`, `c:Wotex.Runtime.Transport.subscribe/4`, `c:Wotex.Runtime.Transport.unsubscribe/4`, optional `c:Wotex.Runtime.Transport.decode_frame/3` |
| Runtime credentials | NoSec and StaticRef | `c:Wotex.Runtime.Credentials.resolve/4` |
| HTTP client | Req request adapter and bounded SSE session | `Wotex.Binding.HTTP.Client.request/3`, `subscribe/4`, `close/2` |
| MQTT client | EMQTT session adapter | `Wotex.Binding.MQTT.Client.publish/3`, `read/4`, `subscribe/4`, `unsubscribe/4` |
| Inbound application | Explicit simulated Thing handlers | Public `Wotex.Runtime.ExposedThing` boundary |

Lab MUST NOT reimplement binding mappings. Fixtures use only supported cells
from the pinned WBH/WBM catalogues. Unsupported aggregate operations return
the documented error, never fabricated success. Exact callback argument order
and return shapes come from the pinned behaviour modules in the source index.

## Runtime and exposure

1. Loopback MUST exercise real ConsumedThing selection and immutable Result
   identity, with supplied credentials and a simulated ExposedThing host. It
   is a transport reference, not evidence that HTTP or MQTT worked.
   `Wotex.Lab.Adapters.Runtime.Loopback` sends raw frames
   (`{:sample, name, value, meta}`, `{:event, name, payload, meta}`,
   `:keepalive`) that the owning subscription decodes through `decode_frame/3`,
   and starts a linked session process that monitors the host so host death
   surfaces as `:transport_down` exactly as a dead connection would in a
   network binding. `Wotex.Lab.Reference.Thing` owns simulated state, admits
   route, credential and DataSchema bounds before any handler runs, counts
   handler calls and rejections, monitors subscribers, and can simulate
   `session_lost`.
2. Runtime subscription child specs MUST be placed under an instance-owned
   supervisor. Zero/one/multiple handles, receiver death, host death, session
   loss, permanent restart with fresh credentials, concurrent stop, forced kill
   and cleanup error MUST have observable outcomes through the runtime envelope
   `{:wotex_runtime, id, {:ok, value, meta} | {:error, error} | {:status, status}}`.
3. The inbound host MUST admit authentication, authorization, exact route/Form,
   operation, content type and DataSchema before handler execution. Invalid
   requests MUST leave a handler-call counter unchanged. Effects and canonical
   simulated state live in the host, never in ExposedThing or the binding.
4. NoSec MUST reject selected non-nosec requirements. StaticRef MUST resolve
   secret references just in time for the selected audience through a
   consumer-owned `lookup` function; its configuration holds references only.
   Config, TDs, handles, errors and event metadata MUST NOT contain resolved
   credentials or references.

## HTTP / SSE

Req performs finite requests with explicit connect/read/overall budgets, bounded
response bytes and disabled implicit retries of effects. TLS peer/hostname
verification is required except in an explicitly identified disposable TLS
fixture. Redirects default to denied; approved destinations require audience
validation and fresh credential resolution. Public hosted controls cannot
turn arbitrary user URIs into private-network fetches.

Check the actual mapped destination, including ActionStatus `href`/Location,
not only the originally selected Form. Syntactic URI validation is not SSRF
protection or credential-audience admission. Resolve and check every address
and redirect hop; reject private/link-local/metadata/multicast targets in the
hosted profile, pin the admitted peer through connect and verify TLS identity.
Simulated loopback endpoints are explicit local-profile allowlist entries.

The SSE session MUST incrementally handle UTF-8 splits, LF/CRLF, comments,
multi-line data, empty events, IDs and retry fields, and emit complete
`Wotex.Binding.HTTP.SSE.Event` values. It owns bounded buffered bytes and event
queues. Oversize lines/events terminate with a typed error; a slow receiver
must apply the declared pause-or-close policy, not grow an unbounded mailbox.
Handshake status/content type are validated before success. Failed opens and
duplicate closes clean up exactly the identified connection. Closing with a
transplanted config cannot close a different instance's connection.

Reconnect is a **host lifecycle decision**. The HTTP port forbids retaining
credentials in config, handle or callback closure and provides no refresh
callback. Therefore authenticated reconnect MUST stop the failed Runtime
subscription and begin a new one through Runtime credential resolution. The
host may carry validated non-secret Last-Event-ID and bounded retry state.
It MUST NOT capture the original credential for automatic reconnect or replay
non-idempotent Actions. A failed refresh remains a failed attempt.

## MQTT

EMQTT owns its supervised connection and session; the MQTT binding owns topic,
filter, QoS and operation mapping. The disposable broker image is digest-pinned
with isolated run topic prefixes and bounded retained state. Retained reads
are finite and MUST distinguish missing retained data, timeout and invalid
delivery. Publish acknowledgement is not proof of a physical Action effect.

Reconnect/resubscribe requires explicit host policy, bounded backoff and fresh
Runtime credential resolution under the same ephemeral-credential constraints.
The selected MQTT wire client may use a credential to establish a session but
the Lab MUST verify it is not retained in reconnect options/process diagnostics;
otherwise that authenticated profile fails acceptance until the public client
seam supports the needed custody contract. No undocumented bypass is allowed.
QoS duplicate deliveries require explicit sample/attempt identity handling;
there is no blanket exactly-once guarantee. Validate payload bytes, topic and
filter size/count, receiver capacity and concurrent handle isolation.

The client must explicitly disable automatic credential reuse/reconnect and
sanitize crash/diagnostic output; connection custody remains client-owned.
Fresh connections re-enter Runtime as above. The authenticated reference lane
must prove these client controls against the pinned EMQTT source; absence of
the controls is a failed contract, not permission to claim secure reconnect.
Also exercise MQTT `$` topics/shared filters, broker ACL isolation, retained
stale samples, Last Will, session expiry, inflight/QoS bounds and power loss.
Time since receipt is not sensor observation age; clock uncertainty and device
reset identity are part of admission before a sample reaches Wotex Nx.

## Acceptance

`test/wotex/lab/loopback_test.exs` covers the in-BEAM loopback lane: admission
with identity and inert results, rejected writes leaving the handler counter
unchanged, retry classification from the transported cause, just-in-time
credentials that never appear in errors or process state, frame decoding in
the owner, ignored keep-alives and unrelated affordances, undecodable frames,
session loss, host death, receiver death, permanent restart with fresh
credentials, and port exception isolation with telemetry.

Real loopback HTTP/SSE and disposable-broker runs cover read, write, Action,
Property observation and Event subscription where supported, plus wrong
status/content type, malformed/oversized JSON, deadline expiry, callback
raise/throw/exit, invalid return, wrong identity, failed handshake, fragmented
SSE, disconnect, retry exhaustion, receiver death, overload and duplicate stop.
Every case records ownership and cleanup evidence. Source owners are
RT-C01–C06, WBH-C01–C06 and WBM-C01–C06; Lab evidence supports their gates but
does not amend their specs. No complete WoT Profile or wire-client certification
follows from a successful scenario.
