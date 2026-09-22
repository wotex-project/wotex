---
id: lab-catalogue
---

# WoTEx physical lab catalogue

This directory indexes repeatable physical interoperability labs across the
WoTEx protocol family.

The programme extends beyond the hardware currently on one bench. It tests
whether the same Thing semantics survive different protocol implementations,
devices, gateways, host operating systems and failure modes.

## Scope

These documents are operator runbooks and QA plans. They do not define source
implementation status, make physical-evidence claims or block completion of
repository-owned code. Package specifications and their catalogues remain the
authority for implementation status. A lab result exists only after the
runbook has been executed and its evidence recorded.

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
| BACnet | `wotex-bacnet` | Physical BACnet/IP or MS/TP device/gateway and Property/Action mapping |
| Modbus | `wotex-modbus` | Physical Modbus TCP and, where admitted, RTU gateway/device |
| OPC UA | `wotex-opcua` | Physical/server peer, browse/read/write/subscription and reconnect |
| Matter | `wotex-matter` | Commissioned physical Matter accessory/controller interaction |
| Thread | `wotex-thread` | Physical Thread topology/inspection and OpenThread management |
| LoRaWAN integration | Lab | Network-server integration without treating LoRaWAN as a WoT interaction binding |
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

## Documentation map

- [Inventory and identification ledger](inventory/README.md)
- [Current home-bench cohort](home-bench/README.md)
- [Protocol hardware matrix](protocol-matrix.md)
- [Cross-protocol QA scenarios](qa-scenarios.md)
- [Universal WoT interoperability lab](universal-wot.md)
- [Reusable lab template](TEMPLATE.md)
- [BLE](ble/README.md)
- [HTTP/SSE](http/README.md)
- [MQTT](mqtt/README.md)
- [CoAP](coap/README.md)
- [BACnet](bacnet/README.md)
- [Modbus](modbus/README.md)
- [OPC UA](opcua/README.md)
- [Matter](matter/README.md)
- [Thread](thread/README.md)
- [LoRaWAN integration](lorawan/README.md)
