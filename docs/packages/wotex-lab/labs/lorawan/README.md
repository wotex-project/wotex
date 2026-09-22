# LoRaWAN integration lab

Runbook status: planned cross-system lane. LoRaWAN is not a core WoTEx protocol
package, and this runbook does not change source implementation status.

## Purpose

Test the topology in which constrained devices reach an application through a
LoRaWAN Network Server without treating LoRaWAN as a WoT interaction binding.

## Hardware class

Future hardware must provide:

- operator-controlled LoRaWAN keys;
- a regional band selected for the operator's location and regulatory domain;
- an operator-controlled network server or documented integration;
- no mandatory vendor cloud.

## Scenarios

- OTAA enrollment;
- uplink with one or multiple sensor channels;
- duplicate frame;
- frame-counter or replay rejection;
- one device heard by multiple gateways;
- gateway disappearance and return;
- weak-signal and SNR metadata;
- application-payload codec revision change;
- downlink only where the physical device supports it safely.

Compare normalized sensor semantics with equivalent BLE, MQTT and HTTP Things
in the universal WoT lab.
