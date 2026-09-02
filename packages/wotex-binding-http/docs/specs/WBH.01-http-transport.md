# HTTP transport specification

## Scope

The package implements the `Wotex.Runtime.Transport` callbacks from Runtime
version `~> 0.1.0`:

```elixir
request(request, execution_context, config)
subscribe(request, receiver, execution_context, config)
unsubscribe(handle, request, execution_context, config)
```

The binding profile is constructed with `Wotex.Runtime.BindingProfile.new/1`,
uses id `:http`, supports `http` and `https`, and declares the nine operations
in the pinned Runtime API. Form selection remains Runtime responsibility.

## Form-to-message mapping

| WoT operation | Missing `htv:methodName` | Body | Response |
| --- | --- | --- | --- |
| `readproperty` | `GET` | none | optional JSON value |
| `writeproperty` | `PUT` | JSON input | optional JSON value |
| `invokeaction` | `POST` | JSON input or explicit empty marker | optional JSON value |
| `queryaction` | `GET` | none; input identifies `ActionStatus` | optional JSON value |
| `cancelaction` | `DELETE` | none; input identifies `ActionStatus` | optional JSON value |
| `observeproperty` | `GET` | none | SSE handshake |
| `subscribeevent` | `GET` | none | SSE handshake |
| `unobserveproperty` | close | none | no HTTP exchange |
| `unsubscribeevent` | close | none | no HTTP exchange |

An explicit valid `htv:methodName` is preserved exactly because HTTP methods
are case-sensitive. It is rejected when a Form declares multiple operations.

Missing `contentType` means `application/json`. A Form-level `response`
`contentType` is honored only when it is also `application/json`. Version 0.1
does not implement other representations.

`queryaction` and `cancelaction` accept an absolute or relative href string, a
map with an `href`, or a prior Runtime result containing a resolved HTTP
`Location` or payload `href`. Relative targets resolve against the selected
Form target. Unsafe targets fail before the client call.

## Result mapping

Only status codes 200 through 299 produce Runtime results. Empty response
bodies become `nil`; non-empty bodies must be JSON and must match the Form
representation. Status 204 and 205 reject non-empty bodies.

Result metadata contains the HTTP method, request URI, validated response
fields, and a resolved `Location` when present. It contains no credentials.
Transport success is only a protocol outcome and does not establish canonical
Property truth or prove a physical Action effect.

## Failure rules

Invalid Form terms, fields, methods, URIs, representations, byte sizes,
statuses, client returns, and JSON fail as structured
`Wotex.Binding.HTTP.Error` values. External client reasons and exceptions are
not retained in returned errors.
