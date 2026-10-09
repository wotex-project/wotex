# WMA.09 Exposed Matter bridge/server target

## Status

Version: 0.17.0-target.

Target contract. The package catalogue records implementation status separately.
Existing WMA.01-WMA.08 remain controller-side and MUST NOT be cited as
bridge/server evidence.

## Purpose

Add an explicitly separate Matter server/accessory role capable of exposing consumer-owned Things as Matter endpoints, including bridged non-Matter devices.

## Required boundary

The native connectedhomeip host owns generic:
- Matter server lifecycle;
- fabric/commissioning state;
- bridge root/aggregator semantics;
- endpoint allocation and durable endpoint identity;
- Device Type/cluster declarations;
- inbound attribute reads/writes/commands;
- event/attribute reporting;
- commissioning windows and ACL enforcement;
- restart/recovery.

The consumer owns:
- which Things are exported;
- semantic mapping from consumer domain to Matter Device Types;
- authorization beyond Matter fabric admission;
- physical Action-effect truth;
- safety policy.

## Runtime integration

Inbound Matter requests MUST pass through an authenticated/authorized consumer boundary before ExposedThing dispatch. A successful Matter command is not automatically a physical-effect observation.

Endpoint identity MUST remain stable across host restart and must not silently rebind to another Thing.

The native bridge store MUST have a separate format and immutable consumer-owned
bridge identity, model digest, vendor and product identity. It MUST NOT select a
controller node, generate a controller authority or accept a controller store.
Endpoint allocation and removal MUST commit durably before acknowledgment. A
removed endpoint MUST remain retired across restart; re-adding the same Thing
allocates a new endpoint. An existing live Thing MUST NOT change Device Type
under its current endpoint. The finite profile admits sixteen live endpoints
and allocates IDs 3 through 65534 without wrapping.

SDK fabric values and endpoint custody MUST share the bridge's locked atomic
store. An incomplete commit or incompatible store MUST prevent startup; a
failed durable write MUST terminate further store service and cause the server
owner to stop. A compatible local reopen does not establish safe import of an
older copy, anti-rollback protection or an atomic multi-call SDK fabric change.

The server process MUST explicitly own SDK memory/platform initialization,
credentials, the generated data-model provider, the network driver, interface
and service port. Missing credentials or a model/vendor/product identity
mismatch MUST prevent server initialization. The disabled model-generation
endpoint MUST NOT be served. Each native process has one SDK server lifetime.
Normal shutdown MUST stop the event loop before releasing SDK resources and
retire global references to borrowed providers. A partial SDK initialization
or poisoned store MUST terminate the native process before it can serve cached
state; the outer owner MUST reap and classify that process without retrying a
mutation.

Dynamic SDK slots MUST remain distinct from durable endpoint IDs. Restore MUST
receive one explicit consumer configuration for every live Thing and refuse
missing, duplicate or incompatible Device Types before registering children.
The selected temperature capabilities MUST remain fixed for the registered
lifetime. Unknown bounds and unavailable measurements MUST retain their null
meaning; a restart MUST NOT promote a previous measurement to current truth.
An observation MUST match both the Thing identity and its current endpoint.
Invalid observations MUST preserve previously approved state and reachability.
Permanent removal MUST retire SDK cluster registrations and endpoint-scoped
group/attribute custody. Normal shutdown MUST preserve durable group custody.

The native consumer handoff MUST retain a slot for every unconsumed request
context, including a staged result or expired request. It MUST admit at most
sixteen contexts, bind each ticket to one explicit process generation and a
non-reused request ID, and preserve one absolute deadline no later than 500 ms
after admission. Clock regression MUST be refused. Neither queue admission nor
a staged result grants authorization or establishes a physical effect. A
result consumed at or after expiry MUST become a timeout. Closure MUST refuse
new requests and retire all unconsumed results; the native owner MUST consume
their contexts before releasing SDK resources. Unconsumed handoffs at server
shutdown MUST terminate the native process before SDK cleanup.

The threaded handoff owner MUST serialize custody operations and sample its
explicit elapsed-time clock inside that same lock. A synchronous SDK wait
MUST release the custody lock while blocked, allowing input resolution and
closure without acquiring the SDK stack lock. Every wake MUST recheck the
original absolute deadline; a spurious wake MUST NOT extend it. Serialized
SDK cleanup that closes custody MUST also wake its waiters. The native owner
MUST close admission, drain contexts and join all callers before destroying
the threaded owner or releasing its borrowed custody and clock. Destruction
with unconsumed custody MUST terminate the process. These mechanics do not
establish consumer authorization or schedule SDK completion work.

Consumer result input MUST use LF-delimited frames of at most 512 bytes,
including LF. Each result frame MUST be one JSON object with exactly six scalar
fields: unsigned integer `v: 1`, `backend: "matter-bridge"`, `type: "result"`,
`generation` as the expected 16-byte generation encoded as 32 lowercase
hexadecimal characters, `id` as the canonical decimal string of a nonzero
uint64, and `outcome` as `"completed"`, `"denied"`, `"failed"` or `"unknown"`.
Duplicate, missing or extra
fields, nested values, wrong types, foreign roles/generations, trailing JSON,
NUL, CR and oversized input MUST be refused. Decode failure MUST preserve the
caller output. A duplicate staged result or consumed/unknown ID MUST NOT revive
custody or release credit. A late result MUST NOT extend the original deadline.

The serialized result reader MUST retain only a bounded partial frame and use
an explicit bounded notification port after custody unlocks. Notification MUST
NOT acquire the SDK stack lock; asynchronous completion owners MUST coalesce
late-result notifications within the sixteen-context bound. EOF, partial EOF,
malformed input, clock failure, allocation failure, notification refusal, read
failure and caller cancellation MUST close admission and wake pending waits
before SDK cleanup. Cancellation MUST NOT depend on closing a descriptor under
a read. The caller MUST join the reader before closing its borrowed descriptor
or releasing custody. Result correlation grants no consumer policy authority.

Outbound request delivery MUST use an explicitly started, exclusively owned
writer, separate from the SDK callback and input reader. SDK output admission
MUST copy bounded frame bytes without waiting for a queue mutex or descriptor.
Refusal MUST retain no bytes; an already admitted request MUST be explicitly
resolved or closed, without silently retrying or granting Success.

The output owner MUST bound requests to sixteen frames of at most 262144 bytes
each and reserve four control frames of at most 512 bytes each, including their
final LF. LF elsewhere, CR, NUL and excess length MUST be refused. Selected
wire encoders separately enforce JSON, role and schema contracts. Capacity
MUST include an active frame until its bytes are fully written or discarded.
Queued controls MUST precede queued requests, with FIFO within each class and
no interleaving of an already started frame. Writing a frame MUST NOT release
the shared request context or establish consumer authorization.

Cancellation, explicit closure or consumer loss, including loss while output
is idle, MUST close output admission and shared custody, wake pending waits
without an SDK lock, and discard queued bytes. An active write MUST retire its
charged slot before the writer returns. Output closure and notification MUST
release the queue mutex before acquiring custody. Notification MUST occur once
after custody closes and MUST NOT perform SDK cleanup. The caller MUST join
every user before destroying output or closing its exclusive pipe or stream
socket descriptor; settable file status flags MUST be restored. Destruction
with queued bytes or an active writer MUST terminate the process. Closure MUST
NOT implicitly flush queued requests.

The version-1 native request codec MUST use the `matter-bridge` backend and
`request` role, separately from the controller protocol. One complete JSON
object and its final LF MUST fit within 262144 bytes. Decoders MUST require the
expected sixteen-byte process generation and refuse duplicate, missing or extra
fields at every object boundary, CR, NUL, embedded LF and unsupported cells.
The exact fifteen fields are:

| Field | Representation |
| --- | --- |
| `v` | Integer `1` |
| `backend` | String `matter-bridge` |
| `type` | String `request` |
| `generation` | Thirty-two lowercase hexadecimal characters |
| `id` | Nonzero unsigned 64-bit decimal string |
| `deadline_ms` | Nonzero unsigned 64-bit decimal string in the native clock domain |
| `thing` | One to 256 opaque bytes encoded as lowercase hexadecimal |
| `operation` | `read`, `write` or `invoke` |
| `path` | Exactly `endpoint`, `cluster`, `member`; integer endpoint 3–65534 and valid SDK cluster/attribute/command identifiers |
| `principal` | Exactly `fabric_index`, `auth_mode`, `subject`, `cats`, `is_commissioning` |
| `fabric_scope` | Exactly `epoch`, `fabric_id`, `bridge_node`, `root_public_key`, `noc_sha256` |
| `flags` | Exactly four booleans: `expanded`, `timed`, `fabric_filtered`, `allows_large_payload` |
| `list` | Exactly `{"operation":"not-list","index":0}` for the finite scalar profile |
| `data_version` | Null for reads/invokes; null or an unsigned 32-bit integer for writes |
| `payload` | Null for reads; exactly `kind` and `value` for writes/invokes |

Unsigned decimal strings MUST use `0` or a nonzero leading digit followed by
digits, without signs, whitespace or leading zeros. The principal MUST preserve
fabric index 1–254, CASE or group authentication mode, unsigned 64-bit subject
including zero, all three unsigned 32-bit CAT slots in order and the boolean
commissioning context. PASE, absent and internal authentication modes MUST be
refused by this selected codec. Fabric epoch and fabric ID MUST be nonzero
unsigned 64-bit decimal strings; bridge node MUST be an operational node ID.
The root public key MUST retain 65 bytes beginning with `04`, and the NOC SHA-256
MUST retain 32 bytes, both in lowercase hexadecimal. These representation checks
MUST NOT be presented as credential verification or current authorization.
Encoding MUST compare the complete captured principal with the request and
preserve the original fabric snapshot; exporting retained invoke metadata MUST
NOT sample a replacement scope from the current fabric table.

Read flags MUST have `timed` false. Write flags MUST have `fabric_filtered` and
`allows_large_payload` false. Invoke flags MUST additionally have `expanded`
false. Unsupported list operations MUST be refused rather than discarded.
Finite write payloads MUST use `u16` with a value 0–65535 for IdentifyTime, OnTime
and OffWaitTime, or `nullable_enum8` with null or 0–2 for StartUpOnOff. Invoke
payloads MUST use `tlv` with lowercase hexadecimal owned argument bytes and the
anonymous Structure, byte, depth and node bounds below. The syntax scan MUST
enforce the pinned SDK's tag/container rules without an implicit profile,
including its special qualified-tag representations. It MUST leave command
fields, profile identifiers and scalar values opaque; it MUST NOT substitute
the narrower controller value profile for retained SDK arguments.

Native encoding failures MUST preserve the caller's output bytes and distinguish
malformed input, excess limits and allocation failure. BEAM decoding failures
MUST return a structured invalid-frame error without external input details.
Successful decoding MUST retain the native deadline as native time; clock
projection, mandatory consumer policy and ExposedThing dispatch MUST be supplied
by their explicit owner before execution. Consumer result encoding MUST produce
the existing exact six-field `matter-bridge/result` frame within 512 bytes
including LF. Encoding either direction MUST grant no policy or effect authority.

### Consumer execution ownership

The consumer execution owner MUST start explicitly for one process generation,
with one receiver, an explicit BEAM monotonic clock, required policy and exact
routes. Dependency loading MUST start nothing. Its child specification MUST
NOT restart a lost generation implicitly. Only the configured receiver may
submit requests or collect results. The trusted native Port owner MUST preserve
native admission order when encoding and enqueueing requests before their SDK
callback returns. Delivered IDs MUST increase strictly; gaps are permitted,
but a refused submission MUST NOT be retried under its original ID. Malformed,
foreign-generation, duplicate or reversed frames MUST close execution custody.

Native deadlines MUST NOT be treated as BEAM timestamps. A projection MUST
bind one generation to a BEAM sample before a probe, a BEAM sample after its
reply and the reply's native sample. Native samples MUST round down with less
than one millisecond error; BEAM sampling error MUST be less than one
millisecond. The caller MUST qualify a positive lower BEAM/native elapsed-time
rate through the native expiry; one exchange, matching units or a shared host
MUST NOT be cited as that qualification. The selected ratio has positive terms
no greater than one million and is at most one. Projection MUST start from the
earlier BEAM sample, subtract one millisecond in each clock domain and round
the remaining qualified duration down. It MUST refuse exchanges over 500 BEAM
milliseconds, native deadlines over 500 milliseconds beyond the probe, invalid
or regressed clocks, generation mismatch and an elapsed or overflowing result.
Obtaining a fresh probe MUST NOT extend the original native deadline.

Routes MUST bind opaque Thing identity, endpoint, cluster, member and native
operation to one validated ExposedThing, exact Runtime operation, declared
Interaction Affordance and handler. At most 1024 routes may cover sixteen
distinct Thing/endpoint pairs; identity aliases and rebindings MUST be refused.
The Context MUST retain the complete decoded request, exact Runtime route,
generation-scoped request identity and conservative BEAM deadline. Policy MUST
receive that request and Context before payload mapping or handler execution.
Only explicit approval may proceed. Missing routes MUST deny execution;
malformed or failed policy and input mapping MUST fail closed without external
exception text. Captured principal/fabric values MUST NOT substitute for
authenticated SDK admission, live authorization or consumer policy.

Input mapping MUST be explicit. Approved work MUST call the exact public
ExposedThing dispatch boundary. Result mapping MUST explicitly choose completed,
denied, failed or unknown and own approved-observation delivery before declaring
completion. Dispatch or result failure, malformed outcome and expiry MUST yield
unknown outcome without retrying a handler or promoting physical-effect truth.
Policy, mapping, dispatch and result acceptance MUST share the original
projected deadline, with serialized non-regressing clock checks between stages.

Sixteen execution slots MUST include running workers and uncollected results.
Credit MUST remain charged until actual worker retirement and receiver
collection. Each staged result MUST produce one generation/ID-scoped readiness
notification and the existing bounded native result frame. Collection MUST
retire it once. Expiry MUST kill owned work and retain its unknown result.
Receiver death, clock failure, protocol failure, execution-owner loss or explicit
closure MUST reap owned workers, including workers that trap exits. The native
Port owner MUST monitor execution custody, close native custody on its loss
and resolve or refuse rejected submissions without retrying mutations.

Clock exchange MUST use separate version-1 `matter-bridge` control roles. One
`clock-probe` input has exactly five scalar fields: integer `v: 1`, the backend,
`type`, expected lowercase hexadecimal generation and nonzero canonical uint64
decimal `id`. Its `clock-sample` reply adds only `native_ms`, a canonical uint64
decimal string permitting zero. Both frames MUST include LF and fit within
512 bytes. Duplicate, missing or extra fields, wrong types, roles, generations,
identities or framing MUST be refused. Result-only decoders MUST refuse probes.

Probe IDs MUST increase strictly in a namespace separate from request IDs.
Sampling MUST verify the generation even before the first request, use the
custody owner's serialized clock and update the same non-regressing clock
history. A probe MUST reserve or retire no request credit, stage no result,
authorize no work and extend no deadline. Sampling and reply admission MUST
remain independent of the SDK stack lock, including while an SDK callback
waits for a consumer result. The reply sink MUST run after custody unlocks and
copy one bounded frame into reserved control-output capacity without blocking
or performing descriptor I/O. Malformed/replayed probes, invalid clocks and
reply refusal MUST close input and native custody and wake pending waits.

The Port owner MUST correlate each sample with its exact expected generation
and probe ID, retain its BEAM samples before sending and after receiving, and
supply the qualified projection inputs above. A successfully exchanged sample
MUST NOT be presented as host authentication, a qualified elapsed-time rate,
consumer authorization or completed native bootstrap.

### Native callback custody

Before an SDK request callback returns, retained metadata MUST own the complete
principal, including fabric, authentication mode, subject, CASE Authenticated
Tags and commissioning context, together with its exact path and operation
flags. Retained command arguments MUST be copied into one anonymous-root TLV
Structure of at most 65536 encoded bytes, 24 container levels and 4096 nodes,
counting the root. Malformed or excessive arguments MUST acquire neither a
request slot nor an SDK command handle. A retained invoke context MUST own an
SDK command handle until its result is consumed. An invalidated handle MUST
NOT be used for a response. Only an explicit renderer for the selected command
semantics may encode a completed consumer result; response-encoding failure
MUST still release the consumed context. Closure MUST drain retained handles
under the SDK stack lock before stopping the event loop. Destruction with a
retained handle MUST terminate the process.

The retained invoke owner MUST require an explicit SDK guard before copying
arguments or reserving custody. The guard MUST capture the exact fabric realm,
a non-reused local epoch and operational-certificate digest, together with the
live command metadata and required invoke privilege. Child admission MUST
require a current fabric and current SDK ACL grant. Immediately before a
completed renderer, the owner MUST revalidate that realm, live path, unchanged
command contract and current ACL. Fabric deletion, index reuse, credential
update or rollback MUST NOT revive a retired scope. Metadata failures MUST
preserve their error meaning. A guard failure MUST prevent completed rendering
and still release the consumed SDK handle; refusal encoding MUST NOT erase the
guard error. The scope owner MUST detach from the fabric table after draining
contexts and before SDK shutdown. Active destruction MUST terminate the host.
These checks do not authenticate a supplied principal or grant consumer policy.

A retained attribute write MUST own its scalar value and complete callback
metadata before its decoder expires. The finite profile permits IdentifyTime,
OnTime and OffWaitTime as unsigned 16-bit values, and StartUpOnOff as null or
the defined Off, On and Toggle values. Unsupported paths and list operations,
or a principal differing from the decoder's complete principal, MUST be refused
before decoding. Invalid type/range values MUST preserve their SDK error and
acquire no handoff slot. Valid writes MUST share the same sixteen-context
custody and original deadline as other operations. Admission MUST NOT mutate
approved state or establish consumer authorization. The receiver MUST consume
every admitted write ticket before returning its synchronous SDK response.

A delayed native renderer MUST use the captured principal and timed context,
without querying the original SDK handler's session or exchange. Its scoped
reply adapter MUST copy at most eight distinct permitted response command IDs
and write at most one reply for the original endpoint/cluster/command path.
Invalid scope or path MUST prevent response service. A data-encoding failure
MUST remain observable even if the SDK-defined Failure-status fallback is
written. A renderer that produces no reply MUST NOT establish completion.
Retaining an SDK handle from the scoped adapter MUST terminate the process
before a borrowed adapter can escape its renderer-call lifetime.

The installed SDK data-model provider MUST preserve generated metadata and
Root Node/Aggregator operations while routing live child reads, writes,
commands and list-write lifecycle notifications to an explicit native
receiver. Child operations MUST NOT fall back to native cluster execution.
Disabled or absent endpoints MUST be refused before receiver delivery;
metadata allocation failures MUST retain their error meaning. Receiver
metadata MUST own its principal and operation flags before the callback
returns. An asynchronously retained invocation MUST NOT return an automatic
Success status. SDK path and fabric/ACL validation remains a prerequisite;
the provider wrapper alone does not establish consumer authorization.

The provider MUST relay delegated attribute/endpoint change notifications
under the SDK stack lock and unregister its listener before delegated
shutdown. Partial startup, failed shutdown or destruction while active MUST
terminate the process before borrowed provider context can be released.
A closed provider MUST NOT reopen its SDK lifetime or serve interactions.

## Bridged devices

A bridge may represent non-Matter physical devices. The bridge contract MUST preserve that distinction and cannot claim the underlying device itself is Matter-certified.

## Evidence

Required software peers include a bridged light and at least one non-light endpoint. Physical ecosystem evidence is separate and should include independent Matter controllers only after the generic server contract passes software gates.

CSA certification is outside ordinary package conformance and must never be implied by passing WMA tests.

## Finite server profile

The [exposed bridge profile](../plans/exposed-bridge-profile.md) owns the
selected Matter 1.6 Device Types, mandatory clusters/commands, generated
model, build options, bounded consumer handoff and separately owned test
credentials/peer inputs. The required On/Off Light includes Identify, Groups,
the Lighting feature and Scenes Management; a three-command On/Off-only
endpoint does not satisfy that selected Device Type. Temperature Sensor
includes Identify. Fabric-scoped group/scene operations and permitted
attribute writes MUST retain consumer authorization before dispatch.

Reproducible model generation is distinct from server implementation. It
does not establish fabric-store custody, commissioning, callback behavior,
reporting, independent-peer interoperability or certification.

## Delivery

The [exposed bridge delivery plan](../plans/exposed-bridge-delivery.md) sequences the existing target's native profile, endpoint custody, consumer authorization, reporting and independent-peer evidence. It adds no implementation claim to this target or the controller catalogue.
