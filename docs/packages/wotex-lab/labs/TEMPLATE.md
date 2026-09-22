# Physical lab template

Use this template for each new hardware or protocol lab.

## Identity

- **Lab ID:** `<protocol-or-scenario>/<device-or-cohort>`
- **Owning package/specification:** `<package/specification identifiers>`
- **Evidence class:** software | simulator | interoperability | hardware | field
- **Host:** exact board, operating system and runtime
- **Peer/device:** exact model, SKU and revision
- **Firmware/protocol revision:** exact value or digest
- **Plan state:** draft | ready
- **Run result:** not-run | unavailable | skipped | failed | passed

## Purpose

State the one claim the lab tests. Avoid broad claims such as “BLE works”. A
bounded claim is: “A physical GATT peripheral can be discovered, read,
subscribed to and disconnected through the accepted BlueZ backend while
preserving Runtime semantics.”

## Hardware bill of materials

| Qty | Part | Exact identity | Electrical domain | Required? |
| ---: | --- | --- | --- | --- |
|  |  |  |  |  |

Unknown modules stay out of the wiring diagram until identified.

## Wiring

Document each connection by source pin, destination pin, signal, nominal
voltage and rationale. Mixed-voltage connections require an explicit
level-shifting or divider decision.

## Software and firmware

Record:

- host operating-system image and kernel;
- BLE stack, broker or network-service versions;
- Elixir and Erlang/OTP cohort;
- WoTEx commit;
- device firmware commit or vendor firmware revision;
- configuration digest.

## Network

Draw the path from the physical peer to WoTEx. State which links are local,
routed, encrypted and operator-controlled.

## Acceptance

- [ ] positive interaction
- [ ] malformed or unsupported input
- [ ] timeout or disconnect
- [ ] restart and recovery
- [ ] duplicate or replay where relevant
- [ ] authorization and credential boundary
- [ ] evidence record produced
- [ ] limitations documented

Record the expected observable result and artifact path for each item.

## Evidence manifest

Record at least:

- lab ID;
- timestamp;
- hardware and firmware revisions;
- host and runtime identity;
- WoTEx commit;
- commands run;
- raw capture and fixture digests;
- result for each acceptance item;
- deviations and limitations.

## Safety

State power, RF, mains and privacy risks. Never open or breadboard mains devices
unless a separate electrical-safety procedure explicitly covers the work.
