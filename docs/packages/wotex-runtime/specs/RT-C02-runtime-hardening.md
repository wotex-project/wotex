# RT-C02: Runtime hardening contract

Packet `RT-C02` defines the bounded ConsumedThing and subscription behavior
required by `docs/packages/wotex-runtime/plans/wotex-runtime-completion.md`.
The evidence is executable package behavior. This document does not record a
release-gate result or assign consumer and binding resource policy to Runtime.

## Admission bounds

Runtime applies shallow bounds where it owns admission before a port call or
delivery.

| Surface | Runtime bound | Executable evidence |
|---|---:|---|
| Request identity | 256 UTF-8 bytes | `test/wotex/runtime/value_test.exs` |
| Context and Result metadata | 64 top-level map entries | `test/wotex/runtime/value_test.exs` |
| Binding profiles | 32 entries | `test/wotex/runtime/consumed_thing_test.exs`, `test/wotex/runtime/form_selector_test.exs` |
| Forms examined for one interaction | 128 entries | `test/wotex/runtime/form_selector_test.exs` |
| Early subscription messages | 64 per opening subscription | `test/wotex/runtime/subscription_opening_test.exs` |
| Receiver mailbox | optional positive `max_queue_length` | `test/wotex/runtime/subscription_test.exs` |

Threshold vectors succeed and one-over vectors return typed errors or the
configured overflow outcome. List admission examines no more than the threshold
and one rejecting cell. An improper list within the admitted prefix is invalid.

These bounds do not cap payloads, nested metadata, opaque port configuration,
protocol frames, transport mailboxes, supervisor mailboxes, total process heap,
or native Software Development Kit allocation. Consumers and bindings own those
limits.

## Request and result boundary

Runtime constructs each `Wotex.Runtime.Request` from a validated selection and
caller context. A transport may return only a `Wotex.Runtime.Result` whose
request id and operation match that request. Runtime rejects substituted
identity or operation before publishing the result, then validates status and
metadata even when a transport returns a manually constructed struct.

ConsumedThing port calls run in the caller. Runtime propagates an absolute
deadline but does not interrupt a synchronous callback. The credential and
transport ports own callback latency, protocol timeouts, partial-resource
binding, and cancellation.

Credential values exist only in the private execution context used for a port
call. Normalized errors and exception telemetry omit the raw exception, exit or
throw reason, stacktrace, port details, and credential value. Opaque port
configuration and trusted consumer callbacks remain outside this guarantee.
The request/result and credential vectors are in
`test/wotex/runtime/consumed_thing_test.exs`.

## Subscription lifecycle

A receiver is a live pid or registered local name. Runtime resolves and monitors
that process without linking it. A missing or dead receiver prevents protocol
establishment or stops the subscription with `{:shutdown, :receiver_down}`.

Subscription establishment uses a monitored callback worker so receiver death,
owner death, and explicit cancellation remain responsive while a callback is
pending. Early deliveries remain ordered up to the fixed admission bound. An
overflow stops establishment as overloaded. These behaviors are exercised in
`test/wotex/runtime/subscription_opening_test.exs`.

Once established, the subscription applies the consumer's mailbox policy before
each delivery. `overflow: :drop` discards that delivery and emits drop telemetry;
`overflow: :stop` terminates the subscription as overloaded. The check samples a
local mailbox and does not provide backpressure or exactly-once delivery.

Concurrent explicit stop performs at most one unsubscribe. Credential,
subscribe, decode, and unsubscribe callbacks that raise, exit, throw, or return
malformed values produce typed errors without credential material. A graceful
stop attempts cleanup even when stop credential resolution fails. Forced
termination cannot prove remote cleanup. Receiver, overflow, stop, restart, and
callback-failure vectors are in `test/wotex/runtime/subscription_test.exs`.

## Qualifications

RT-C02 establishes deterministic local mechanics and the public
ConsumedThing/Transport correlation boundary. It does not establish callback
latency, recursive allocation bounds, durable or exactly-once delivery, remote
unsubscribe, binding-native correlation, transport interoperability, canonical
Thing state, or physical effect.
