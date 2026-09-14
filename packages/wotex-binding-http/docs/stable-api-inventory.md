# Stable API candidate inventory

This `WBH-C06` inventory freezes the supported consumer surface for package
baseline `wotex_binding_http 0.1.0`. The freeze covers documented functions,
protocol values, Runtime callbacks, supplied-client callbacks and messages,
operation mappings, defaults, limits, result mapping, and binding error
identities. The executable vectors live in
`test/wotex/binding/http/stable_api_inventory_test.exs`; the deterministic
`bin/check_stable_api.exs` gate keeps the inventory, source error codes, package
contents, and vector names in sync.

| Cell | Frozen contract | Named vectors |
| --- | --- | --- |
| WBH-K01 | Documented consumer entry points and public function arities | WBH-K01-P, WBH-K01-N |
| WBH-K02 | Nine Runtime operations, seven HTTP defaults, two close pairs, JSON/SSE representations, and draft authorities | WBH-K02-P, WBH-K02-N |
| WBH-K03 | Request, response, configuration, event, notification, empty-body, subscription, and error value shapes | WBH-K03-P, WBH-K03-N |
| WBH-K04 | Six configuration defaults, positive overrides, exact byte/count measurements, field normalization, and override precedence | WBH-K04-P, WBH-K04-N |
| WBH-K05 | Client and Runtime callback arities, callback return tuples, owner frame/status messages, and Runtime receiver deliveries | WBH-K05-P, WBH-K05-N |
| WBH-K06 | HTTP result status/metadata mapping and the complete binding error code/phase/class surface | WBH-K06-P, WBH-K06-N |
| WBH-K07 | Credential separation, redaction, opaque-handle inspection, and no package process/application callback | WBH-K07-P, WBH-K07-N |
| WBH-K08 | Compatibility, draft-revision, migration, and release nonclaims | WBH-K08-P, WBH-K08-N |

## Supported consumer functions

The compatibility surface consists of these documented calls plus the Runtime
transport callbacks in the final row. Default arguments provide both listed
arities. Functions marked `@doc false`, including `Form.build/2`,
`Subscription.new/4`, `Subscription.unwrap/1`, `Error.new/3..5`, configuration
default helpers, and header-limit helpers, remain package implementation
details even though the BEAM can call them.

| Module | Supported functions |
| --- | --- |
| `Wotex.Binding.HTTP` | `profile/0`, `config/1`, `transport/1`, `empty_body/0` |
| `Wotex.Binding.HTTP.Config` | `new/1`, `client/1`, `instance_ref/1`, `headers/1`, `max_request_bytes/1`, `max_response_bytes/1`, `max_event_bytes/1`, `max_header_count/1`, `max_header_bytes/1`, `max_uri_bytes/1` |
| `Wotex.Binding.HTTP.Error` | `class/1` |
| `Wotex.Binding.HTTP.Headers` | `new/1`, `new/2`, `merge/2`, `put/3`, `get/2`, `token?/1` |
| `Wotex.Binding.HTTP.Request` | `new/5`, `method/1`, `uri/1`, `headers/1`, `body/1`, `request_id/1`, `deadline/1`, `operation/1`, `media_type/1`, `stream?/1`, `max_response_bytes/1`, `max_event_bytes/1`, `max_header_count/1`, `max_header_bytes/1`, `max_uri_bytes/1` |
| `Wotex.Binding.HTTP.Response` | `new/3`, `status/1`, `headers/1`, `body/1` |
| `Wotex.Binding.HTTP.EmptyBody` | `new/0` |
| `Wotex.Binding.HTTP.SSE.Event` | `new/1`, `new/2`, `data/1`, `event/1`, `id/1`, `retry/1` |
| `Wotex.Binding.HTTP.Notification` | `new/3` |
| `Wotex.Binding.HTTP.Client` | callbacks `request/3`, `subscribe/4`, `close/2` |
| `Wotex.Binding.HTTP.Transport` | Runtime callbacks `request/3`, `subscribe/4`, `unsubscribe/4`, `decode_frame/3` |

## Values, defaults, and messages

Consumers construct request, response, configuration, and event values through
their constructors and read them through accessors. `%Config{}` and `%Request{}`
retain the fields declared by their public types. `%Response{}` retains
`status`, `headers`, and `body`; `%SSE.Event{}` retains `data`, `event`, `id`,
and `retry`; `%Error{}` retains the exception marker plus `code`, `phase`,
`class`, `message`, and `details`. `%EmptyBody{}` has no fields.
`%Subscription{}` is opaque: only its
module identity and documented Inspect projection are stable, not its internal
keys or a serialization format. Notification metadata is exactly
`%{event: ..., id: ..., retry: ..., request_id: ..., operation: ...}`.

The configuration defaults remain `max_request_bytes: 1_048_576`,
`max_response_bytes: 4_194_304`, `max_event_bytes: 1_048_576`,
`max_header_count: 64`, `max_header_bytes: 65_536`, and `max_uri_bytes: 8_192`.
Each limit is a positive integer. Body, event, and URI bounds use encoded bytes;
the field bound sums normalized field-name and field-value bytes. These local
admission values are not HTTP standard limits or total-memory guarantees.

The supplied client returns either `{:ok, response}` or `{:error, reason}` from
`request/3`. It returns either `{:ok, handle, handshake_response}` or
`{:error, reason}` from `subscribe/4`, and either `:ok` or `{:error, reason}`
from `close/2`. It sends only
`{:wotex_transport_frame, %Wotex.Binding.HTTP.SSE.Event{}}` and
`{:wotex_transport_status, :reconnected | :session_lost | :transport_down}` to
the supplied Runtime owner. Runtime receivers observe
`{:wotex_runtime, subscription_id, {:ok, data, meta}}`,
`{:wotex_runtime, subscription_id, {:error, %Wotex.Runtime.Error{}}}`, or
`{:wotex_runtime, subscription_id, {:status, status}}`. These tuple shapes and
atoms are compatibility surfaces; socket messages, parser state, and client
process protocols are not.

## Operation and result decisions

`readproperty`, `writeproperty`, and `invokeaction` retain the TD 1.1 defaults
`GET`, `PUT`, and `POST`. The package retains the dated WoT Profiles Working
Draft 2025-11-04 choices `queryaction: GET`, `cancelaction: DELETE`,
`observeproperty: GET` plus `sse`, and `subscribeevent: GET` plus `sse`.
`unobserveproperty` and `unsubscribeevent` close the paired opaque handle and do
not create HTTP requests. A future draft does not change these mappings without
a reviewed specification and compatibility decision.

A successful response maps HTTP 202 to Runtime result status `:accepted`; all
other successful 2xx statuses map to `:ok`. An empty successful body maps to
payload `nil`. Result metadata is `%{http: %{method: method, request_uri: uri,
status: status, headers: headers}}`; a valid resolved Location adds
`location: absolute_uri` to that inner map. This metadata records protocol
facts. It does not authorize a redirect or Action target or assert a remote
effect.

## Error identity manifest

The stable part of an error is its `code`, `phase`, and `class`. `message` is
human-readable and may improve without a compatibility release. `details`
remains credential-free diagnostic context; consumers may use documented keys
but must tolerate additional safe keys. Client reasons and exception terms are
never part of this surface.

<!-- error-manifest:start -->
| Code | Phase | Class |
| --- | --- | --- |
| `:invalid_config_options` | `:configuration` | `:permanent` |
| `:invalid_client` | `:configuration` | `:permanent` |
| `:invalid_limit` | `:configuration` | `:permanent` |
| `:conflicting_header` | `:form` | `:permanent` |
| `:invalid_form_header` | `:form` | `:permanent` |
| `:invalid_form_headers` | `:form` | `:permanent` |
| `:invalid_media_type` | `:form` or `:request` | `:permanent` |
| `:invalid_method` | `:form` or `:request` | `:permanent` |
| `:method_on_multi_operation_form` | `:form` | `:permanent` |
| `:no_default_method` | `:form` | `:permanent` |
| `:unsupported_media_type` | `:form` | `:permanent` |
| `:unsupported_response_media_type` | `:form` | `:permanent` |
| `:unsupported_subprotocol` | `:form` | `:permanent` |
| `:credential_header_forbidden` | `:request` | `:permanent` |
| `:duplicate_header` | `:request` | `:permanent` |
| `:framing_header_forbidden` | `:request` | `:permanent` |
| `:invalid_action_target` | `:request` | `:permanent` |
| `:invalid_admission_limit` | `:request` | `:permanent` |
| `:invalid_body` | `:request` | `:permanent` |
| `:invalid_byte_limit` | `:request` | `:permanent` |
| `:invalid_deadline` | `:request` | `:permanent` |
| `:invalid_header` | `:request` | `:permanent` |
| `:invalid_header_name` | `:request` | `:permanent` |
| `:invalid_header_value` | `:request` | `:permanent` |
| `:invalid_headers` | `:request` | `:permanent` |
| `:invalid_request` | `:request` | `:permanent` |
| `:invalid_request_identity` | `:request` | `:permanent` |
| `:invalid_runtime_request` | `:request` | `:permanent` |
| `:invalid_stream_flag` | `:request` | `:permanent` |
| `:invalid_transport_arguments` | `:request` | `:permanent` |
| `:invalid_uri` | `:request` | `:permanent` |
| `:missing_action_target` | `:request` | `:permanent` |
| `:missing_input` | `:request` | `:permanent` |
| `:stream_requires_subscribe` | `:request` | `:permanent` |
| `:unexpected_input` | `:request` | `:permanent` |
| `:unsupported_operation` | `:request` | `:permanent` |
| `:unsupported_scheme` | `:request` | `:permanent` |
| `:uri_credentials_forbidden` | `:request` | `:permanent` |
| `:uri_fragment_forbidden` | `:request` | `:permanent` |
| `:uri_too_large` | `:request` | `:permanent` |
| `:invalid_decode_input` | `:codec` | `:permanent` |
| `:invalid_encode_limit` | `:codec` | `:permanent` |
| `:json_decode_failed` | `:codec` | `:protocol` |
| `:json_encode_failed` | `:codec` | `:protocol` |
| `:json_limit_exceeded` | `:codec` | `:protocol` |
| `:request_body_too_large` | `:codec` | `:protocol` |
| `:response_body_too_large` | `:codec` or `:response` | `:protocol` |
| `:invalid_response` | `:response` | `:permanent` |
| `:http_status` | `:response` | 408 `:timeout`; 429 `:rate_limited`; 502/503/504 `:unavailable`; every other non-2xx `:permanent` |
| `:invalid_location` | `:response` | `:protocol` |
| `:result_build_failed` | `:response` | `:protocol` |
| `:unexpected_response_body` | `:response` | `:protocol` |
| `:unexpected_response_media_type` | `:response` | `:protocol` |
| `:client_request_exception` | `:client` | `:unavailable` |
| `:client_request_failed` | `:client` | reason `:timeout` gives `:timeout`; every other reason gives `:unavailable` |
| `:invalid_client_return` | `:client` or `:subscription` | `:protocol` |
| `:client_close_exception` | `:subscription` | `:unavailable` |
| `:client_close_failed` | `:subscription` | reason `:timeout` gives `:timeout`; every other reason gives `:unavailable` |
| `:client_subscribe_exception` | `:subscription` | `:unavailable` |
| `:client_subscribe_failed` | `:subscription` | reason `:timeout` gives `:timeout`; every other reason gives `:unavailable` |
| `:invalid_sse_event` | `:subscription` | `:protocol` |
| `:invalid_sse_field` | `:subscription` | `:protocol` |
| `:invalid_sse_retry` | `:subscription` | `:protocol` |
| `:invalid_subscription_arguments` | `:subscription` | `:permanent` |
| `:invalid_unsubscribe_arguments` | `:subscription` | `:permanent` |
| `:operation_is_not_streaming` | `:subscription` | `:permanent` |
| `:sse_event_too_large` | `:subscription` | `:protocol` |
| `:sse_handshake_body` | `:subscription` | `:protocol` |
| `:sse_handshake_media_type` | `:subscription` | `:protocol` |
| `:sse_handshake_status` | `:subscription` | `:protocol` |
| `:subscription_client_mismatch` | `:subscription` | `:permanent` |
| `:subscription_operation_mismatch` | `:subscription` | `:permanent` |
| `:subscription_request_mismatch` | `:subscription` | `:permanent` |
| `:invalid_header_limits` | caller phase | `:protocol` for `:response`/`:subscription`; otherwise `:permanent` |
| `:header_count_exceeded` | caller phase | `:protocol` for `:response`/`:subscription`; otherwise `:permanent` |
| `:header_bytes_exceeded` | caller phase | `:protocol` for `:response`/`:subscription`; otherwise `:permanent` |
<!-- error-manifest:end -->

## Compatibility and migration decisions

The C06 decision keeps every existing documented name, arity, tuple, atom,
default, limit measurement, mapping, and value projection. No rename,
deprecation alias, data migration, or consumer code migration is required for
the `0.1.0` candidate. A proposed incompatible change must update the normative
WBH specification, this manifest and its vectors, and the package version under
the project's release policy. Draft text, a new HTTP client, or an internal
refactor cannot silently alter these choices.

This is source and exact-archive compatibility evidence for one pinned
Elixir/OTP pair and dependency cohort. It does not establish a published
release, registry installation, ABI compatibility between BEAM toolchains,
serialized struct compatibility, a broad runtime matrix, complete HTTP or WoT
conformance, production-client interoperability, remote-effect certainty, or
permission to publish.
