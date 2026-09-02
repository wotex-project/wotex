# WTX.02: DataSchema, Form, affordance, and security values

**Status**: Implemented development contract  
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
3. A Form MUST contain a non-empty `href`. Relative references remain values;
   base-URI resolution belongs to runtime mechanics.
4. A security scheme MUST contain a non-empty `scheme` term.
5. A Property, Action, or Event wrapper MUST reject a value constructed for a
   different affordance category.
6. `to_map/1` MUST return the complete preserved map.
7. Wrappers MUST perform no I/O and start no process.

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
round-trip preservation, and category identity. Thing Description fixtures
cover their aggregate schema relationship.
