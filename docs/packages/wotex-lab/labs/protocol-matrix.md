# Physical protocol lab matrix

This matrix defines the hardware-facing test programme for every protocol family currently represented in WoTEx. It is a planning/evidence map, not a claim that every lane already has hardware.

| Protocol / package | Minimum physical lab | Required behaviours | Useful hardware classes | Current home-bench status |
| --- | --- | --- | --- | --- |
| BLE / `wotex-ble` | Linux BlueZ host + physical GATT peripheral | discover, connect, read, write, notify/indicate, lifecycle, pairing policy | Nano 33 IoT, commercial BLE sensor | **available now** |
| HTTP/SSE / `wotex-binding-http` | LAN Thing + host consumer | read/write/action, content type, auth, timeout, SSE/reconnect | Nano 33 IoT, Shelly local API | **available now** |
| MQTT / `wotex-binding-mqtt` | physical publisher/subscriber + broker | retained state, QoS, LWT, reconnect, ACL/session behaviour | Nano 33 IoT, ESP-01S, Mosquitto | **available now** |
| CoAP / `wotex-coap` | constrained physical peer | GET/PUT/POST, Observe, retransmission, DTLS/OSCORE profile | ESP32/nRF class board or commercial CoAP node | purchase later |
| BACnet / `wotex-bacnet` | physical BACnet/IP or MS/TP device | discovery, property read/write, COV, object identity | thermostat/controller + optional RS-485 gateway | purchase later |
| Modbus / `wotex-modbus` | physical Modbus TCP/RTU device | register read/write, coils, exception responses, endian/scaling | energy meter, PLC/I/O module, USB-RS485 | purchase later |
| OPC UA / `wotex-opcua` | physical or independent industrial server/device | browse, read/write, subscriptions, sessions/security | PLC/gateway/industrial simulator appliance | purchase later |
| Matter / `wotex-matter` | commissioned physical accessory | commissioning boundary, read/write/commands/events, fabric lifecycle | smart plug/light/sensor | purchase later |
| Thread / `wotex-thread` | physical Thread topology | neighbor/route inspection, OpenThread management, partition/rejoin | OTBR-compatible radio + Thread end device | purchase later |
| Directory / `wotex-directory` | physical hosts using real network/storage | registration/discovery/update/expiry under host auth | Pi + independent client | available now |
| Continuum / `wotex-continuum` | at least two physical hosts or edge/cloud placements | disconnect, replay, stale data, authority boundaries | Pi + laptop/server | available now |
| Runtime cross-protocol | same semantic Thing over 2+ protocols | identical consumer semantics through different bindings | Nano BLE + Nano HTTP/MQTT | **available now** |

## Hardware-acquisition rule

Do not buy a protocol appliance until:
1. its package has an accepted physical evidence obligation;
2. the hardware is not cloud-locked;
3. the protocol can be exercised without a proprietary SaaS dependency;
4. the device has enough documented functionality to cover the package's important operations;
5. the expected evidence cannot already be produced with existing hardware.

## Industrial QA-oriented scenarios

The physical labs should deliberately include scenarios common to large IoT platforms without coupling the docs to any company:

- device onboarding from first packet through capability mapping;
- one physical device exposing multiple sensor channels;
- gateway versus end-device identity;
- intermittent/offline gateways;
- duplicate uplinks and replay;
- stale retained state;
- reconnect/session recovery;
- unit/scaling differences;
- malformed payloads;
- device profile/version changes;
- low battery and weak signal;
- source/gateway metadata preservation;
- alarm/event transitions;
- mixed fleets where the same semantic sensor arrives through LoRaWAN, MQTT, HTTP or BLE gateways;
- headless API consumers independent of vendor UI.

These scenarios should feed the same evidence vocabulary as the package-specific physical lanes.
