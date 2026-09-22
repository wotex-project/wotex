---
id: lab-inventory
---

# Physical inventory and identification ledger

This ledger is cumulative. It records what hardware is physically available, what has been identified, and what remains unsafe to wire.

## Current home-bench cohort

| Item | Identification | Electrical domain | Candidate labs | Status |
| --- | --- | --- | --- | --- |
| Raspberry Pi 3 Model B v1.2 | confirmed by PCB silkscreen | 5 V input; 3.3 V GPIO | BLE host, LAN host, serial bridge, development gateway | identified |
| 2 x Arduino Nano 33 IoT | retail boxes confirmed; actual board/header revision to inspect | 3.3 V GPIO | BLE fixture, Wi-Fi HTTP/MQTT fixture, cross-protocol Thing | identify actual boards before soldering |
| Arduino Uno R3 | confirmed | 5 V GPIO | serial/GPIO fixture | identified |
| Adafruit PIR Motion Sensor ADA189 | confirmed by package label | verify exact supply/output before Nano connection | BLE/Wi-Fi physical motion source | identified, electrical check pending |
| Shelly Motion 2 | confirmed | mains-charged/battery consumer appliance; local Wi-Fi | HTTP/local-LAN finished-device lab | firmware/API qualification pending |
| Delock smart plug | brand/type visible; exact model unknown | mains | HTTP/MQTT/local control only if documented | UNSPECIFIED - DO NOT OPEN OR PROFILE |
| AZ-Delivery ESP8266 ESP-01S kit | confirmed from package | 3.3 V | independent Wi-Fi peer | programmer/voltage verification pending |
| Blue USB adapter | exact chipset/function unknown | unknown | possible serial/programming | UNSPECIFIED - DO NOT WIRE |
| Green USB adapter | likely ESP-style programmer, exact model unknown | unknown | possible ESP fixture | UNSPECIFIED - DO NOT WIRE |
| Plexgear USB dongle | brand visible, function unknown | USB | possible secondary radio | identify with label + lsusb |
| Small round USB dongle | unknown | USB | unknown | identify with lsusb |
| Additional bagged green boards | unknown | unknown | future sensor fixtures | UNSPECIFIED - DO NOT WIRE |
| Breadboard/electronics kit | confirmed | passive/mixed | all low-voltage fixture labs | usable after part-level checks |
| Pi fan | fitted to Pi | rated voltage/pins to verify | host cooling | pin/rating verification pending |

## Evidence required to move an item from unknown to admitted

1. Front and back photographs outside antistatic bag where safe.
2. Manufacturer/model/PCB revision or legible IC markings.
3. Datasheet or authoritative source.
4. Supply and logic voltage.
5. Pinout.
6. Multimeter verification where relevant.
7. Unique bench label.
8. Firmware revision for programmable/commercial devices.

Unknown items remain out of wiring diagrams and qualification claims.
