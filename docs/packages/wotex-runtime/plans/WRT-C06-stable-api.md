# WRT-C06: Stable API candidate

Packet `WRT-C06` records the `wotex_runtime 0.1.0` compatibility candidate. The
decision covers consumer-visible values, callback and delivery shapes,
operation semantics, typed errors, limits, and lifecycle defaults. It does not
freeze an exhaustive export list, private helper, complete struct layout,
documentation wording, or test organization.

## Retained contract

| Surface | Compatibility promise | Behavioral evidence |
|---|---|---|
| Context and profile construction | callers supply request identity, deadlines, metadata, binding ids, schemes, operations, and media types; malformed values return typed errors | `test/wotex/runtime/value_test.exs` |
| Form selection | Thing Description Form order precedes profile order; unsupported, absent, and incompatible cells fail explicitly | `test/wotex/runtime/form_selector_test.exs` |
| ConsumedThing requests | short operations run in the caller through explicit credential and transport ports; returned Result identity and operation must match the Request | `test/wotex/runtime/consumed_thing_test.exs` |
| ExposedThing dispatch | callbacks run in the caller; Runtime validates its declared route while the consumer owns inbound Form, schema, and policy admission | `test/wotex/runtime/exposed_thing_test.exs` |
| Subscriptions | child specifications are inert; the caller supplies identity, receiver, naming, supervision, restart, shutdown, and overload policy | `test/wotex/runtime/subscription_test.exs`, `test/wotex/runtime/subscription_opening_test.exs` |
| Distribution | exact archives compile and execute under separate consumers without an application callback | `bin/check_reference_consumer.exs`, `bin/check_package.exs` |

The supported operation vocabulary is the TD 1.1 vocabulary declared by
WRT.01 and WRT.03. A binding profile opts into individual operations. Runtime
does not infer support from a URI scheme or transport module.

## Port and delivery shapes

Credential and transport callbacks retain their documented arities and tagged
returns. `Credentials.resolve/4` receives security declarations, the selected
Form, the caller Context, and consumer configuration. `Transport.request/3`
receives a Request, an ephemeral execution context, and binding configuration.
Subscription callbacks receive the start or stop Request and the Runtime owner.

A transport request succeeds as `{:ok, %Wotex.Runtime.Result{}}`. A subscription
receiver obtains `{:wotex_runtime, id, event}`, where `event` is a successful
value and metadata tuple, a typed Runtime error, or a transport status tuple as
specified by WRT.01. These shapes are integration contracts for binding and
consumer implementations.

## Errors, limits, and defaults

Runtime error compatibility attaches to `code`, `phase`, and optional retry
`class`. Error messages are explanatory prose. Error `details` are compatible
only where a specification names a field, including the admitted atom fields
of a structured external cause. Raw callback failure terms and credential
material are excluded.

The retained admission limits are 256 UTF-8 bytes for request identity, 64
top-level entries for Context and Result metadata, 32 binding profiles, and 128
Forms examined for one interaction. WRT-C02 defines their scope and
qualifications.

Subscription child specifications default to `restart: :transient` and a
5,000 ms shutdown value. Receiver mailboxes are unbounded unless the consumer
sets `max_queue_length`; the default overflow policy is `:drop`. Result status
defaults to `:ok`. Context metadata defaults to an empty map and its deadline
defaults to `nil`.

## Migration notes

The candidate includes the pre-release admission tightening already recorded
by WRT.01 and WRT-C02:

- malformed, non-keyword, and improper option values return typed errors;
- profile and Form scans stop at their admitted bounds;
- transport Results with substituted identity or operation are rejected;
- forged Result status and metadata are revalidated;
- registered local receiver names resolve to a live process before protocol
  establishment; and
- port exceptions and malformed returns are normalized without credential
  material.

Consumers that relied on permissive malformed input or manually constructed
Runtime structs must use the documented constructors and tagged callback
contracts.

## Qualification

This decision is a release candidate for package version `0.1.0`. It does not
promise compatibility forever, binding support for every operation, protocol
interoperability, registry availability, remote cleanup, durable delivery,
canonical state, or physical effect. Future compatibility decisions use
semantic versioning and the consumer-visible behavior above.
