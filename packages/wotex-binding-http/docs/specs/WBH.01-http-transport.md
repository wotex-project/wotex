# WBH.01: HTTP transport specification

Specification `WBH.01@1.0.0`; package baseline `wotex_binding_http 0.1.0`.
Requires `WBH.02`, `wotex_runtime:WRT.01`. This is an implementation contract,
not a completed standards or release claim; see
the repository completion plan at `docs/plans/wotex-binding-http-completion.md`.

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

## Ownership and public entry points

`Wotex.Binding.HTTP.profile/0` declares the nine operations above.
`config/1` validates consumer client/options, `transport/1` returns the explicit
Runtime port/config pair, and `empty_body/0` distinguishes absent input from
JSON `null`. `Form.build/2` maps a selected Runtime Request to an immutable HTTP
Request; `Transport.request/3`, `subscribe/4`, `unsubscribe/4` implement the
callback boundary. The binding never selects a profile after a failed match.

Runtime owns Form selection, request identity, ephemeral credentials and
consumer-supervised subscriptions. Wotex owns TD values. The consumer client
owns wire exchange and sessions; the consumer host owns policy, accepted Thing
state, Action lifecycle/effect and durable Event handling. There is no endpoint,
server route, global registry, framework, connection manager or task scheduler.

## Execution and effect contract

| Phase | Required behavior | Negative evidence |
|---|---|---|
| Map | Validate method, URI, operation, representation and fields before calling client | Invalid multi-op method override, unsafe URI and unsupported operation invoke no client |
| Encode | JSON or explicit absent body; bound output | Empty marker differs from JSON null; unsupported representation and oversize fail |
| Execute | One explicit client request in caller; credential passed separately | Invalid/raising client returns become redacted errors; no hidden retry |
| Decode | Validate response type/status/headers/body before Runtime result | Non-2xx, malformed JSON, unsupported content type and nonempty 204/205 fail |
| Continue Action | Resolve safe Location/href locator against selected target | Locator is not Action completion, authority or an automatic follow-up request |
| Recover | Return failure to consumer | No automatic redirect, reconnect, Action retry or compensation |

The existing implementation collects complete binary bodies. A byte limit is
not a guarantee that the client did not allocate the body beforehand. WBH-C03
must prove allocation and redirect/deadline policy at the consumer boundary.
Cross-origin Action locators need consumer authorization and credential
audience checks; syntactically valid HTTP targets are not trusted destinations.

## Explicit unsupported cells

Thing-level operations from WRT.03, non-JSON representations, MQTT messages,
HTTP server exposure and complete WoT Profiles conformance are not declared by
this profile. Do not silently map them to one of the nine supported operations.
An error before client invocation has no protocol effect; an error after I/O
does not prove the remote Action did not execute. HTTP status alone does not
classify physical-effect certainty.

## Standards and executable evidence

`docs/standards-baseline.md` fixes TD 1.1 Recommendation 2023-12-05, HTTP
Semantics RFC 9110, framing delegation RFC 9112, JSON RFC 8259, and explicitly
draft-derived Profile mappings. `form_test.exs`, `transport_test.exs` and
`integration_test.exs` under `test/wotex/binding/http/` prove the package subset.
Each new claim requires source revision, exact operation, preconditions,
negative cells and named tests. A draft-derived GET/DELETE/SSE mapping remains
package behavior, not W3C endorsement or registry membership.
