# WZG.03 — Coordinator and device evidence

Version: 0.2.0-target. Planned evidence contract.

## Cohort identity

Record host architecture/OS/runtime, serial adapter, coordinator chip/revision, firmware bytes/digest and host protocol revision, network parameters without keys, endpoint fingerprint, profile and scenario. Device qualification is per capability: successful pairing alone does not prove correct attribute reporting or alarm behavior.

## Required lanes

**WZG3-01.** A byte-fixture lane covers framing, checksums, finite queues, malformed replies and reordering. An independently implemented scripted NCP peer checks that the host and fixture are not simply repeating the same encoder assumptions. A live coordinator lane checks startup, negotiation, commands, reports, USB loss and restart. A physical-device lane checks a mains-powered endpoint and a sleepy sensor under WAN isolation.

**WZG3-02.** Exercise node interview, standard attributes, manufacturer-specific opaque attributes, reporting, bind/configure errors and source identity. Test NCP reset separately from new-network formation. Power interruption, duplicate replies, slow consumers and stale operation handles must not trigger unwanted network administration.

**WZG3-03.** A dedicated backup/restore cohort checks continuity of keys, counters and identity and excludes concurrent use of the original coordinator. No test rewinds a production network to manufacture success. Channel migration and cross-chip restore are separate optional cases, not inferred from same-chip reboot.

## Safety and privacy

Tests involving a safety endpoint require consumer-owned safe procedures. This protocol package cannot certify the physical detector or its standalone function. Unattended firmware updates and alarm controls do not run in ordinary CI. Redacted fixtures preserve valid framing while replacing private identifiers and exclude network/link keys.

## Release claims

WZG3-T1: every claimed callback maps to pure/fixture/native/physical evidence. WZG3-T2: at least one independent peer and exact real coordinator pass. WZG3-T3: sleepy device and reporting-soak cases are recorded without projecting battery lifetime. WZG3-T4: firmware/host drift invalidates the affected receipts. WZG3-T5: missing physical or certification evidence remains visibly unpassed. No package availability or regulator/CSA certification is claimed by a populated catalogue.
