# WRT.02: ExposedThing callback mechanics

Specification: `WRT.02@1.1.0`. Requires `WRT.01@1.3.0`.
Package baseline: `wotex_runtime 0.1.0`; see the
repository completion plan at `docs/plans/wotex-runtime-completion.md` for unproven claims.

## Implemented boundary

The complete callback surface below is implemented without a server process or
implicit serialization. Repository tests prove that invalid named and
Thing-level routes never invoke an otherwise available handler, eight blocked
callbacks enter concurrently in eight caller processes, callback error values
pass through unchanged, and both raises and exits propagate to the caller.
These are package-source results; inbound authentication, selected Form,
schema and policy enforcement remain the consumer server's responsibility.

## Ownership

The package owns a binding-neutral ExposedThing value, operation/affordance
route checks, handler lookup, and callback dispatch. It does not own an HTTP or
MQTT server, router, endpoint, authentication, canonical Thing state, or policy.

## Requirements

1. Construction MUST require a validated `Wotex.ThingDescription` and explicit
   handler map.
2. Dispatch MUST verify that the referenced Property, Action, or Event exists
   before calling a handler.
3. Handlers MUST be keyed by the exact runtime operation and affordance name.
4. Missing affordances and handlers MUST return stable typed errors.
5. Handler exceptions MUST not be rescued into false success.
6. Returned values are callback outcomes. A consumer decides whether and how
   they alter canonical state or evidence.
7. Server bindings MUST adapt inbound protocol messages to this contract without
   importing consumer policy into Wotex Runtime.

## Evidence

Tests cover Property, Action, and Event dispatch, missing affordances, missing
handlers, input/context forwarding, and callback error propagation.

## Independently implementable dispatch matrix

| Operation family | Handler key | Dispatch entry | Required checks |
|---|---|---|---|
| Property read/write | `{operation, property_name}` | `dispatch/5` | Supported Property operation and named Property Affordance |
| Property observe/unobserve | `{operation, property_name}` | `dispatch/5` | Same route checks; consumer handler owns observation semantics |
| Action invoke/query/cancel | `{operation, action_name}` | `dispatch/5` | Supported Action operation and named Action Affordance |
| Event subscribe/unsubscribe | `{operation, event_name}` | `dispatch/5` | Supported Event operation and named Event Affordance |
| Thing-level aggregate operations | `operation` | `dispatch_thing/4` | Exact operation explicitly present in a top-level Form, then handler |

The names above refer to `Wotex.Runtime.ExposedThing`. `new/2` accepts a
validated `Wotex.ThingDescription` and a map of arity-two functions. Each
callback receives the original input and `Wotex.Runtime.Context`; its result is
returned unchanged. `thing_description/1` returns the immutable TD.

The implementation validates named-affordance existence, not a selected
inbound protocol Form for `dispatch/5`. Thus an available handler is not proof
of a Form operation declaration or authorization. The consumer server MUST
validate its selected binding, operation access, schema and policy before
dispatch. RT-C03 must make this division explicit in negative vectors; do not
claim full inbound TD validation from route existence alone.

## Failure, concurrency and lifecycle

| Input or event | Required result / owner |
|---|---|
| Invalid TD or handler map | Constructor rejects; no callback starts |
| Unsupported operation or wrong entry point | Typed `unsupported_operation`; no handler call |
| Missing affordance | Typed `affordance_not_found` |
| Missing Thing-level declaration | Typed `thing_operation_not_found` |
| Missing handler | Typed `handler_not_found` |
| Invalid dispatch/context | Typed construction/dispatch error |
| Handler returns an error | Propagated callback result, never rewritten as success |
| Handler raises/exits | Propagates to caller; consumer owns error disclosure and supervision |
| Concurrent invocations | Independent caller executions; no implicit serialization or mutex |
| Consumer shutdown | No package process to drain; consumer drains its in-flight callbacks |

The value itself has no mutable lifecycle or recovery log. Handler side effects
are consumer effects; no transaction, deduplication, idempotency, cancellation,
retry or physical-effect guarantee is added by dispatch. Query/cancel handlers
must use consumer-owned Action identity and lifecycle facts.

## Allocation, credentials and compatibility

Handlers capture arbitrary consumer terms and run synchronously. Their memory,
I/O, timeout and concurrency budgets are consumer-owned. There is no hidden
worker pool or scheduler. Request bodies, metadata, callbacks and outputs need
consumer limits before invoking this API. The package does not accept inbound
credentials or perform TLS/authentication; do not place secrets in Context
metadata, handler error messages or public callback outcomes.

`exposed_thing_test.exs` proves route/handler checks, no-callback negative
routes, concurrent caller execution, forwarding and exception propagation;
`library_contract_test.exs` proves the passive package boundary. RT-C04 adds
independent consumer-server and archive evidence.
No HTTP/MQTT server, endpoint, policy framework, canonical Property database or
full WoT Scripting API implementation is implied. Handler-key changes, exception
policy changes and stronger Form checks are observable compatibility changes,
not invisible cleanup; record them under a successor specification.
