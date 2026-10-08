# WZG specification index

The development package implements a bounded TI ZNP host slice and a finite
ZCL global attribute codec. Consumer profiles retain device-family semantics.

- [WZG.01 — Coordinator host](WZG.01-library-contract.md), 0.7.0-target.
- [WZG.02 — Network continuity and ZCL](WZG.02-network-zcl.md), 0.7.0-target.
- [WZG.03 — Hardware evidence](WZG.03-hardware-evidence.md), 0.2.0-target.
- [Catalogue](catalogue.yaml).

The [catalogue](catalogue.yaml) records the partial status of WZG.01–WZG.03.
The TI host API is pinned, but a distributor must configure exact NCP firmware
bytes and qualify a real coordinator and devices before claiming an installed
system. See the [completion plan](../plans/wotex-zigbee-completion.md).
