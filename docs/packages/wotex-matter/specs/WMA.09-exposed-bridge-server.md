# WMA.09 Exposed Matter bridge/server target

## Status

Version: 0.23.0-target.

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

The explicit credential owner MUST copy consumer-supplied DAC, PAI and
Certification Declaration bytes without selecting example credentials. DAC
and PAI MUST each contain 1–600 bytes; the declaration MUST contain 1–4096
bytes. The owner MUST validate the pinned SDK's DAC/PAI certificate formats,
require matching DAC vendor/product identity and compatible PAI identity,
and import exactly the SDK's 97-byte serialized P-256 keypair. The DAC public
key MUST match the imported key, and a locally signed challenge MUST verify
with that DAC key before provider service. These checks MUST NOT be represented
as PAA-chain trust, Certification Declaration verification or certification.

Commissioning MUST require an explicit SDK-valid setup passcode, discriminator
0–4095, iteration count 1000–100000 and 16–32-byte salt. Provider creation MUST
NOT install global providers, invent onboarding material or select a random
salt. The owner MUST derive and retain its own bounded PASE verifier and copy
its attestation bytes. Callers MUST own and clear their original private input.
Creation failure MUST preserve the caller's existing owner. Provider signing
MUST accept only 1–4096 message bytes and sufficient signature capacity.
Immutable commissioning setters MUST refuse changes. After global references
are retired, explicit retirement MUST refuse all getter/signing service and
clear the retained key, verifier, salt and passcode. Failure MUST preserve
caller output. Provider calls and retirement MUST remain serialized by the
SDK owner.

Native bootstrap material MUST use explicit consumer-owned private snapshots,
with no file discovery or repeated credential reads after loading. A snapshot
MUST accept only a normalized absolute path of at most 4096 bytes, refuse NUL,
CR, LF, empty components, `.` and `..`, and follow no parent or leaf symlink.
It MUST require a regular file owned by the effective user, one hardlink and
exact mode 0400 or 0600. The caller MUST select a maximum of 1–65536 bytes;
empty or excessive files MUST be refused before byte allocation. Reads MUST
handle short reads and interruptions, verify EOF, and refuse an observed
change in file identity, size, ownership, permissions, links or modification
metadata. Failure MUST preserve the previous snapshot. Release MUST clear
the complete owned byte allocation. These checks MUST NOT be described as
filesystem immutability or protection from a malicious file owner; the consumer
owns original disk material and other copies.

The internal commissioning-input format MUST contain exactly `WMCSET1` followed
by NUL, a big-endian uint32 passcode, uint16 discriminator, uint32 iteration
count, uint8 salt length and the salt bytes. Its total length MUST be 35–51
bytes, discriminator 0–4095, iterations 1000–100000 and salt length 16–32.
Extra, missing or malformed bytes MUST be refused without changing the current
owner. The decoder MUST copy the salt and passcode into its own bounded storage
and clear both on retirement. Successful structural decoding MUST NOT establish
SDK PIN validity, provider creation or commissioning. This is a package bootstrap
format, not a Matter or W3C-standard field.

Native bootstrap configuration MUST use the package format
`wotex.matter.bridge-bootstrap@1`: one UTF-8 JSON object of at most 65536 bytes,
with exactly the following twenty-one required fields. Unknown or duplicate
members, trailing input, unsupported nesting, raw NUL and incorrect scalar types
MUST be refused. Numeric fields MUST use integer values, not floating-point,
boolean or string representations. Integer zero MUST retain its value regardless
of the parser's signed representation. No absent member MUST select a default.

| Field | Required value |
| --- | --- |
| `schema` | Exactly `wotex.matter.bridge-bootstrap@1` |
| `sdk_revision` | Exact selected revision from the native bridge controls |
| `model_sha256` | Exact selected generated-model digest from the native bridge controls |
| `bridge_id` | 2–512 even lowercase hex digits, decoded to 1–256 opaque bytes |
| `vendor_id` | Integer 1–65534 |
| `product_id` | Integer 1–65535 |
| `vendor_name`, `product_name` | Nonempty UTF-8 strings of at most 32 bytes, without NUL |
| `hardware_version` | Explicit integer 0–65535 |
| `hardware_version_string` | Nonempty UTF-8 string of at most 64 bytes, without NUL |
| `store_path` | Normalized absolute UTF-8 path of at most 4096 bytes, without NUL, CR, LF, empty components, `.` or `..` |
| `store_mode` | Exactly `new` or `reopen`, without a create-or-open fallback |
| `interface` | Explicit nonempty UTF-8 name of at most 15 bytes, without NUL, CR or LF |
| `port` | Integer 1–65535 |
| `commissioning_window_seconds` | Explicit integer 0 for closed or 180–900 for one finite startup window |
| `dac_path`, `pai_path`, `declaration_path`, `key_path`, `commissioning_path` | The same path constraints as `store_path` |
| `devices` | Array of zero to sixteen exact device configurations |

Each device object MUST require exactly `thing_id`, `device_type`, `node_label`,
`minimum_temperature` and `maximum_temperature`. Thing identities MUST use the
same hex representation as `bridge_id` and be unique by decoded bytes. Device
Type MUST be On/Off Light (`256`, `0x0100`) or Temperature Sensor (`770`, `0x0302`).
Node labels MUST be UTF-8 strings of at most 32 bytes, preserving their existing
SDK byte meaning. Both temperature members MUST be explicit null for a light.
A sensor MUST supply explicit null or signed hundredths of a degree Celsius:
minimum -27315–32766, maximum -27314–32767 and maximum greater than minimum when
both are present. Unsupported types, duplicate identities and extra device
members MUST be refused.

The decoder MUST perform no filesystem access, credential validation, provider
installation, network activity or SDK startup. Failure, including allocation or
library-capacity refusal, MUST preserve the caller's existing configuration
owner and return a fixed classification. The owning file, store, credential and
network boundaries MUST separately validate their actual resources. Window
opening and expiry MUST belong to the SDK process owner, without automatic
reopening after expiry. A parsed setting MUST NOT open a window or establish
commissioning, authentication or interoperability. This configuration is a
package bootstrap format, not a Matter or W3C-standard field.

Private bootstrap loading MUST take one explicit configuration-file path after
caller SDK memory initialization. It MUST use the bounded private-file boundary
for the configuration and all five selected material files. Configuration MUST
fit within 65536 bytes; DAC/PAI and declaration MUST retain their credential-owner
bounds. The serialized keypair MUST have the selected SDK's exact 97-byte
capacity, and commissioning input MUST have its exact 35–51-byte layout.
Provider creation MUST use the configured VID/PID and the explicit decoded
commissioning material. The loader MUST clear its passcode copy, decoded PIN/salt
and original key/setup snapshots after the credential factory call, on success
or refusal. All temporary snapshots MUST retire on every return path. Original
consumer files and copies remain consumer-owned.

Loading failure MUST preserve the previous configuration/credential owner and
return a fixed file, configuration, credentials or no-memory classification,
without paths or external diagnostic text. Loading MUST install no provider,
initialize no platform or store, perform no network/window action and start no
SDK server. Before releasing or replacing a successful owner, its caller MUST
retire all borrowed provider references. Loading MUST NOT establish trusted
attestation, commissioning, peer interoperability or certification.

The internal SDK resource owner MUST borrow one successfully loaded bootstrap,
unchanged configuration, request custody, receiver and explicit closed
commissioning provider for its entire serialized lifetime. Its caller MUST
initialize SDK memory. Initialization MUST refuse reused, closed or pending
custody before filesystem or platform startup, resolve only the selected
interface and open only the selected store mode. Pre-platform allocation
failure MUST return a fixed no-memory error. After entering the locked store
directory, partial platform/server startup MUST terminate with 70, without a
successful process receipt.

New-store startup MUST durably allocate every explicitly configured initial
device identity before dynamic SDK registration. Reopen MUST restore exactly
the compatible live mappings and MUST NOT allocate absent devices as a fallback.

The owner MUST install its explicit credentials before platform startup and
its configured public identity after platform startup but before server startup.
Absent optional factory identity MUST return not-implemented without selecting
SDK example values. Identity retirement MUST refuse service and preserve output.
The Ethernet driver MUST inspect only its explicit externally configured
interface, expose at most one bounded iterator entry and derive connected state
from actual kernel UP/RUNNING flags. Sampling failure MUST refuse service;
shutdown MUST prevent reopening. It MUST NOT discover, configure or retry a
network connection.

The owner MUST require an initially closed commissioning window, retain zero
as closed or open exactly one configured 180–900-second startup window. SDK
expiry MUST close that window without automatic reopening. Starting and stopping
the event loop MUST be explicit, serialized and outside the SDK stack lock;
stopping MUST join the loop from outside that loop. Initialization and final
cleanup MUST acquire the SDK stack lock themselves. Cleanup MUST require a
stopped loop and already closed, fully consumed request custody. It MUST close
the window, retire endpoints/server and borrowed model/storage references,
restore captured identity/attestation providers, install the explicit closed
commissioning provider, shut down the platform, restore the original process
directory and release the store lock. Cleanup failure or active destruction
MUST terminate with 70 before a successful closed receipt. The resource owner
alone MUST NOT establish Port readiness, authenticated request admission,
consumer authorization, clock-rate qualification or independent-peer support.

The bridge SDK logging hook MUST discard module, format and argument data
without dereferencing, formatting, emitting or retaining it. The explicit
process owner MUST report only fixed stage codes. Controller logging belongs
to its separate host profile.

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

### Native process coordination

The BEAM connection MUST start explicitly with a live local owner, an absolute
caller-selected immutable executable, its lowercase SHA-256, explicit arguments,
nonblocking clock, qualified minimum rate, required policy, exact routes and a
handshake timeout from 1 to 5000 milliseconds. It MUST refuse missing, malformed,
nonexecutable, symlink or digest-mismatched artifacts before starting native
execution. It MUST clear inherited environment variables and MUST NOT discover,
download, build or restart an executable implicitly. File digest admission MUST
NOT be presented as protection against replacement of a mutable selected file.

One random 16-byte generation MUST bind the complete process lifetime. The
version-1 `matter-bridge/open` and `close` controls each have exactly four scalar
fields: integer `v: 1`, `backend`, `type` and lowercase hexadecimal `generation`.
The `ready` receipt adds exactly `sdk_revision` and `model_sha256`, matching the
selected SDK revision and generated model. The `closed` receipt has only the four
base fields. Every control MUST include LF within 512 bytes; duplicate, missing,
extra, mistyped or foreign-generation fields MUST be refused. A ready receipt
MUST NOT substitute for authentication, initialized credential ownership or
clock qualification. The selected native host MUST enforce SDK admission and
close/drain custody on input loss before releasing SDK resources.

Startup MUST require an exact ready receipt and one correlated clock exchange
within its absolute handshake deadline. Requests received during that exchange
MUST remain inert until bootstrap succeeds. Queued and running requests together
MUST fit within sixteen slots, preserve strictly increasing native IDs and retain
their original native deadlines. One pending probe MUST service the ordered
queue; each request may trigger at most one fresh probe. A fresh sample that
regresses or still cannot cover the original deadline MUST close the generation.
Expired queued work MUST return unknown without executing policy or a handler.
Accepted work MUST use the private consumer execution boundary and collect each
result once. Native writes MUST NOT suspend this connection; a busy or failed
pipe MUST close the generation without retries.

Only the configured owner may inspect bounded generation/count status or request
close. Owner, execution-owner or native loss MUST stop owned work and reap the
native process. Failure reports and diagnostic status MUST exclude payloads,
bootstrap arguments, route contents and external exception text. An admitted
mutation MUST make subsequent channel loss conservatively unknown. Startup
refusal MUST return a structured error after cleanup without terminating the
linked caller. Temporary supervision MUST NOT restart a lost generation.

Explicit close MUST stop consumer work first, then require the exact closed
receipt, zero native exit and joined Port release within one second of native
close admission. It may discard at most sixteen strictly increasing in-flight
requests and one outstanding correlated clock reply without executing them.
Other output, output after acknowledgment, nonzero exit or missed grace MUST
fail close and force cleanup of the owned native child. Process coordination
tests with a scripted host MUST NOT be cited as actual SDK process bootstrap,
authenticated requests, approved-observation delivery or qualified host clocks.

The native first-frame decoder MUST accept only the exact four-field `open`
control supplying version, backend, type and the sixteen-byte generation.
Subsequent input MUST refuse `open`. The exact four-field `close` control MUST
match both the reader's generation and shared custody, close admission and wake
pending waits before native cleanup. Ready/closed encoders MUST preserve the
selected receipt fields and existing LF/512-byte limit; failure MUST preserve
caller output.

After cleanup, the shutdown owner MAY explicitly finish output with a final
bounded control. This operation MUST refuse new output and discard frames
whose writing has not started, while preserving the one active frame through
its final LF before writing the terminal control. The terminal control MUST
be written once, followed by output retirement. Allocation or counter refusal
MUST preserve the queue. Cancellation or consumer loss MUST abort the finish
without promoting it to successful closure. Finishing output MUST NOT establish
SDK cleanup or authorize a closed receipt before actual native cleanup.

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
