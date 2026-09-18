# WRT-C03: ExposedThing boundary contract

Packet `WRT-C03` defines the source-side boundary of
`Wotex.Runtime.ExposedThing`. It records Runtime-owned routing and
consumer-owned request admission. It does not claim an inbound server,
protocol interoperability, or a release-gate result.

## Dispatch boundary

An ExposedThing contains a Thing Description and an explicit handler map.
Dispatch runs synchronously in the caller.

| Entry | Runtime checks before callback | Consumer checks before dispatch |
|---|---|---|
| `dispatch/5` | supported Property, Action, or Event operation; matching named Interaction Affordance; exact `{operation, name}` handler; valid Runtime Context | selected inbound binding and Form; protocol method and media handling; input and output schema; authentication, authorization, safety, and overload policy |
| `dispatch_thing/4` | supported Thing-level operation; operation declared by a top-level Form; exact operation handler; valid Runtime Context | selected inbound binding and Form; request payload semantics; authentication, authorization, safety, and overload policy |

A named Interaction Affordance route does not prove that a particular inbound
Form was selected or declares the operation. Runtime passes input and Context
metadata to the consumer handler without schema or policy interpretation. The
consumer server rejects inadmissible exchanges before dispatch.

Thing-level dispatch requires the operation in a top-level Form. This proves
only that the Thing Description declares the route. It does not prove that an
inbound exchange selected that Form or passed policy.

## Operation families

`dispatch/5` admits the named operations below through their matching
Interaction Affordance type:

- Property: `readproperty`, `writeproperty`, `observeproperty`, and
  `unobserveproperty`;
- Action: `invokeaction`, `queryaction`, and `cancelaction`; and
- Event: `subscribeevent` and `unsubscribeevent`.

`dispatch_thing/4` admits `readallproperties`, `writeallproperties`,
`readmultipleproperties`, `writemultipleproperties`, `observeallproperties`,
`unobserveallproperties`, `queryallactions`, `subscribeallevents`, and
`unsubscribeallevents`.

Each operation succeeds through its own entry when the route and handler are
present and returns `unsupported_operation` through the other entry. The
operation vectors are in `test/wotex/runtime/exposed_thing_test.exs`.

## Negative routes and caller-owned admission

An unsupported operation, missing Interaction Affordance, missing top-level
Form declaration, invalid Runtime Context, or absent handler returns a typed
Runtime error without invoking an available callback.

The same evidence demonstrates the ownership boundary by dispatching three
values that Runtime deliberately does not interpret: a named operation absent
from the affordance's Forms, input that contradicts the affordance's schema,
and Context metadata representing a consumer policy decision. The handler
receives these values unchanged. This behavior requires the consumer to perform
Form, schema, and policy admission before dispatch.

## Execution and failures

Concurrent dispatches execute in their independent caller processes. Runtime
adds no server, registry, worker pool, or serialization point. Callback return
values pass through unchanged. Raises and exits propagate to the caller through
both dispatch entries.

The consumer owns callback supervision, error disclosure, deadlines,
cancellation, memory and I/O budgets, and shutdown of in-flight callers.
WRT-C03 does not establish canonical Thing state, transactions, retries,
idempotency, durable recovery, or physical effect.
