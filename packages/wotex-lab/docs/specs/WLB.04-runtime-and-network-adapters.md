# WLB.04: Runtime and real reference transports

Specification version: 1.3.0. Contract: accepted. Source status: the loopback
transport, simulated Thing host, NoSec and StaticRef credential adapters, the
Req client with its bounded SSE session, and the EMQTT client with its linked
broker session are implemented and exercised over real sockets against a
disposable local server and a disposable MQTT broker container; TLS, broker
ACL isolation, Last Will, session expiry, power loss and the hosted
destination policy remain planned.

## Public seams and chosen implementations

| Seam | Lab owner | Exact contract |
| --- | --- | --- |
| Runtime transport | Loopback adapter; network binding transports | `c:Wotex.Runtime.Transport.request/3`, `c:Wotex.Runtime.Transport.subscribe/4`, `c:Wotex.Runtime.Transport.unsubscribe/4`, optional `c:Wotex.Runtime.Transport.decode_frame/3` |
| Runtime credentials | NoSec and StaticRef | `c:Wotex.Runtime.Credentials.resolve/4` |
| HTTP client | `Wotex.Lab.Adapters.HTTP.ReqClient` with `Adapters.HTTP.SSE.Session` and `Adapters.HTTP.SSE.Parser` | `c:Wotex.Binding.HTTP.Client.request/3`, `c:Wotex.Binding.HTTP.Client.subscribe/4`, `c:Wotex.Binding.HTTP.Client.close/2` |
| MQTT client | `Wotex.Lab.Adapters.MQTT.EmqttClient` with `Adapters.MQTT.Session` | `c:Wotex.Binding.MQTT.Client.publish/3`, `c:Wotex.Binding.MQTT.Client.read/4`, `c:Wotex.Binding.MQTT.Client.subscribe/4`, `c:Wotex.Binding.MQTT.Client.unsubscribe/4` |
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

`ReqClient` performs finite requests with the runtime deadline as the receive
budget, an explicit connect budget, a response body collected chunk by chunk
that halts past the request's `max_response_bytes`, and redirects and
automatic retries disabled. The credential (`{:bearer, token}`,
`{:basic, user, password}`, or a map of them from `StaticRef`) becomes one
`authorization` field for that exchange and is never stored. Req performs finite requests with explicit connect/read/overall budgets, bounded
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

The SSE session MUST incrementally handle UTF-8 splits, LF/CRLF/CR, comments,
multi-line data, empty events, IDs and retry fields, and emit complete
`Wotex.Binding.HTTP.SSE.Event` values. `SSE.Parser` is that pure, bounded
parser and `SSE.Session` is a process linked to the runtime subscription that
issues the handshake with Req in asynchronous mode, feeds every chunk through
the parser, and sends each event to the owner as a raw frame; the owner
decodes through the binding's `decode_frame/3`. Oversize lines/events end the
session with a typed reason, which the owner reports as `:transport_down`; a
slow receiver is bounded by the runtime's `max_queue_length` policy rather
than an unbounded mailbox.
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

`Wotex.Lab.Adapters.MQTT.EmqttClient` implements the four client callbacks over
the optional `emqtt` dependency; the module exists only when that dependency is
loaded. `Wotex.Lab.Adapters.MQTT.Session` owns every connection the adapter
opens. EMQTT owns its supervised connection and session; the MQTT binding owns
topic, filter, QoS and operation mapping, and Lab reimplements neither.

`subscribe/4` starts one session linked to the runtime subscription owner. It
connects, subscribes to the command's Topic Filters with the command QoS, and
sends each Application Message to the owner as
`{:wotex_transport_frame, %Wotex.Binding.MQTT.Delivery{}}`, so no delivery is
decoded on the connection process. A delivery larger than the command's
`max_payload_bytes` is dropped by the client instead of being forwarded. A
server DISCONNECT or a dead connection sends
`{:wotex_transport_status, :transport_down}` and exits with a `:shutdown`
reason; unsubscription unsubscribes the Topic Filters, disconnects and exits
normally. `publish/3` and `read/4` serve the calling process over a bounded,
monitored connection that is always torn down, so a refused broker cannot
become an exit signal in a caller that never asked for a session.

Retained reads are finite and MUST distinguish missing retained data, timeout
and invalid delivery. `read/4` subscribes, lets a PINGREQ round trip flush the
broker's retained delivery for the Topic Filter, and returns
`no_retained_message`, `mqtt_timeout` or `undeliverable_message` accordingly.
Publish acknowledgement is not proof of a physical Action effect.

Reconnect/resubscribe requires explicit host policy, bounded backoff and fresh
Runtime credential resolution under the same ephemeral-credential constraints.
The client sets emqtt `reconnect: false` and `retry_calls_on_reconnect: false`,
so no credential can be reused for an automatic reconnect and every fresh
connection re-enters Runtime credential resolution. The credential builds one
CONNECT packet and reaches no session state, handle, log line or error; the
Lab verifies this against the pinned EMQTT source, whose own state holds the
password only inside an `emqtt_secret` closure. Configuration is non-secret:
an optional admitted-peer host pin, the default port, a Client Identifier
prefix, Keep Alive and a connect budget. QoS duplicate deliveries require
explicit sample/attempt identity handling; there is no blanket exactly-once
guarantee. Validate payload bytes, topic and filter size/count, receiver
capacity and concurrent handle isolation.

The disposable broker is an `eclipse-mosquitto:2` container with a generated
minimal configuration, an ephemeral loopback port, no persistence and an
isolated run topic prefix per test, removed when the suite ends. The image is
selected by tag for local evidence; a digest-pinned image belongs to the
release profile of WLB.08 and is not claimed here. MQTT `$SYS` topics and
MQTT 5 shared Topic Filters are exercised against that broker. TLS, broker ACL
isolation, retained stale samples, Last Will, session expiry, inflight/QoS
bounds and power loss remain planned. Time since receipt is not sensor
observation age; clock uncertainty and device reset identity are part of
admission before a sample reaches Wotex Nx.

Run the broker lane explicitly; it is excluded unless the switch is set, so a
machine without a container runtime still runs a complete `mix check`:

```sh
WOTEX_PATH_DEPS=1 WOTEX_LAB_BROKER=1 MIX_ENV=test mix test
```

## Acceptance

`test/wotex/lab/http_test.exs` covers the HTTP/SSE lane over a disposable
Bandit server: read/write/Action with status mapping and bounds, oversized,
slow (deadline), redirected, mistyped and unauthorized exchanges with retry
classes and no credential leakage, incremental SSE parsing with CRLF, split
UTF-8, comments, ids and retries, undecodable frames, server-side stream end,
explicit stop closing the connection, oversized events ending the session,
and a mistyped handshake failing the open. `test/wotex/lab/loopback_test.exs`
covers the in-BEAM loopback lane: admission
with identity and inert results, rejected writes leaving the handler counter
unchanged, retry classification from the transported cause, just-in-time
credentials that never appear in errors or process state, frame decoding in
the owner, ignored keep-alives and unrelated affordances, undecodable frames,
session loss, host death, receiver death, permanent restart with fresh
credentials, and port exception isolation with telemetry.

`test/wotex/lab/mqtt_broker_test.exs` covers the MQTT lane against the
disposable `eclipse-mosquitto:2` broker: a retained Property read, a Topic
Filter with no retained message, accepted `writeproperty` and `invokeaction`
publications observed on the wire, an observation carrying Topic Name metadata
through the runtime envelope, an ignored unrelated Topic Name and a dropped
oversized Application Message, an explicit stop that unsubscribes and
disconnects every session process, a stopped broker container surfacing
`:transport_down` and stopping the child, a permanent child resubscribing after
restart with freshly resolved credentials, an authenticated profile whose
password appears in no process diagnostic, a bounded receiver mailbox, and
shared plus `$SYS` Topic Filters. `test/wotex/lab/mqtt_test.exs` covers the
container-free client paths against a scripted in-BEAM MQTT 5 peer and closed
or silent sockets: refused connections, a bounded handshake and read budget,
credential mapping and rejection, an unadmitted broker host, an alien handle, a
denied Topic Filter, a server DISCONNECT, a closed socket and a killed
subscription owner. The scripted peer is a test peer, not broker evidence.

Real loopback HTTP/SSE and disposable-broker runs cover read, write, Action,
Property observation and Event subscription where supported, plus wrong
status/content type, malformed/oversized JSON, deadline expiry, callback
raise/throw/exit, invalid return, wrong identity, failed handshake, fragmented
SSE, disconnect, retry exhaustion, receiver death, overload and duplicate stop.
Every case records ownership and cleanup evidence. Source owners are
RT-C01–C06, WBH-C01–C06 and WBM-C01–C06; Lab evidence supports their gates but
does not amend their specs. No complete WoT Profile or wire-client certification
follows from a successful scenario.
