# LoRaWAN integration lab

Status: planned cross-system lane; LoRaWAN is not currently a core WoTEx protocol package.

## Purpose

Test the common IoT topology where constrained devices reach an application through a LoRaWAN Network Server, without pretending LoRaWAN itself is a WoT interaction binding.

## Hardware class

Future selection must provide:
- operator-controlled LoRaWAN keys;
- EU868 support for the initial Swedish lab;
- operator-controlled network server or documented integration;
- no mandatory vendor cloud.

## Scenarios

- OTAA enrollment;
- uplink with one and multiple sensor channels;
- duplicate frame;
- frame-counter/replay rejection;
- one device heard by multiple gateways;
- gateway disappears/reappears;
- weak signal/SNR metadata;
- application payload codec version change;
- downlink only where the physical device safely supports it.

Normalized sensor semantics should then be compared with equivalent BLE/MQTT/HTTP Things in the universal WoT lab.
