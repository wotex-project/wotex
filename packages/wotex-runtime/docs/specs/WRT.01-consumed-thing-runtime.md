# WRT.01: ConsumedThing runtime mechanics

**Status**: Implemented development contract

## Ownership

The package owns immutable runtime context, binding-profile values,
deterministic Form selection, typed requests/results, credential and transport
ports, synchronous ConsumedThing operations, retry decisions, and explicit
subscription child specifications.

The consumer owns authorization, credential custody, transport instances,
durable delivery, accepted Property/Event truth, governed Action intent and
effect, clocks, and supervision.

## Requirements

1. The runtime MUST consume `Wotex.ThingDescription` through its public facade.
2. It MUST support `readproperty`, `writeproperty`, `observeproperty`,
   `unobserveproperty`, `invokeaction`, `queryaction`, `cancelaction`,
   `subscribeevent`, and `unsubscribeevent` only when a selected profile and
   Form both declare the operation.
3. Form selection MUST be deterministic over TD form order and consumer profile
   order. It MUST return typed absence instead of guessing a transport.
4. A request MUST carry a caller-supplied request id and optional absolute
   deadline. The package MUST NOT call a clock or generate identity.
5. Security declarations MUST be passed to a credential port immediately before
   execution. Credential material MUST NOT enter public request values or errors.
6. Short operations MUST run in the caller process.
7. A long-lived observation or Event subscription MUST start only through an
   explicit child specification. Zero, one, and multiple named instances MUST
   work without application-global state.
8. Retry classification MUST return a decision; this package MUST NOT sleep or
   retry a potentially non-idempotent operation by itself.
9. A successful result records protocol exchange only, never physical effect or
   canonical state.

## Evidence

Tests cover every operation category, deterministic selection, unsupported
cells, credential isolation, transport errors, retry classification, and zero,
one, and multiple subscription instances.
