---
id: lab-modbus
---

# Modbus physical lab

Protocol contract: `wotex-modbus`.

Runbook status: planned. This does not change source implementation status.

## Hardware class

Prefer an inexpensive DIN energy meter or isolated I/O module with a documented
Modbus map. An RTU lane requires an isolated USB-to-RS-485 adapter.

## Acceptance

- holding and input-register reads;
- coil and discrete-input operations where supported;
- safe write to a fixture-only register or coil;
- exception responses;
- endian and scaling cases;
- timeout and partial or invalid-frame handling;
- RTU and TCP semantic equivalence where both are admitted;
- restart and address changes.

Never connect mains measurement hardware on an open breadboard.
