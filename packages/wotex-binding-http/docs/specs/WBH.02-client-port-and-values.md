# WBH.02: Client port and HTTP values

Specification `WBH.02@1.0.0`; package baseline `wotex_binding_http 0.1.0`.
Requires `wotex_runtime:WRT.01`; WBH.01 owns operation mapping and WBH.03 streams.

## Client callbacks

A consumer-supplied module implements:

```elixir
request(http_request, credential, client_config)
subscribe(http_request, credential, event_handler, client_config)
close(opaque_handle, client_config)
```

`request/3` returns `{:ok, response}` or `{:error, reason}`.
`subscribe/4` returns `{:ok, opaque_handle, handshake_response}` or an error.
`close/2` returns `:ok` or an error. The binding validates every return.

The client configuration must be non-credential configuration. The credential
argument is ephemeral, is separate from the immutable HTTP request, and must
not be retained or captured by the stream event handler. Client errors are
normalized without copying their reasons.

The client owns network I/O, HTTP version selection, TLS and redirect policy,
deadlines, proxy behavior, response collection, SSE framing, connection reuse,
backpressure, and reconnection. This package supplies no client or pool.

## Immutable values

`Wotex.Binding.HTTP.Request` contains only method, absolute URI, validated
fields, optional binary body, request id, deadline, operation, representation,
and stream flag. `Wotex.Binding.HTTP.Response` contains only status, validated
fields, and a complete binary body. Neither type has a credential field.

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
| `Request.new/5` | Method, absolute URI, validated fields, optional body and request options | Immutable protocol request; no credential field |
| `Response.new/3` | Integer status 100–599, validated fields, complete binary body | Construction is not successful-status or response-size admission |
| `Headers.new/2`, `merge/2`, `put/3`, `get/2` | Validated lowercased fields and deterministic override | No cookie jar, credential store or wire framing |
| `Codec.encode/2`, `decode/2` | JSON term/binary and explicit positive byte limit | Tagged failure without reflecting payload/codec exceptions |
| `EmptyBody.new/0` | Explicit no-body marker | Distinct from an encoded JSON null |
| `SSE.Event` / `Notification` | Framed event data and decoded payload with request/operation metadata | Client frames; binding adapts; no durable Event authority |
| `Subscription.new/4`, `unwrap/1` | Opaque client handle bound to opening operation/configuration instance | No registry or connection owner; WBH.03 governs close |

Configured defaults are `max_request_bytes: 1_048_576`,
`max_response_bytes: 4_194_304`, `max_event_bytes: 1_048_576`; each override must
be a positive integer. Test exactly-at/above-limit cases. The current codecs
may allocate encoded JSON before rejecting oversized output; an output limit
is not a whole-process memory limit. Headers, URI, nested decoded terms and
client callback memory require separate bounds/evidence in WBH-C03.

## Credential and destination security

The caller must supply credentials only through the immediate client callback,
never static/Form headers, URI userinfo, client configuration or stream
closures. Client-port code is trusted code; hiding `Inspect` fields cannot stop
it retaining a term or logging it. Client exceptions and error reasons must not
be copied into public values. Test nested external reasons, exception messages,
request/response inspection and stream closure captures independently.

TLS verification, DNS resolution, redirect allowlists, proxy policy, target
authorization, credential audiences and timeouts belong to the consumer client.
The binding's URI validation is syntax validation, not SSRF protection. A client
must not forward credentials to a redirected or Action-status target merely
because its URI passes syntax checks. No global security policy is installed.

## Compatibility and proof

`value_test.exs`, `error_test.exs`, `form_test.exs` and
`library_contract_test.exs` under `test/wotex/binding/http/` are the current
value/port evidence. Exact default limits, error code/phase, JSON-null behavior,
header precedence and callback tuples are observable API contracts. Alterations
need a specification/package compatibility decision and clean-consumer tests.
Config instance identity is process-local and not serializable capability,
cross-node admission or protection against forged internal structs.
