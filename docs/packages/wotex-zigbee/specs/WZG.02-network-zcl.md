# WZG.02 — Network continuity, interviews and ZCL

Version: 0.8.0-target. The catalogue records implementation status separately.

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

The finite global value codec admits boolean, uint8/16/32, int8/16 and short
octet/character strings. Its exact type IDs, widths, non-values and endpoint
vectors are pinned in
[`zcl-global-r8.json`](../../../../packages/wotex-zigbee/test/support/profiles/zcl-global-r8.json),
from revision 8 sections 2.6.2.1–2, 2.6.2.5, 2.6.2.7–8 and 2.6.2.13–14.
Standard non-values decode as `:null`, retaining the original bytes in `raw`:
boolean `0xFF`, all-one unsigned values, the high-bit-only signed values and
short-string length `0xFF`. Other boolean values outside zero/one are malformed.
Failed read status, a successful null, an empty string and an unsupported type
remain distinct. Short strings retain encoded bytes; character interpretation
belongs to the selected descriptor/profile. Basic inspection applies its own
UTF-8 and 32-byte string limits.

Some attribute definitions admit the full numeric range rather than use the
type's non-value. `ZCL.decode_attributes/3` takes an explicit list of at most
32 distinct numeric attribute IDs for that adopted policy. For those IDs the
otherwise reserved encoding retains its integer value. No cluster or
manufacturer label infers this choice. Selection for a successful nonnumeric
record is refused. Truncated known values fail rather than become null.
An unsupported type has no admitted width: retain the whole remaining payload
as that record's opaque `raw` tail and infer no later record boundaries.

Read/write responses, default responses, unsolicited reports and command outcomes retain source and trust. Configure reporting/binding only under an explicit consumer request, with record-by-record success/failure. Retries are profile-sensitive; a failed write must not be silently repeated as a different command.

`Wotex.Zigbee.ZCL.Value` encodes the same finite value subset. Standard
non-values require explicit `:null`; the otherwise reserved integer requires
numeric `full_range: true`. Full-range policy excludes null and applies only
when the adopted attribute definition permits it. Values outside their width
are refused without wrapping or coercion. Short strings admit at most 64
encoded bytes; boolean input is `true`, `false` or `:null`.

`Wotex.Zigbee.ZCL.Configuration` builds inert ordinary Write Attributes,
Configure Reporting and Read Reporting Configuration requests, pinned to
revision 8 sections 2.5.3, 2.5.5, 2.5.7–10 and 2.5.12. The reviewed source
digest, command IDs, limits and response vectors are recorded in
[`zcl-configuration-r8.json`](../../../../packages/wotex-zigbee/test/support/profiles/zcl-configuration-r8.json).
Every request retains its command, byte sequence, header direction,
optional uint16 manufacturer code, canonical records and exact payload.
Admit 1–32 distinct records and at most 128 bytes including the complete
header. Refuse unknown fields, unsupported write types, malformed values,
duplicate keys and frame overflow. Do not chunk, dispatch, retry or select
undivided/no-response writes implicitly.

Write records contain `id`, `type`, `value` and optional numeric `full_range`
policy. Reporting records use a separate `report_direction`: `:send` (wire
zero) identifies reports sent by the addressed cluster; `:receive` (wire one)
identifies reports it expects. This is independent of the ZCL header
direction. Configure-send records contain type and uint16 minimum/maximum
seconds, with integer change only for admitted analog types. Discrete types
omit change. Configure-receive records contain only ID, direction and uint16
timeout seconds. Configure/read keys are `{report_direction, id}`; writes
key by ID.

Minimum zero imposes no lower reporting interval. A nonzero maximum must be
at least the minimum. Maximum `0xFFFF` disables reports. Minimum `0xFFFF`
with maximum zero requests the cluster defaults. Both special modes require
analog change zero on transmission. Other maximum-zero configurations retain
change-based reporting without periodic reporting. Signed changes retain
their bytes; revision 8 specifies that the receiver ignores their sign.
Receive timeout zero disables that reporting timeout. Binding destinations,
cluster-specific limits, authorization and power policy remain explicit
consumer responsibilities.

Response decoding preserves the exact bytes, header, record order and
duplicates. Write/configure success is exactly one zero-status byte with no
record keys. Otherwise those responses contain only failure records. A read
configuration response retains each key, status and send/receive fields;
failures omit configuration. Unconfigured analog change retains standard
null and raw bytes. Unknown types retain the whole remaining configuration
tail, after checking the fixed interval fields exist; no later record
boundaries are inferred. Malformed or oversized frames and reserved record
directions fail. Observed interval values are evidence, not an approved
configuration to retransmit.

`Configuration.observe/5` requires a complete valid request and AF context
with identical payload, current route custody and matching AF source,
remote/local endpoints and cluster. The ZCL response must match command,
sequence, manufacturer code and inverse header direction. Retain the exact
original Event, its security disposition, raw response and caller correlation.
Return outcomes in original request order. Aggregate success establishes
peer-reported success for those records. A failure-only response implies
success for omitted keys only when all response keys are expected and
distinct. Duplicate/unexpected failures leave omissions unconfirmed. Missing
read records, duplicate records and unsupported configurations remain
unconfirmed. Default Responses retain command status and leave every record
unconfirmed, including status zero. No response failure triggers a retry.

This pure matching API does not establish that the request was dispatched.
The consumer owns the finite operation deadline, fresh AF transaction/ZCL
sequence context and actual send, NCP admission and APS observations. Reused
context can match an old response. A matching record is no proof of radio
replay protection, authentication, consumer authorization or physical effect.
The profile supplies no binding, joining or autonomous transaction lifecycle.

## Sleepy endpoints and freshness

**WZG2-05.** Model expected reporting/check-in behavior and bound queued downlinks. No fixed short inactivity timeout for every end device. A quiet battery device is not immediately offline; freshness and reachability are separate. Reporting interval changes have power implications and require qualified consumer policy. Do not poll to make a dashboard appear live.

`Wotex.Zigbee.Downlinks` supplies an inert queue for one owner epoch.
The consumer explicitly admits each AF request and supplies monotonic
milliseconds and a lifetime from 1 ms to 24 hours. Host limits are 1,024
entries globally, 128 per raw IEEE peer and 131,072 payload bytes; defaults
are 128, 8 and 16,384 respectively. These limits are independent. Revalidate
complete nested requests, timestamps, FIFO tickets, pending peer/correlation
identity and all budgets after copying. Tickets never wrap. A refused
admission leaves existing entries unchanged. Expired entries occupy capacity
until explicit expiry or selection; overflow never drops an older command.

`expire/2` returns removed entries in original order at their exact deadline.
`take/5` expires entries across all peers, then removes a bounded FIFO
selection for an explicitly chosen peer. Each selected request checks current
route custody. Ready receipts retain the original request, owner epoch and
the earlier queue/custody deadline. Refused entries retain their request and
bounded reason, including route rejoin, conflict or custody expiry. Other
peers and unselected entries retain their order. Clock rewind fails; no queue
operation obtains ambient time or sends.

Retain the returned queue before attempting ready receipts through
`Wotex.Zigbee.send_queued_data/4`; WZG1-04 owns receiver deadline enforcement.
Selection grants no authorization or wakefulness and allocates no fresh
AF/ZCL tokens. Cancellation returns the removed entry. Owner rebind
invalidates every queued request and retains ticket history. Neither removal
nor expiry declares a peer offline. No automatic retry, polling, retargeting
or reporting interval change occurs. The consumer owns serialization,
expected reporting/check-in behavior and qualified battery policy; the queue
alone supplies no sleepy-device freshness model.

## Scope exclusions

Automatic OTA, Green Power proxy/sink behavior, arbitrary manufacturer codecs and concurrent multi-protocol radio scheduling are not implied. Each needs a separate explicit profile and evidence before it can be advertised. A Zigbee stack on the NCP does not turn every command into a supported public package operation.

## Acceptance

WZG2-T1: bounded join/interview and repeated joins preserve identity. WZG2-T2: same IEEE/new short address versus different IEEE/same label. WZG2-T3: forged/replayed reports preserve the stack's security disposition. WZG2-T4: stale backup, cloned coordinator and unsupported cross-chip restore fail safely. WZG2-T5: sleepy reporting and exhausted downlink queues. WZG2-T6: ZCL typed-value, manufacturer-extension, malformed frame and per-record error vectors. WZG2-T7: partial migration/key rotation and explicit recovery without false global success.

`interview_owner_test.exs` executes the software inspection subset of WZG2-T1
and selected Basic record negatives of WZG2-T6. `routes_test.exs` and
`routes_owner_test.exs` execute raw-identity/rejoin/conflict custody in WZG2-T2
and host epoch/time/sequence fencing with unchanged security disposition in
WZG2-T3. The scripted peer exercises interview adoption, source resolution and
guarded AF sends. `zcl_test.exs` executes the pinned non-value/endpoint vectors
for read responses and reports, explicit full-range policy, malformed policy,
forbidden booleans, truncation, string bounds and opaque tails in WZG2-T6.
`interview_owner_test.exs` retains numeric Basic nulls as partial evidence.
`zcl_value_test.exs` executes pinned scalar endpoints/non-values for encoding,
explicit full-range policy and refusal of overflow/coercion.
`zcl_configuration_test.exs` executes write/configure/read wire vectors,
complete-frame budgets, reporting modes, fixed-field truncation, record
ambiguity, Default Responses and source/header/request mismatch negatives.
`zcl_configuration_owner_test.exs` independently frames all three requests
and responses through the serial owner after interview and route adoption;
NCP admission, APS confirmation and unchanged-source ZCL observations remain
separate. These tests cover the finite write/reporting subset of WZG2-T6.
`downlinks_test.exs` executes the software queue subset of WZG2-T5: constructor
purity, all three budgets, correlation/ticket exhaustion, FIFO selection,
expiry, cancellation, rebind, clock rewind and custody refusal.
`zcl_configuration_owner_test.exs` executes queued write/reporting dispatch
and absolute expiry before and after I/O. This supplies no physical sleepy,
check-in, wakefulness or battery evidence.
Joining, sleepy policy, physical rejoin/source security, network continuity
binding and administration remain outstanding.
