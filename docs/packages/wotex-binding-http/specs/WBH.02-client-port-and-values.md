# WBH.02: Client port and HTTP values

Specification `WBH.02@1.1.1`; package baseline `wotex_binding_http 0.1.0`.
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

The client owns network I/O, HTTP version selection, TLS and destination/redirect
policy, credential-audience admission, deadlines, proxy behavior, response
collection, SSE framing, connection reuse, backpressure, and reconnection. This
package supplies no client or pool.

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
stream flag, and the response/event, field-count, aggregate field-byte, and URI
limits.
`Wotex.Binding.HTTP.Response` contains only status, validated fields, and a
complete binary body. Neither type has a credential field.

All limits are positive integers taken from configuration. Response/event,
field, and URI ceilings are carried on the request so a client can abort an
oversized body, event, field block, or redirect while reading instead of first
allocating its complete representation. The binding repeats its checks on the
complete values it receives; request-borne limits are client obligations, not
proof about an arbitrary implementation.

Request targets must be absolute HTTP or HTTPS URIs with a host and without
user information, fragment, controls, whitespace, or unresolved templates.
Request bodies and response bodies have explicit byte limits. Request targets
also have an explicit byte limit.

## Field policy

Names use the RFC HTTP token grammar and are normalized to lowercase. Values
must be valid strings without NUL, CR, LF, or disallowed controls. Duplicate
names within one source fail. Form fields override same-named static fields.

Credential-bearing fields are rejected from both request and response values.
Host, connection, and message-framing request fields are rejected because the
supplied client owns them. Generated `accept` and `content-type` fields must not
conflict with Form fields. The final request and each returned response are
limited by field count and by the sum of normalized field-name and field-value
bytes. That aggregate excludes wire delimiters, compression, and client-library
objects, which remain client limits.

## Public value matrix

Module names below are under `Wotex.Binding.HTTP`.

| Value/function | Contract | Allocation / effect |
|---|---|---|
| `Wotex.Binding.HTTP.Config.new/1` | Explicit client and nonsecret client configuration; body/event, field, and URI limits; static headers | Creates one nonsecret configuration-instance reference; no process/network |
| `Request.new/5` | Method, bounded absolute URI, validated/bounded fields, optional body, identity, deadline, and positive client-facing admission limits | Immutable protocol request; no credential field |
| `Response.new/3` | Integer status 100–599, validated fields, complete binary body | Construction is not successful-status or response-size admission |
| `Headers.new/2`, `merge/2`, `put/3`, `get/2` | Validated lowercased fields and deterministic override | No cookie jar, credential store or wire framing |
| `Codec.encode/2`, `decode/2` | JSON term/binary and explicit positive byte limit; decoding delegates to `Wotex.JSON.decode/2` | Tagged failure without reflecting payload/codec exceptions; structural limits and duplicate members rejected before use |
| `EmptyBody.new/0` | Explicit no-body marker | Distinct from an encoded JSON null |
| `SSE.Event` / `Notification` | Framed event data, and the delivery metadata map (`event`, `id`, `retry`, `request_id`, `operation`) accompanying a decoded value | Client frames; binding adapts; no durable Event authority |
| `Subscription` handle | Opaque client handle bound to the opening operation and configuration instance; constructed and unwrapped only inside the binding | Consumers hold it and pass it back; no registry or connection owner; WBH.03 governs close |

Configured defaults are `max_request_bytes: 1_048_576`,
`max_response_bytes: 4_194_304`, `max_event_bytes: 1_048_576`,
`max_header_count: 64`, `max_header_bytes: 65_536`, and `max_uri_bytes: 8_192`;
each override must be a positive integer. Native JSON validation applies the
configured string/key-payload ceiling and core structural defaults before
encoding, followed by an exact encoded-byte check. Existing caller terms,
encoded syntax overhead, complete client returns, and process mailboxes mean
these limits are not a whole-process memory guarantee.

## Credential and destination security

The caller must supply credentials only through the immediate client callback,
never static/Form headers, URI userinfo, client configuration or a retained
connection process. Client-port code is trusted code; hiding `Inspect` fields cannot stop
it retaining a term or logging it. Client exceptions and error reasons must not
be copied into public values. Test nested external reasons, exception messages,
request/response inspection and connection-process captures independently.

TLS verification, DNS resolution, redirect allowlists, proxy policy, target
authorization, credential audiences and timeouts belong to the consumer client
and host.
The binding's URI validation is syntax validation, not SSRF protection. A client
must not forward credentials to a redirected or Action-status target merely
because its URI passes syntax and length checks. The client authorizes the exact
initial target, DNS/IP results, proxy route, and each redirect before applying a
credential within its audience. No global security policy is installed.

## Compatibility and proof

The [client lifecycle inventory](../client-lifecycle-inventory.md) and the
[limits and security inventory](../limits-security-inventory.md) map
the complete callback, lifecycle, limit, and security reviews to named vectors.
`value_test.exs`, `error_test.exs`, `form_test.exs`, `transport_test.exs`,
`client_lifecycle_inventory_test.exs`, `limits_security_test.exs` and
`library_contract_test.exs` under `test/wotex/binding/http/` are the current
value/port evidence. Exact default limits, error code/phase/class, JSON-null
behavior, header precedence and callback tuples are observable API contracts.
Alterations need a specification/package compatibility decision and
clean-consumer tests. Config instance identity is process-local and not
serializable capability, cross-node admission or protection against forged
internal structs.
