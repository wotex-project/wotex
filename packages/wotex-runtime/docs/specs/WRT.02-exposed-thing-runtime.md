# WRT.02: ExposedThing callback mechanics

**Status**: Implemented development contract

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
