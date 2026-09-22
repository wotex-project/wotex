# WoTEx Lab hardware bench

Status: operator build and physical-evidence guide. This document does not turn
photographed hardware into qualified evidence.

## Lab catalogue

This page covers the current home-bench cohort. The complete physical programme
is indexed in the [physical lab catalogue](labs/README.md), including the
per-protocol runbooks, reusable template, cross-protocol QA scenarios and
universal WoT acceptance lab.

## Purpose

This bench covers BLE/GATT, Wi-Fi/IP Things, GPIO and serial sensor peers,
protocol discovery, Runtime interactions and later Nerves evidence. It remains
separate from product-specific hardware benches.

## Inventory from the 2026-09-21 photographs

### Confirmed from readable markings

| Qty | Hardware | Bench role |
| ---: | --- | --- |
| 1 | Raspberry Pi 3 Model B v1.2 (© Raspberry Pi 2015) in ventilated case with fitted fan | Linux/BlueZ gateway, WoTEx host and serial/GPIO bridge. The PCB revision is confirmed; the fan voltage and occupied GPIO power pins still require verification. |
| 2 | Arduino Nano 33 IoT retail units | Open BLE/Wi-Fi Things, IMU source, secure-element experiments, controlled GATT peers. |
| 1 | Arduino Uno R3 | 5 V GPIO/serial fixture and deterministic sensor simulator. |
| 1 | Shelly Motion 2 | Finished Wi-Fi motion Thing for local-LAN interoperability. |
| 1 | AZ-Delivery ESP8266 ESP-01S kit/box | Small open Wi-Fi peer or UART-to-Wi-Fi fixture. |
| 1 | Breadboard/electronics kit | Breadboards, jumpers, resistors, LEDs, buttons and basic prototyping parts. |
| 1 | Blue USB serial/programming adapter | UART/programming after chipset and logic voltage are verified. |
| 1 | Green ESP-01/serial-style programming adapter | Candidate ESP8266 programmer; exact marking/voltage must be verified. |
| 1 | Delock mains smart plug | Candidate finished IP Thing; exact model/local protocol must be read from its label. |
| 1 | Adafruit PIR Motion Sensor ADA189 | Confirmed from its package label. Check authoritative electrical characteristics before Nano wiring. |
| several | Additional sensor modules in antistatic bags | Exact part numbers and pinouts remain unverified. Do not wire them by appearance. |
| several | USB cables, power adapters, jumper/header parts | Bench support. |

### Visible but not safely identifiable

A small green ribbon-cable board, multiple bagged modules, a black clamp/fixture, a black USB power device and other adapters are visible. They are intentionally not assigned a model or pinout. Record close-up front/back photographs and readable markings before using them in a wiring recipe.

## Electrical domains

- Raspberry Pi GPIO: 3.3 V logic.
- Nano 33 IoT: 3.3 V board; treat GPIO as 3.3 V only.
- ESP8266 ESP-01S: 3.3 V.
- Uno R3: 5 V logic.
- Never connect an Uno 5 V output directly to Pi, Nano 33 IoT or ESP8266 GPIO.
- Never infer USB-UART logic voltage from connector shape or PCB colour.

## Pi 3 role

A Pi 5 is not required for the first generic hardware bench. Pi 3 has Ethernet, Wi-Fi, USB and BLE and is suitable for a Raspberry Pi OS Linux/BlueZ host.

The current accepted `wotex-lab` Nerves reference host is Raspberry Pi 4. Therefore a Pi 3 Linux run is useful hardware/interoperability evidence but is not evidence for the existing Pi 4 Nerves target. Add a Pi 3 Nerves target only if the project intentionally admits it.

The Pi should own BlueZ, the `wotex-ble` native host/guardian, Lab scenarios, USB serial fixtures and host-selected local HTTP/MQTT peers.

## Bench build

### Inventory before soldering

For every board photograph front/back, record silkscreen/model/revision and assign a bench label before attaching headers.

### Nano 33 IoT headers

The photographed boxes say **with headers**. Open them first: if the headers are already factory-soldered, do not rework them.

If the actual boards are headerless:
1. Disconnect USB/power.
2. Put two straight 2.54 mm header rows into a breadboard to hold them square.
3. Place the Nano over them in the intended orientation.
4. Tack one corner on each row.
5. Check board flatness and perpendicular headers.
6. Tack opposite corners, re-check, then solder remaining pins.
7. Inspect every joint for bridges.
8. With power removed, continuity-check suspicious adjacent pins.
9. Power by USB alone and run a basic board test before attaching sensors.

### Nano #1: open BLE Thing

Use the onboard IMU first; no external sensor is needed.

```text
Nano 33 IoT IMU
 -> small custom GATT service
 -> Pi 3 BlueZ
 -> wotex-ble
 -> Wotex Runtime
 -> Lab observation/evidence
```

Expose explicit firmware/protocol revision, one read-only motion value and one notification characteristic.

### Nano #2: open Wi-Fi Thing

Use it as an independent HTTP or MQTT Thing. Keep this first experiment separate from the BLE transport path so the Lab proves two physical transports.

### Uno R3

Use USB serial initially. Generate deterministic button/potentiometer/PIR frames for timing, malformed-input and replay tests. Identify any external sensor exactly before wiring it.

### ESP-01S

Optional. Verify programmer supply and logic are 3.3 V before insertion. Use later as a tiny non-Arduino Wi-Fi peer.

### Shelly Motion 2

Use an isolated test SSID/VLAN. Verify its installed firmware and exact local API before adding an adapter. Cloud enrollment is not required for the local experiment.

### Delock plug

Do not integrate or modify it until exact model/local protocol are recorded. Mains hardware is not a breadboard target.

## Pi 3 setup

1. Read PCB silkscreen and record exact model/revision.
2. Use known-good microSD and adequate 5 V supply.
3. Install current supported 64-bit Raspberry Pi OS Lite.
4. Prefer Ethernet for management.
5. Configure SSH keys and unique hostname.
6. Install the repository-required Erlang/OTP, Elixir and native build toolchain.
7. Verify Bluetooth/BlueZ before WoTEx.
8. Build `wotex-ble` using its pinned native build task.
9. Run software/virtual BLE evidence first.
10. Select physical hardware lanes explicitly; no physical scan runs by default.

## First physical acceptance sequence

1. Pi 3 + Nano #1: BLE read/notification.
2. Pi 3 + Nano #2: Wi-Fi HTTP/MQTT property.
3. Pi 3 + Uno: USB serial deterministic sensor.
4. Pi 3 + Shelly Motion 2: finished local-LAN device.
5. Optional ESP-01S: independent Wi-Fi peer.

Record hardware revision, firmware revision/digest, wiring, power, host OS/kernel/BlueZ, WoTEx commit, commands, capture identity, result and limitations.

## Missing for the wider Lab programme

The current bench is sufficient for the first BLE/Wi-Fi/serial experiments. It does not visibly contain the Pi 4 required by the current Lab Nerves target, protocol-specific Matter/Thread/BACnet/Modbus/OPC UA devices, or LoRaWAN hardware. None is required to start.

A multimeter is required before mixed-voltage wiring. A logic analyzer is strongly useful for serial/SPI/I2C evidence.

## Still required from the operator for pin-perfect appendices

Capture the fitted Pi fan rating and occupied power pins; the front and back of
each Nano after opening; markings on every bagged module; both sides of the blue
and green USB adapters; the Delock model label; power-supply ratings; and the
available soldering, measurement and programming equipment.
