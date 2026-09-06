# WTX.02: DataSchema, Form, affordance, and security values

**Status**: Implemented development contract  
**Specification version**: 1.0.0

**Owner**: `wotex`  
**Requires**: WTX.01

## Ownership

This package owns immutable, extension-preserving value wrappers for W3C WoT
DataSchema, Form, Property Affordance, Action Affordance, Event Affordance, and
security-scheme maps. The Thing Description remains the aggregate validation
boundary.

A value wrapper does not authorize an operation, resolve credentials, execute a
protocol, accept a Property observation, or prove an Action effect.

## Requirements

1. Every constructor MUST accept only a JSON-compatible map with string keys.
2. Every wrapper MUST preserve unknown extension members.
3. DataSchema, Property Affordance, Action Affordance, Event Affordance, and
   security-scheme constructors MUST validate the corresponding definition in
   the pinned TD 1.1 schema.
4. A Form MUST contain a non-empty `href`. Relative references remain values;
   base-URI resolution belongs to runtime mechanics.
5. A Form constructed without an interaction context MUST validate the common
   TD 1.1 Form terms. `for: :property`, `for: :action`, `for: :event`, and
   `for: :thing` MUST additionally constrain `op` to the exact operation set
   for that context.
6. A security scheme MUST contain a non-empty `scheme` term. Standard and
   extension scheme shapes MUST follow the pinned TD 1.1 definition.
7. Validation failures MUST use the shared structured error contract and a
   deterministic JSON Pointer-like path.
8. `to_map/1` MUST return the complete preserved map.
9. Wrappers MUST perform no I/O and start no process.

## Public values

| Module | Meaning |
|---|---|
| `Wotex.DataSchema` | TD DataSchema-shaped JSON members |
| `Wotex.Form` | binding metadata for an Interaction Affordance operation |
| `Wotex.PropertyAffordance` | Property Affordance value |
| `Wotex.ActionAffordance` | Action Affordance value |
| `Wotex.EventAffordance` | Event Affordance value |
| `Wotex.SecurityScheme` | named security-scheme definition value |

## Evidence

Constructor tests cover required members, invalid JSON keys and values,
round-trip preservation, exact DataSchema constraints, category-specific Form
operations, affordance requirements, security-scheme variants, and extension
schemes. Thing Description fixtures cover their aggregate relationship.
