# W3C MQTT binding draft provenance

## Observation

- Observed: 2026-09-02
- Source: [Web of Things MQTT Binding](https://w3c.github.io/wot-binding-templates/bindings/protocols/mqtt/)
- Source status shown: W3C Editor's Draft, 01 July 2026
- Document status: work in progress
- Repository snapshot and file digests:
  `docs/packages/wotex-binding-mqtt/provenance/mqtt-binding-source-manifest.json`

This package implements a conservative executable subset of that dated draft.
It does not claim W3C conformance or imply W3C endorsement.

## Terms preserved

The Form mapping reads these exact compact terms:

| Term | Package use |
| --- | --- |
| `mqv:retain` | PUBLISH retain setting and retained Property-read semantics |
| `mqv:controlPacket` | explicit `publish`, `subscribe`, or `unsubscribe` mapping |
| `mqv:qos` | normalized QoS level zero through two |
| `mqv:topic` | PUBLISH Topic Name |
| `mqv:filter` | SUBSCRIBE or UNSUBSCRIBE Topic Filter list |

The draft's URL section limits the scheme to `mqtt` or `mqtts` and separates
the broker address from Topic Names and Topic Filters. The package therefore
rejects topic paths, queries, and fragments in broker href values.

## Default mappings implemented

The dated draft maps Property reads and observations, plus Event subscriptions,
to SUBSCRIBE; Property writes and Action invocations to PUBLISH; and stop
operations to UNSUBSCRIBE. The package supports:

| WoT operation | Default packet |
| --- | --- |
| `readproperty` | `subscribe` |
| `writeproperty` | `publish` |
| `observeproperty` | `subscribe` |
| `unobserveproperty` | `unsubscribe` |
| `invokeaction` | `publish` |
| `subscribeevent` | `subscribe` |
| `unsubscribeevent` | `unsubscribe` |

An explicit `mqv:controlPacket` is accepted only when it matches this supported
mapping. Operations outside this table are outside the package profile.

The draft explains that MQTT can read a Property through retained-message
behavior; without it, the Property can only be observed. Accordingly,
`readproperty` requires `mqv:retain` to be true, a finite client read, and a
retained delivery.

## Draft-sensitive choices

The draft examples use `mqv:filter` as a string while its vocabulary table
describes Topic Filters as a collection. The package accepts either one string
or a non-empty list and normalizes both to a list.

The draft is expected to evolve. Any change to its status, vocabulary, or
mapping must update this record, tests, and the package contracts together.
