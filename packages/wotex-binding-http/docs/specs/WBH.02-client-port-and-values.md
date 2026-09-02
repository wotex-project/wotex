# Client port and HTTP value specification

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
