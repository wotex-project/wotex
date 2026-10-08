# WZG.02 — Network continuity, interviews and ZCL

Version: 0.5.0-target. The catalogue records implementation status separately.

## Network identity and security

**WZG2-01.** Distinguish coordinator IEEE identity, PAN/extended PAN, channel, network-key sequence, peer link keys and security counters. Key material remains private. A 16-bit network address is a route, not durable identity. Permit-join is explicit, scoped where supported and time-bounded; closing it is observable. Install-code support and insecure enrollment fallbacks are declared capabilities, not assumed protections.

**WZG2-02.** Backup and restore must preserve the selected stack's key/counter continuity. An old backup is not safe merely because its checksum is valid. Before restore, isolate the old coordinator and follow the backend's supported counter/identity procedure. If continuity cannot be established, refuse restore and require an explicit rekey/re-enrollment recovery. Never silently reset outgoing frame counters, clone a live coordinator or promise portable restore across chipset families.

Channel migration, key rotation, network healing and leave/rejoin are separate finite administrative operations. No automatic factory reset, mass re-pair or security downgrade after transient loss. Return partial outcomes where some devices did not migrate.

## Discovery and interview

**WZG2-03.** Joining creates a candidate. Obtain bounded node, active endpoint and simple descriptors plus selected Basic attributes. Interview policy must handle unavailable/sleepy devices without an endless retry loop. A standard-required enrollment response is allowed only in the explicitly admitted commissioning scope; broad device configuration is not a side effect of inspection.

Manufacturer/model strings are untrusted evidence, not cryptographic attestation. Preserve duplicates, conflicts and unknown descriptors. A consumer performs profile/Thing admission.

The initial software query profile supplies IEEE identity, node, active endpoint
and simple descriptor requests and typed responses. Immediate SRSP admission
and later ZDO status remain distinct. The finite IEEE and node layouts are
owned by WZG1-04; successful decoding alone does not establish route custody,
cryptographic identity or Thing admission.

The owner-backed interview first matches the expected raw IEEE and candidate
route, then obtains node, active endpoint and simple descriptors. Descriptor
responses must match both source and address of interest; successful simple
descriptors also match the requested endpoint. The advertised list is bounded
by `max_endpoints` (default 16, maximum 77), including duplicates. Its original
order and duplicates remain evidence; each valid distinct endpoint is queried
once. Invalid endpoints, descriptor failures and unknown clusters/profiles are
preserved. Too many advertised endpoints return a partial result without
silently truncating the interview. No step retries automatically.

Basic reads apply only to profile `0x0104` endpoints with Basic input cluster
`0x0000`. The consumer selects from ZCLVersion, ManufacturerName,
ModelIdentifier and ClusterRevision; all four are selected by default.
Matching requires the route, remote/local endpoints, cluster, client-facing
direction, global Read Attributes Response, absent manufacturer extension and
the allocated ZCL sequence. APS confirmation is a separate required observation.
Record errors, duplicate IDs, missing/extra IDs, wrong types, nulls and invalid
or oversized strings remain partial evidence. Duplicate, unrelated, malformed
and unsolicited indications stay in the ordinary bounded event queue with
its existing drop counter. The NCP security flag is retained at its original
trust level. A complete inspection does not perform consumer profile admission.

After consumer review, `Wotex.Zigbee.Routes.adopt/4` admits a complete matching
interview into a finite raw-IEEE ledger. Manufacturer/model strings never key
the ledger. A newer owner observation moves the same identity to its new
route; an older result cannot restore the prior route. Different identities
claiming one route remain conflicted, even if one claim cannot fit in the
table. Retain the returned conflict table before further traffic. Removing a
claim does not grant authority to the remaining conflicted claim.

The consumer supplies monotonic time and a lifetime from the identity
observation, at most 24 hours. Adopting an old result does not refresh that
observation. `Routes.resolve/3` fences source resolution by epoch, expiry,
observation time and owner sequence while preserving the exact original
Event. `Wotex.Zigbee.send_routed_data/4` checks the current supplied ledger at
the receiver and limits the command deadline to custody expiry. A replacement
owner requires explicit rebind and a fresh complete interview. Retained
records, host ordering and IEEE matches do not authenticate a peer, establish
radio replay protection or turn custody expiry into an offline declaration.

## ZCL

**WZG2-04.** Preserve attribute IDs, types, manufacturer code, direction, transaction sequence, status and the exact distinction among value, null, unsupported and malformed. Bound collection lengths and nesting. Support only explicitly catalogued cluster operations. Manufacturer-specific attributes remain opaque unless a consumer adapter supplies semantics. No generic automatic TD generation from a cluster name.

The selected Basic client read profile is pinned to
[ZCL document 07-5123 revision 8, December 2019](https://csa-iot.org/wp-content/uploads/2022/01/07-5123-08-Zigbee-Cluster-Library-1.pdf),
sections 2.4, 2.5.1–2, 2.6.2 and 3.2. Its reviewed source digest, attribute IDs,
types and string limits are recorded in
[`zcl-basic-r8.json`](../../../../packages/wotex-zigbee/test/support/profiles/zcl-basic-r8.json).
This is a finite Read Attributes profile. It does not implement all Basic
attributes/commands or establish complete ZCL, Zigbee or cluster conformance.

Read/write responses, default responses, unsolicited reports and command outcomes retain source and trust. Configure reporting/binding only under an explicit consumer request, with record-by-record success/failure. Retries are profile-sensitive; a failed write must not be silently repeated as a different command.

## Sleepy endpoints and freshness

**WZG2-05.** Model expected reporting/check-in behavior and bound queued downlinks. No fixed short inactivity timeout for every end device. A quiet battery device is not immediately offline; freshness and reachability are separate. Reporting interval changes have power implications and require qualified consumer policy. Do not poll to make a dashboard appear live.

## Scope exclusions

Automatic OTA, Green Power proxy/sink behavior, arbitrary manufacturer codecs and concurrent multi-protocol radio scheduling are not implied. Each needs a separate explicit profile and evidence before it can be advertised. A Zigbee stack on the NCP does not turn every command into a supported public package operation.

## Acceptance

WZG2-T1: bounded join/interview and repeated joins preserve identity. WZG2-T2: same IEEE/new short address versus different IEEE/same label. WZG2-T3: forged/replayed reports preserve the stack's security disposition. WZG2-T4: stale backup, cloned coordinator and unsupported cross-chip restore fail safely. WZG2-T5: sleepy reporting and exhausted downlink queues. WZG2-T6: ZCL typed-value, manufacturer-extension, malformed frame and per-record error vectors. WZG2-T7: partial migration/key rotation and explicit recovery without false global success.

`interview_owner_test.exs` executes the software inspection subset of WZG2-T1
and selected Basic record negatives of WZG2-T6. `routes_test.exs` and
`routes_owner_test.exs` execute raw-identity/rejoin/conflict custody in WZG2-T2
and host epoch/time/sequence fencing with unchanged security disposition in
WZG2-T3. The scripted peer exercises interview adoption, source resolution and
guarded AF sends. Joining, sleepy policy, physical rejoin/source security,
network continuity and administration remain outstanding.
