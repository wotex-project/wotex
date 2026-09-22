---
id: lab-home-bench
---

# Home bench cohort

This lab instance documents the hardware currently available on the maintainer's bench. It is one cohort under the broader physical lab programme; it does not define the full hardware requirements of WoTEx.

## Goals

Use existing hardware to close the first physical evidence gaps cheaply:

1. Pi 3 Model B v1.2 as Linux/BlueZ host.
2. Nano 33 IoT #1 as BLE/GATT Thing.
3. Nano 33 IoT #2 as HTTP/MQTT Thing.
4. ADA189 PIR and Nano IMU as physical inputs.
5. Uno R3 as deterministic USB serial fixture.
6. ESP-01S as optional independent Wi-Fi implementation.
7. Shelly Motion 2 as independently manufactured LAN device after local API qualification.
8. Run the universal WoT comparison across BLE and HTTP/MQTT.

## Non-goals

- claiming Pi 4 Nerves acceptance from Pi 3;
- claiming all protocol packages physically qualified;
- LoRaWAN;
- cloud-only integrations;
- any unidentified board.

See ../inventory/README.md and ../universal-wot.md.
