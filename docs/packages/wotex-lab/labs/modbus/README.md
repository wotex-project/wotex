# Modbus physical lab

**Owner:** `wotex-modbus`

Status: planned physical lane.

## Hardware class

Prefer an inexpensive DIN energy meter or isolated I/O module with documented Modbus map. For RTU, use an isolated USB-RS485 adapter.

## Acceptance

- holding/input register reads;
- coil/discrete-input operations where supported;
- safe write to a fixture-only register/coil;
- exception responses;
- endian/scaling cases;
- timeout and partial/invalid frame handling;
- RTU/TCP semantic equivalence where both are admitted;
- restart and address changes.

Never connect mains measurement hardware on an open breadboard.
