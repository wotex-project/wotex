# WBH.02: Client port and HTTP values

Specification `WBH.02@1.1.0`; package baseline `wotex_binding_http 0.1.0`.
Requires `wotex_runtime:WRT.01`; WBH.01 owns operation mapping and WBH.03 streams.

## Client callbacks

A consumer-supplied module implements:

```elixir
request(http_request, credential, client_config)
subscribe(http_request, credential, owner, client_config)
close(opaque_handle, client_config)
```

`request/3` returns `{:ok, response}` or `{:error, reason}`.
`subscribe/4` returns `{:ok, opaque_handle, handshake_response}` or an error.
`close/2` returns `:ok` or an error. The binding validates every return.

`owner` is the Runtime subscription process. A streaming client sends it raw
frames and status messages and may monitor or link it to release the connection
when it stops; WBH.03 fixes those messages. The client never decodes a frame.

The client configuration must be non-credential configuration. The credential
argument is ephemeral, is separate from the immutable HTTP request, and must
not be retained or captured by a connection process. Client errors are
normalized without copying their reasons.

The client owns network I/O, HTTP version selection, TLS and redirect policy,
deadlines, proxy behavior, response collection, SSE framing, connection reuse,
backpressure, and reconnection. This package supplies no client or pool.

## Deadlines

`request.deadline` is absolute and may be `nil`. An integer is a point on the
calling node's monotonic clock in milliseconds
(`System.monotonic_time(:millisecond)`); a `DateTime` is a UTC instant. The
binding never reads a clock and never converts between the two kinds.

The client must honor the deadline with its own clock reading of the matching
kind and derive the remaining budget through
`Wotex.Runtime.Context.remaining_ms/2`, which returns `:infinity` for `nil`, `0`
for an elapsed deadline, and `{:error, :clock_mismatch}` for a mismatched pair.
A client that expires a call reports the reason atom `:timeout`, the single
reason the binding interprets, so the failure is classified `:timeout`.

## Failure classification

Every returned error carries a `class` for `Wotex.Runtime.Retry.decision/3`.
Runtime copies only the atoms `code`, `phase`, and `class` into `details.cause`.

| Failure | Class | Retryable |
| --- | --- | --- |
| HTTP status 408; client reason `:timeout` | `:timeout` | yes |
| HTTP status 429 | `:rate_limited` | yes |
| HTTP status 502, 503, 504 | `:unavailable` | yes |
| Any other failing client return, raise, exit, or throw | `:unavailable` | yes |
| Any other 4xx or 5xx status | `:permanent` | no |
| JSON encode, decode, admission limit, or byte limit | `:protocol` | no |
| Response media type, empty-body violation, invalid `Location` | `:protocol` | no |
| SSE handshake status, media type, or buffered body | `:protocol` | no |
| Invalid or oversized SSE frame | `:protocol` | no |
| Malformed client return value | `:protocol` | no |
| Configuration, Form, request, and lifecycle-identity failures | `:permanent` | no |

A transient class describes the protocol failure only. It is not permission to
repeat a non-idempotent operation; Runtime retry defaults still admit only
`readproperty` and `queryaction` unless the consumer states idempotence.

## Immutable values

`Wotex.Binding.HTTP.Request` contains only method, absolute URI, validated
fields, optional binary body, request id, deadline, operation, representation,
stream flag, and the `max_response_bytes` and `max_event_bytes` limits.
`Wotex.Binding.HTTP.Response` contains only status, validated fields, and a
complete binary body. Neither type has a credential field.

Both limits are positive integers taken from the configuration and are carried
on the request so a client can abort an oversized body or event while reading
instead of allocating it. The binding repeats both checks on the complete value
it receives; the request-borne limit is the client's obligation, not a proof.

Request targets must be absolute HTTP or HTTPS URIs with a host and without
user information, fragment, controls, whitespace, or unresolved templates.
Request bodies and response bodies have explicit byte limits.

## Field policy

Names use the RFC HTTP token grammar and are normalized to lowercase. Values
must be valid strings without NUL, CR, LF, or disallowed controls. Duplicate
names within one source fail. Form fields override same-named static fields.

Credential-bearing fields are rejected from both request and response values.
Host, connection, and message-framing request fields are rejected because the
supplied client owns them. Generated `accept` and `content-type` fields must not
conflict with Form fields.

## Public value matrix

Module names below are under `Wotex.Binding.HTTP`.

| Value/function | Contract | Allocation / effect |
|---|---|---|
| `Wotex.Binding.HTTP.Config.new/1` | Explicit client and nonsecret client configuration; request/response/event limits and static headers | Creates one nonsecret configuration-instance reference; no process/network |
| `Request.new/5` | Method, absolute URI, validated fields, optional body, identity, deadline, and required positive response/event byte limits | Immutable protocol request; no credential field |
| `Response.new/3` | Integer status 100–599, validated fields, complete binary body | Construction is not successful-status or response-size admission |
| `Headers.new/2`, `merge/2`, `put/3`, `get/2` | Validated lowercased fields and deterministic override | No cookie jar, credential store or wire framing |
| `Codec.encode/2`, `decode/2` | JSON term/binary and explicit positive byte limit; decoding delegates to `Wotex.JSON.decode/2` | Tagged failure without reflecting payload/codec exceptions; structural limits and duplicate members rejected before use |
| `EmptyBody.new/0` | Explicit no-body marker | Distinct from an encoded JSON null |
| `SSE.Event` / `Notification` | Framed event data, and the delivery metadata map (`event`, `id`, `retry`, `request_id`, `operation`) accompanying a decoded value | Client frames; binding adapts; no durable Event authority |
| `Subscription.new/4`, `unwrap/1` | Opaque client handle bound to opening operation/configuration instance | No registry or connection owner; WBH.03 governs close |

Configured defaults are `max_request_bytes: 1_048_576`,
`max_response_bytes: 4_194_304`, `max_event_bytes: 1_048_576`; each override must
be a positive integer. Test exactly-at/above-limit cases. The current codecs
may allocate encoded JSON before rejecting oversized output; an output limit
is not a whole-process memory limit. Headers, URI, nested decoded terms and
client callback memory require separate bounds/evidence in WBH-C03.

## Credential and destination security

The caller must supply credentials only through the immediate client callback,
never static/Form headers, URI userinfo, client configuration or a retained
connection process. Client-port code is trusted code; hiding `Inspect` fields cannot stop
it retaining a term or logging it. Client exceptions and error reasons must not
be copied into public values. Test nested external reasons, exception messages,
request/response inspection and connection-process captures independently.

TLS verification, DNS resolution, redirect allowlists, proxy policy, target
authorization, credential audiences and timeouts belong to the consumer client.
The binding's URI validation is syntax validation, not SSRF protection. A client
must not forward credentials to a redirected or Action-status target merely
because its URI passes syntax checks. No global security policy is installed.

## Compatibility and proof

`value_test.exs`, `error_test.exs`, `form_test.exs`, `transport_test.exs` and
`library_contract_test.exs` under `test/wotex/binding/http/` are the current
value/port evidence. Exact default limits, error code/phase/class, JSON-null
behavior, header precedence and callback tuples are observable API contracts. Alterations
need a specification/package compatibility decision and clean-consumer tests.
Config instance identity is process-local and not serializable capability,
cross-node admission or protection against forged internal structs.
