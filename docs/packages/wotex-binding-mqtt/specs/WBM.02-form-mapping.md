# WBM.02: WoT MQTT Form mapping

Specification `WBM.02@1.1.0`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `WBM.01` and `wotex:WTX.02`. Wotex owns TD/Form values; the binding owns
only mapping to immutable commands. No client, broker policy, Thing authority
or credential custody is transferred.

## Dated standards baseline and operation matrix

The [dated draft provenance](../provenance/mqtt-binding-draft-2026-07-01.md)
records the [WoT MQTT Binding](https://w3c.github.io/wot-binding-templates/bindings/protocols/mqtt/)
Editor's Draft dated 2026-07-01, observed 2026-09-02. This is an engineering
baseline, not a fresh maturity review or W3C conformance/endorsement claim.

| WoT operation | Packet | Form target | Constraint |
|---|---|---|---|
| `readproperty` | SUBSCRIBE | `mqv:filter` | Explicit retain true, finite read, retained delivery |
| `writeproperty` | PUBLISH | `mqv:topic` | JSON input, QoS 0–2, retain boolean |
| `invokeaction` | PUBLISH | `mqv:topic` | No Action-result protocol |
| `observeproperty` | SUBSCRIBE | `mqv:filter` | Explicit consumer lifecycle |
| `subscribeevent` | SUBSCRIBE | `mqv:filter` | No durable Event authority |
| `unobserveproperty` | UNSUBSCRIBE | `mqv:filter` | Consumer handle; no new session |
| `unsubscribeevent` | UNSUBSCRIBE | `mqv:filter` | Consumer handle; no new session |

`Mapping.default_control_packet/1` returns the listed atom or typed unsupported
operation. `Mapping.command/2` receives Runtime Request and positive byte limit
and returns Command or typed error, never I/O. The byte limit is recorded on
every command, PUBLISH, SUBSCRIBE and UNSUBSCRIBE alike, so a subscription
delivery is bounded by the same configured limit as an encoded publish. Explicit `mqv:controlPacket`
must match the operation. Query/cancel/aggregate operations fail explicitly.

## Mapping rules

1. Preserve exactly `mqv:retain`, `mqv:controlPacket`, `mqv:qos`, `mqv:topic`,
   `mqv:filter`. Do not infer topic/filter from broker href.
2. Href is broker-only mqtt/mqtts. Mixed or absent required target terms fail.
3. Filter accepts one string or nonempty list, normalized to a list. This is an
   explicit package choice for the dated draft's example/table mismatch.
4. Default QoS is 0, retain false; read requires explicit true. An explicit
   UNSUBSCRIBE QoS is validated although the command does not emit that field.
5. Missing content type means application/json; normalized JSON parameters are
   supported. No binary/custom-codec fallback is implied.
6. Runtime support does not widen the binding profile. Unsupported operation
   must not borrow a single-affordance mapping or invent correlation semantics.

## Limits, proof and compatibility

Mapping is pure: no process, clock, generated identity, credential resolution
or retry. WBM.01 owns value bounds; WBM-C03 proves the filter-cardinality and
allocation boundary. `test/wotex/binding/mqtt/mapping_test.exs` tests explicit/default
packets, target separation and rejected operations. Command/topic/QoS tests
prove value boundaries. `test/wotex/binding/mqtt/operation_inventory_test.exs`
binds positive and negative vectors for every table row, the exact Runtime
supported/unsupported cells, and the revision/digests in the checked-in source
manifest.

A newer draft changing terms/defaults/retain semantics requires reviewed spec,
package compatibility and consumer vectors. Historical provenance must not be
rewritten to imply the new text was used previously. No Binding Registry
membership follows from mapping the draft vocabulary.
