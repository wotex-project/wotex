# BACnet physical lab

Protocol contract: `wotex-bacnet`.

Runbook status: planned. This does not change source implementation status.

## Hardware class

Prefer an inexpensive BACnet/IP thermostat, controller or open gateway. Add
MS/TP only when package evidence requires an isolated RS-485 interface.

## Acceptance

- device and object discovery;
- Property reads and safe writes;
- COV or subscription behaviour where implemented;
- BACnet error mapping;
- device restart or readdressing;
- multiple objects of the same semantic type;
- scaling and unit fidelity;
- no proprietary cloud dependency.
