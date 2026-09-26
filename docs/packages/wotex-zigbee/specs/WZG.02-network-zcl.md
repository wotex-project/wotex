# WZG.02 — Network continuity, interviews and ZCL

Version: 0.2.0-target. Planned package.

## Network identity and security

**WZG2-01.** Distinguish coordinator IEEE identity, PAN/extended PAN, channel, network-key sequence, peer link keys and security counters. Key material remains private. A 16-bit network address is a route, not durable identity. Permit-join is explicit, scoped where supported and time-bounded; closing it is observable. Install-code support and insecure enrollment fallbacks are declared capabilities, not assumed protections.

**WZG2-02.** Backup and restore must preserve the selected stack's key/counter continuity. An old backup is not safe merely because its checksum is valid. Before restore, isolate the old coordinator and follow the backend's supported counter/identity procedure. If continuity cannot be established, refuse restore and require an explicit rekey/re-enrollment recovery. Never silently reset outgoing frame counters, clone a live coordinator or promise portable restore across chipset families.

Channel migration, key rotation, network healing and leave/rejoin are separate finite administrative operations. No automatic factory reset, mass re-pair or security downgrade after transient loss. Return partial outcomes where some devices did not migrate.

## Discovery and interview

**WZG2-03.** Joining creates a candidate. Obtain bounded node, active endpoint and simple descriptors plus selected Basic attributes. Interview policy must handle unavailable/sleepy devices without an endless retry loop. A standard-required enrollment response is allowed only in the explicitly admitted commissioning scope; broad device configuration is not a side effect of inspection.

Manufacturer/model strings are untrusted evidence, not cryptographic attestation. Preserve duplicates, conflicts and unknown descriptors. A consumer performs profile/Thing admission.

## ZCL

**WZG2-04.** Preserve attribute IDs, types, manufacturer code, direction, transaction sequence, status and the exact distinction among value, null, unsupported and malformed. Bound collection lengths and nesting. Support only explicitly catalogued cluster operations. Manufacturer-specific attributes remain opaque unless a consumer adapter supplies semantics. No generic automatic TD generation from a cluster name.

Read/write responses, default responses, unsolicited reports and command outcomes retain source and trust. Configure reporting/binding only under an explicit consumer request, with record-by-record success/failure. Retries are profile-sensitive; a failed write must not be silently repeated as a different command.

## Sleepy endpoints and freshness

**WZG2-05.** Model expected reporting/check-in behavior and bound queued downlinks. No fixed short inactivity timeout for every end device. A quiet battery device is not immediately offline; freshness and reachability are separate. Reporting interval changes have power implications and require qualified consumer policy. Do not poll to make a dashboard appear live.

## Scope exclusions

Automatic OTA, Green Power proxy/sink behavior, arbitrary manufacturer codecs and concurrent multi-protocol radio scheduling are not implied. Each needs a separate explicit profile and evidence before it can be advertised. A Zigbee stack on the NCP does not turn every command into a supported public package operation.

## Acceptance

WZG2-T1: bounded join/interview and repeated joins preserve identity. WZG2-T2: same IEEE/new short address versus different IEEE/same label. WZG2-T3: forged/replayed reports preserve the stack's security disposition. WZG2-T4: stale backup, cloned coordinator and unsupported cross-chip restore fail safely. WZG2-T5: sleepy reporting and exhausted downlink queues. WZG2-T6: ZCL typed-value, manufacturer-extension, malformed frame and per-record error vectors. WZG2-T7: partial migration/key rotation and explicit recovery without false global success.
