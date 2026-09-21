# WoTEx physical lab catalogue

This directory is the index for repeatable physical interoperability labs across the WoTEx protocol family.

The purpose is broader than the hardware currently on one bench. WoTEx claims transport/protocol independence at the Web of Things boundary, so the physical laboratory must test that the same Thing semantics survive across different protocol implementations, devices, gateways, host operating systems and failure modes.

## Rules

- Every lab is tied to an owning package/specification and explicit evidence class.
- A simulated/software peer and a physical peer are different evidence.
- A passing device does not prove a protocol implementation in general.
- A protocol lab must include positive, negative, lifecycle and malformed-input cases.
- Generic protocol semantics remain in their owning package. The Lab composes them; it does not fork them.
- Unknown hardware is never assigned a pinout or capability by appearance.
- No mandatory vendor cloud may be required by a reference lab.
- Private/commercial project names and customer context are never copied into these public laboratory documents.

## Lab families

| Lab | Owning package | Physical goal |
| --- | --- | --- |
| BLE / GATT | `wotex-ble` | Real BlueZ controller and physical GATT peer; discovery, read/write, notify/indicate, pairing and lifecycle |
| HTTP / SSE | `wotex-binding-http` | Real Thing over LAN, schema/content negotiation, reconnect and bounded streaming |
| MQTT | `wotex-binding-mqtt` | Real broker/device, retained state, QoS/session behaviour, LWT, reconnect and ACL isolation |
| CoAP / DTLS / OSCORE | `wotex-coap` | Physical constrained peer, Observe, retransmission, security profile and loss |
| BACnet | `wotex-bacnet` | Physical BACnet/IP or MS/TP device/gateway and property/action mapping |
| Modbus | `wotex-modbus` | Physical Modbus TCP and, where admitted, RTU gateway/device |
| OPC UA | `wotex-opcua` | Physical/server peer, browse/read/write/subscription and reconnect |
| Matter | `wotex-matter` | Commissioned physical Matter accessory/controller interaction |
| Thread | `wotex-thread` | Physical Thread topology/inspection and OpenThread management |
| Directory | `wotex-directory` | Real host/storage/discovery composition rather than a new hardware protocol |
| Continuum | `wotex-continuum` | Edge/cloud host placement, disconnect/replay and authority boundaries |
| Cross-protocol WoT | `wotex-runtime` + Lab | Same semantic Thing implemented over two or more independent protocols |

The currently owned home-bench hardware is only the first inventory cohort. Add new lab instances under `labs/<protocol-or-scenario>/` as hardware is acquired.

## Universal WoT acceptance

At least one cross-protocol lab must prove the central WoTEx promise:

```text
same Thing Model / same affordance contract
           |
   +-------+-------+----------------+
   |               |                |
  BLE             HTTP             MQTT
   |               |                |
physical peer   physical peer   physical peer
   |               |                |
   +------- Wotex Runtime ----------+
                   |
          identical consumer API
```

The acceptance question is not "can each protocol move bytes?" It is whether the consumer observes the same Property/Action/Event semantics, typed values, errors and lifecycle guarantees through the common WoT interface without protocol-specific application logic.

See `universal-wot.md` and the per-protocol lab directories.
