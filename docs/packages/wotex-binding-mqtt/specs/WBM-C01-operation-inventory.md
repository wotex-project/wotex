# WBM-C01 operation inventory

This inventory binds the seven-operation package profile to the W3C MQTT
binding repository snapshot recorded in
`docs/packages/wotex-binding-mqtt/provenance/mqtt-binding-source-manifest.json`.
The snapshot is an Editor's Draft input, not a W3C conformance or
registry-membership claim.

| WoT operation | MQTT packet | Exact Form target | Defaults and constraint |
| --- | --- | --- | --- |
| `readproperty` | SUBSCRIBE | `mqv:filter` | `mqv:qos=0`; explicit `mqv:retain=true` required |
| `writeproperty` | PUBLISH | `mqv:topic` | `mqv:qos=0`; `mqv:retain=false` |
| `invokeaction` | PUBLISH | `mqv:topic` | `mqv:qos=0`; `mqv:retain=false`; no result protocol |
| `observeproperty` | SUBSCRIBE | `mqv:filter` | `mqv:qos=0`; `mqv:retain=false` |
| `subscribeevent` | SUBSCRIBE | `mqv:filter` | `mqv:qos=0`; `mqv:retain=false` |
| `unobserveproperty` | UNSUBSCRIBE | `mqv:filter` | no command QoS; `mqv:retain=false` |
| `unsubscribeevent` | UNSUBSCRIBE | `mqv:filter` | no command QoS; `mqv:retain=false` |

All rows require a broker-only `mqtt` or `mqtts` href and JSON content. An
explicit `mqv:controlPacket` must equal the row's packet. Only the exact
`mqv:retain`, `mqv:controlPacket`, `mqv:qos`, `mqv:topic`, and `mqv:filter`
keys affect mapping; similarly named unprefixed extension keys do not.

The remaining TD 1.1 Runtime operations are unsupported cells:
`queryaction`, `cancelaction`, `readallproperties`, `writeallproperties`,
`readmultipleproperties`, `writemultipleproperties`, `observeallproperties`,
`unobserveallproperties`, `queryallactions`, `subscribeallevents`, and
`unsubscribeallevents`. They return `unsupported_operation`; the binding does
not borrow a single-affordance mapping for aggregate or Action lifecycle work.

`test/wotex/binding/mqtt/operation_inventory_test.exs` executes every positive
row with default and explicit vocabulary, every packet/target mismatch, exact
prefix handling, the exact Runtime profile set, and all unsupported cells. The
source manifest is recorded provenance; no test reads it.
