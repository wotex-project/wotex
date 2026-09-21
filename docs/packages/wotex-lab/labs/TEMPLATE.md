# Physical lab template

Use this template for every new hardware/protocol lab.

## Identity

- **Lab ID:** `<protocol-or-scenario>/<device-or-cohort>`
- **Owning package/spec:** `<package/spec ids>`
- **Evidence class:** software | simulator | interoperability | hardware | field
- **Host:** exact board/OS/runtime
- **Peer/device:** exact model/SKU/revision
- **Firmware/protocol revision:** exact value or digest
- **Status:** planned | ready | running | blocked | complete

## Purpose

State the one claim this lab is meant to test. Avoid broad claims such as “BLE works”. Prefer: “A physical GATT peripheral can be discovered, read, subscribed to and disconnected through the accepted BlueZ backend while preserving Runtime semantics.”

## Hardware bill of materials

| Qty | Part | Exact identity | Electrical domain | Required? |
| ---: | --- | --- | --- | --- |
|  |  |  |  |  |

Unknown modules stay out of the wiring diagram until identified.

## Wiring

Document every connection by source pin, destination pin, signal, nominal voltage and rationale. Mixed-voltage connections require an explicit level-shifting/divider decision.

## Software/firmware

Record:
- host OS image/kernel;
- BLE stack/broker/network service versions;
- Elixir/Erlang cohort;
- WoTEx commit;
- device firmware commit or vendor firmware;
- configuration digest.

## Network

Draw the path from physical peer to WoTEx. State which links are local, routed, encrypted and operator-controlled.

## Acceptance

- [ ] positive interaction
- [ ] malformed/unsupported input
- [ ] timeout/disconnect
- [ ] restart/recovery
- [ ] duplicate/replay where relevant
- [ ] authorization/credential boundary
- [ ] evidence record produced
- [ ] limitations documented

For each checkbox record the observable expected result and artifact/evidence path.

## Evidence manifest

At minimum:
- lab ID;
- timestamp;
- hardware/firmware revisions;
- host/runtime identity;
- WoTEx commit;
- commands run;
- raw capture/fixture digests;
- pass/fail per acceptance item;
- deviations/limitations.

## Safety

State power, RF, mains and privacy risks. Mains devices are never opened or breadboarded unless a separate electrical-safety procedure explicitly covers it.
