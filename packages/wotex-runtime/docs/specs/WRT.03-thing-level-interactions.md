# WRT.03: Thing-level meta-interaction mechanics

Specification: `WRT.03@1.0.0`. Package baseline: `wotex_runtime 0.1.0`.
Operation support is not proof of binding support or release readiness; use
the repository completion plan at `docs/plans/wotex-runtime-completion.md` for remaining evidence.
**Requires**: WRT.01, WRT.02, `wotex:WTX.02`

## Ownership

The package owns binding-neutral selection, request construction, callback
dispatch, and explicit subscription child specifications for Thing-level Forms.
These Forms describe aggregate interactions over Properties, Actions, or Events
without turning the Thing Description into canonical Thing state.

The consumer owns authorization, accepted Property values, Action lifecycle
truth, Event delivery, transaction semantics, retries, supervision, and concrete
protocol behavior.

## Standards baseline

This contract follows the top-level `forms` operation vocabulary in W3C WoT
Thing Description 1.1, Recommendation 5 December 2023:

- `readallproperties`;
- `writeallproperties`;
- `readmultipleproperties`;
- `writemultipleproperties`;
- `observeallproperties` and `unobserveallproperties`;
- `queryallactions`; and
- `subscribeallevents` and `unsubscribeallevents`.

## Requirements

1. Thing-level selection MUST inspect only top-level Forms and MUST require the
   exact requested operation on both the Form and binding profile.
2. Selection MUST preserve TD Form order and consumer profile order.
3. A top-level Form MUST be validated with the TD 1.1 Thing interaction context.
4. Read-all and query-all requests MUST carry no inferred input.
5. Read-multiple requests MUST carry a non-empty ordered list of non-empty
   Property Affordance names.
6. Write-all and write-multiple requests MUST carry a non-empty map with
   non-empty Property Affordance names. Value validation remains a separate
   interaction-data concern.
7. Aggregate observation and Event subscription APIs MUST return child
   specifications and start no process.
8. Start and stop operations MUST resolve to the same binding profile.
9. ExposedThing handlers for Thing-level operations MUST be keyed directly by
   the operation atom. Dispatch MUST reject operations absent from top-level
   Forms even when a handler exists.
10. A transport or callback result MUST NOT be described as accepted canonical
    Property truth, completed Action truth, or durable Event delivery.

## Public operations

| Operation | Runtime function |
|---|---|
| `readallproperties` | `ConsumedThing.read_all_properties/2` |
| `readmultipleproperties` | `ConsumedThing.read_multiple_properties/3` |
| `writeallproperties` | `ConsumedThing.write_all_properties/3` |
| `writemultipleproperties` | `ConsumedThing.write_multiple_properties/3` |
| `queryallactions` | `ConsumedThing.query_all_actions/2` |
| `observeallproperties` | `ConsumedThing.all_properties_observation_child_spec/3` |
| `subscribeallevents` | `ConsumedThing.all_events_subscription_child_spec/3` |
| any Thing-level operation | `ExposedThing.dispatch_thing/4` |

## Evidence

Tests cover all nine operation atoms, deterministic top-level Form selection,
invalid aggregate inputs, absent declarations, synchronous caller execution,
handler dispatch, zero-process child-spec construction, and explicit aggregate
unsubscription.

## Primary sources

- https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#form
- https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#sec-td-serialization-json
- https://www.w3.org/TR/2023/NOTE-wot-scripting-api-20231003/#the-consumedthing-interface
