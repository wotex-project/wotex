# CoreBluetooth host v1

Version: 0.7.0. Updated: 2026-10-20. Status: accepted delivery contract.
Owner: [WBL.08](WBL.08-write-modes-and-native-hosts.md), requirements 01–04.
Implementation and executed evidence are recorded in the package catalogue.

## Native operation ownership

The host keeps one serialized operation at a time. Its explicit ticket consists
of a nonzero consumer connection generation, a non-reused request number and an
exact characteristic-route token. The SDK owner holds the peripheral and
characteristic objects for that route. A callback from another ticket, route or
generation cannot complete the operation. A timed-out or cancelled submitted
operation retires its entire SDK owner before another generation may start.

The native operation takes an explicit nonnegative elapsed time, one absolute
deadline at most 60,000 ms later, the complete selected route, at most 512 bytes,
an SDK port and a bounded result sink. It reads no clock or global configuration.
The SDK port supplies current authorization, connection/route identity, the
per-write-mode maximum length, command readiness, submission and actual retirement
state. Submission additionally receives the original deadline and returns its
accepted/refused/uncertain classification, fixed cause and observed elapsed time.
The port rechecks time and current SDK facts after marker admission, immediately
before calling the SDK. A regressed or expired return observation retires the
operation and cannot become queue success. Its callbacks are prompt, nonthrowing and non-reentrant; the SDK owner
serializes delegate events after the initiating call returns. This port does not establish
that those supplied SDK facts have been independently qualified.

Reads require a readable route and empty input. Acknowledged writes require the
write property. Commands require the distinct write-without-response property.
For either write, the complete input must fit both 512 bytes and the current SDK
maximum for its exact mode. A zero/unavailable SDK maximum refuses. No value is
split, truncated, retried or changed to another write mode.

Before a command is submitted, readiness, authorization, route, size and the
original deadline are checked again. Waiting for readiness consumes that same
deadline and emits no submitted marker. A readiness callback for another ticket
does nothing. A readiness callback is only a reason to recheck current facts;
it cannot override a currently false readiness value.

A bounded submission marker must be admitted before either write reaches the
SDK. Marker refusal sends nothing. A command succeeds with native queue evidence
only after the SDK port reports submission accepted; it never waits for or
fabricates an ATT response. An acknowledged write succeeds only on its matching
write callback. A read succeeds only on its matching bounded value callback.
Errors after the marker preserve submission uncertainty. Success is emitted at
most once, and a finished operation cannot be restarted.

Cancellation, deadline equality, clock regression, authorization loss, route or
connection loss and malformed matching callbacks fence further submission.
Retirement is requested once. Its single 500 ms budget never extends on repeated
cancellation or callbacks. A terminal result waits for confirmed owned-resource
retirement; refusal or expiry instead returns cleanup_timeout with the original
cause and submission classification. Confirmation must be observed strictly
before the cleanup deadline; equality is expired. Initiating retirement is not confirmation.
Destroying an unfinished operation is a native lifetime error, not silent cleanup.

## SDK and public client delivery

The SDK adapter implements the port through CoreBluetooth on a dedicated
serialized callback queue, using exact peripheral/characteristic object identity.
The public Client and installed permission/peripheral qualification must exist
before claiming that these native components are a usable public macOS backend.
Ordinary package loading must
not instantiate a manager or prompt for permission.

The adapter must consult maximumWriteValueLengthForType for the selected write
type and canSendWriteWithoutResponse before a command. The readiness delegate
does not supply an acknowledgement. CoreBluetooth cancellation is asynchronous;
the adapter must confirm its owned callbacks/objects are retired and preserve
uncertainty about work already given to the system. OS pairing/security policy,
explicit private peripheral identity and unsupported capability cells remain
part of the required adapter contract, never inferred from a UUID or paired flag.

Notifications, sleep/reset/permission loss, consumer-owned startup,
CoreBluetooth/Runtime/archive joins and installed macOS qualification remain
WBL.08 obligations. Delivering the operation component does not waive them.

The native operation component is implemented in
`packages/wotex-ble/priv/corebluetooth/native/operation.hpp`. Its fourteen-case
independent scripted-port corpus is
`packages/wotex-ble/test/native/corebluetooth_operation_test.cpp`, executed by
`corebluetooth_operation_test.exs`. This component and its tests instantiate no
CoreBluetooth manager and establish no SDK, permission or peripheral behavior.
The [operation record](../provenance/corebluetooth-operation-2026-10.md) binds
the ordinary/sanitizer runs, source identities, actual checks and omissions.

`packages/wotex-ble/priv/corebluetooth/native/sdk.cpp` implements the SDK owner
entry below through the real framework selectors, including bounded complete
discovery, command readiness, generation retirement and released object custody.
Its injected-selector tests establish the adapter's software behavior. The
native process and explicit build entry below are implemented. A public Client
is still required before the package has a usable macOS session.
The [SDK record](../provenance/corebluetooth-sdk-2026-10.md) binds the current
operation/SDK inputs, thirty ordinary/sanitizer cases and native suite results.

## Acceptance

### SDK owner entry

The internal C++ SDK owner starts explicitly with a canonical 36-byte peripheral
UUID, nonzero consumer generation, `require_authorized` (default) or `request`
permission policy, explicit `system` pairing policy, supplied clock and sink,
and one opening deadline of at most 60,000 ms. The UUID is private macOS routing
data. Unknown policies, malformed identity, invalid deadlines and reuse refuse.
Restricted/denied authorization, or undetermined authorization under the default
policy, refuses before manager construction. Explicit `request` permits the
system permission prompt; `system` permits OS-managed pairing. Neither policy
provides a consumer credential decision or a guarantee of link security.

The owner uses one private serial delegate queue, retrieves only the supplied
identifier and never scans or reconnects. Opening covers connection and complete
discovery under the same deadline. Discovery admits at most 64 services and 256
characteristics, checks actual peripheral/service/characteristic association and
copies canonical Bluetooth UUIDs, properties and generation-scoped route tokens.
Duplicate UUIDs remain distinct routes. Missing identifiers and over-bound or
malformed discovery refuse and retire the owner; no partial discovery is success.

One operation is admitted at a time with an increasing, nonzero uint64 request
number and an exact discovered route. Current SDK object identity and properties
are rechecked. CoreBluetooth supplies no echoed request ID: its documented
serialized delegate completions are attributed only to the sole outstanding
procedure; timeout, cancellation, service invalidation or loss retires the whole
owner before any successor can start. Old delegate objects are detached from
the owner. A read refuses while the characteristic is notifying, because the
value delegate alone cannot distinguish a read from a notification. Notification
support needs its separately qualified receiving contract.

The native host supplies polling and elapsed-clock observations, including while
idle. Regression, opening expiry, authorization loss, reset, power loss,
disconnect and service invalidation end the generation. Retirement clears
delegate owner references, detaches SDK delegates, requests cancellation once
and releases all retained SDK objects on the serial queue. This confirms owned
callback/object retirement, not physical disconnection or unsending queued work.
Cleanup exceptions remain unconfirmed. Sinks are bounded, prompt, nonthrowing and
non-reentrant. Destruction requires an idle or explicitly retired owner and joins
the serial queue; it cannot silently abandon a running owner.

The SDK source is Objective-C++17 at the Apple framework boundary. Its native
suite is explicitly scoped to `darwin`; other hosts record no Mac qualification.
Injected objects must implement the actual SDK selectors. Such tests establish
adapter behavior under supplied callbacks, not real authorization, connection,
pairing or radio behavior. The point Client/Runtime join is delivered below;
public receiving is specified below; sleep observation and independent archive
qualification remain separate required host-delivery work.

| Case | SDK stimulus and falsifier |
| --- | --- |
| CB-SDK1 | Default/denied/unknown permission and malformed startup create no manager; explicit request reaches only the selected identifier |
| CB-SDK2 | Bounded complete discovery preserves duplicate UUID routes; wrong object association, excess cardinality and expired opening produce no opened success |
| CB-SDK3 | Actual read/write selectors, exact NSData bytes, separate mode maxima and command readiness preserve operation evidence; notifying reads refuse |
| CB-SDK4 | Foreign delegates, service invalidation, power/permission/clock loss and original deadlines cannot settle successor work or reconnect |
| CB-SDK5 | Explicit close/cancel detaches delegates, releases owned references once and preserves submitted uncertainty; separate owners remain independent |

### Native operation acceptance

| Case | Independent stimulus and falsifier |
| --- | --- |
| CB-OP1 | Read, acknowledged write and command preserve exact ticket/mode/bytes; only their matching completion evidence succeeds |
| CB-OP2 | Empty/512-byte, exact SDK maximum and one-over inputs; missing property/maximum, invalid ticket/deadline and refused marker invoke no SDK submission |
| CB-OP3 | Readiness waits, duplicate and foreign callbacks, changed size/permission/route, clock regression and deadline equality cannot send unsent work |
| CB-OP4 | Submitted timeout/cancellation preserves uncertainty; repeated cancellation cannot renew cleanup; late callbacks cannot complete a retired operation |
| CB-OP5 | Pending/confirmed/unconfirmed retirement, exact 500 ms cleanup boundary, one result and unfinished destruction are distinguished |

## Native process and build entry

The CoreBluetooth process uses UTF-8 JSON lines, each at most 131,072 bytes
including LF, with the existing bounded duplicate-key/depth/node parser.
It emits exactly `{"version":1,"event":"ready","backend":"corebluetooth-native","revision":"1"}`
before creating an SDK owner. This receipt supplies artifact/protocol identity,
not permission or connection readiness. The process accepts no command-line
options. Loading the package or running a closed-input build probe creates no
manager and prompts for no permission.

Requests have exactly `version`, `id`, `operation`, `parameters`, `timeout_ms`.
Version is 1 and timeout is 1..60,000 ms. The first open uses id `open`; subsequent
data IDs are strictly increasing canonical nonzero uint64 decimal strings;
close uses id `close`. One generation is opened per process. Repeated open,
reused IDs, malformed frames and unsupported operations end the process without
fallback. Ordinary operations are `discover`, `read`, `write`, `write_command`
and `health`; subscription/pairing commands have no implicit implementation.

Open parameters are exactly `identifier` (canonical lowercase 36-byte private
peripheral UUID), `generation` (nonzero uint64), `permission`
(`require_authorized` or `request`) and `pairing` (`system`). Discovery, health
and close take an empty object. Read takes exactly `address`; both writes take
exactly `address` and a canonical 512-byte-bounded byte envelope. Address is
exactly nonzero uint64 `generation` and `route`, matching the opened generation
and a current discovered token. UUID matching and ambiguity policy belong to
the public Client, not a fabricated D-Bus path or ATT handle.

Successful replies have exactly `version`, `generation`, `id`, `ok: true` and
`result`. Open returns `{"generation": G}`; discover returns
`{"characteristics": [...]}` with up to 256 complete records. Each record has
exactly `route`, `service_uuid`, `characteristic_uuid`, `read`, `write`,
`write_without_response`, `notify` and `indicate`; tokens are 1..N in SDK discovery
order and UUIDs are canonical 128-bit Bluetooth strings. Read returns the
existing byte envelope, write returns null, command returns the existing exact
native-queue evidence, health returns `{"connected":true,"services_resolved":true}`,
and close returns null only after confirmed owned retirement.

Errors replace result with exactly `error`, containing fixed `code`, `cause`,
Boolean `submitted` and Boolean `cleanup_confirmed`; `ok` is false. No NSError
domain/message or private identifier is returned. A malformed open may carry
generation zero because no valid generation was admitted. A bounded
`write_submitted` control contains exactly version, generation, event and id.
It is admitted before the SDK call; loss of its delivery never establishes that
a write was unsent. A `connection_lost` control has exactly version, generation,
event and fixed code. Neither event establishes a physical outcome.

The original native deadline starts when a complete frame is received and is
retained through native dispatch and callbacks; no queue wait renews it. The
Client separately owns its full startup/call deadline including transit and
retires the process on expiry. Native elapsed coordinates do not qualify a
BEAM/native clock relationship or guarantee physical completion by a wall time.
A successful callback observed after its retained native deadline is withheld
until retirement and returned as timeout, retaining submitted uncertainty.

The process admits one SDK operation and at most 64 reply reservations, including
queued output. Additional data requests while one is active return busy without
SDK dispatch. Existing bounded native output reserves controls separately and
flushes at most 65,536 bytes/64 attempts per turn. Serialized SDK callbacks enqueue
through a fixed bounded inbox without taking the output mutex. A one-use atomic
submission gate checks the exact ticket, mode and original deadline before
admitting a write marker; refusal prevents the SDK handoff. Accepted markers
precede their point replies even if close overtakes result delivery. Inbox
overflow or output failure fences the process. Callbacks never wait for stdout.
Input/partial-input EOF, malformed
input, consumer output loss, clock failure and owner loss retire the SDK owner.
Explicit close can overtake active work and drains already admitted output for
at most 500 ms. The independent existing C guardian enforces process-group
retirement if the host stalls. There is no retry, reconnect or session reuse.

The macOS build is explicit, offline and workspace-owned. It records actual
compiler/SDK/tool and source identities, exact arguments, binary digests and
closed-input ready probe. The executable embeds a generic Bluetooth usage
description and links only Apple system frameworks and its C++ runtime; the
separate runtime guardian is built from its pinned existing source. Immutable
deployment files and their digests remain consumer inputs. A verified build
or probe establishes no installed permission, peripheral or RF result.

| Case | Process stimulus and falsifier |
| --- | --- |
| CB-H1 | Closed input emits only the pinned ready receipt; invalid input/private identifiers produce no manager or leaked error text |
| CB-H2 | Independent process requests retain generation, exact bytes/mode, route bounds, increasing identity and one active procedure |
| CB-H3 | Deadline/late callback, EOF, malformed frame and busy/output pressure cannot renew or silently replay work |
| CB-H4 | Close overtakes active work, preserves uncertainty and confirms actual retirement before success; blocked output remains bounded |
| CB-H5 | Exact build/reuse checks source/tool/argument/binary identity, rejects changed artifacts and packages the required source closure |

The [native process/build record](../provenance/corebluetooth-host-2026-10.md)
binds the current inputs, ten independent process cases, three actual macOS
build cases, renewed forty-case sanitizer corpus and extracted archive
compilation. That record covers the native process/build; the public Client
evidence is separate below. Installed-host obligations remain open.

## Public Client and point-operation entry

`Wotex.BLE.CoreBluetooth` implements the existing Client callbacks and explicit
`start_link/1`, `session/1`, `discover/2` and `health_check/2` ownership seams.
Its pure `Peer.new/1` accepts exactly one UUID identifier, normalized lowercase;
inspection hides it. Connection options require that Peer, nonzero uint64
`generation`, `pairing: :system` and the complete native executable/digest/
guardian/digest cohort. Optional permission is `:require_authorized` (default)
or `:request`, timeout is 1..60,000 ms (default 5,000), and owner is a local PID
(default the initiating caller). Duplicate/unknown options and unsupported
policies refuse before executable verification or startup. No Linux selection
or artifact discovery is implicit.

The consumer-owned connection verifies both immutable artifacts in a monitored
startup worker, pins the exact CoreBluetooth ready receipt, opens and validates
the complete discovery result under one original startup deadline. An opaque
handle binds local PID, private reference and consumer generation. The owner
admits at most 64 calls, including one active native operation; queued expiry
and caller loss remove unsent work. Active expiry/caller loss, owner death,
malformed/mismatched output and native loss retire the generation without replay.
Wire IDs are assigned only at dispatch. Public calls remain bounded even for a
forged or unresponsive PID. Inspection/status and errors omit private routing
identity, artifact paths, native text and request values.

Discovery returns at most 256 immutable CoreBluetooth Characteristic values.
Each carries exact service/characteristic UUIDs, generation, route token and
read/write/command/notify/indicate properties. `Characteristic.address/1` produces
the shared Address with `native_route: {:core_bluetooth, token}` and generation.
This new optional Address selector is mutually exclusive with ATT handle and
D-Bus path, requires nonzero generation and is never interpreted by BlueZ.
Omission preserves existing facade/mapping message fields; it does not insert
a nil selector into legacy messages or alter the BlueZ wire grammar.

CoreBluetooth requests accept only read/write messages. Exact native routes
must match their generation and both UUIDs in the admitted discovery snapshot.
UUID-only requests select exactly one matching route; zero and multiple matches
refuse. An optional supplied generation must match. BlueZ path/handle selectors
refuse before native dispatch. Requested properties and byte/mode bounds are
checked without mode substitution. Reads return bytes; acknowledged writes
return `:written`; commands retain the exact native queue evidence. A write
success requires one matching submitted marker; duplicate/malformed/foreign
markers or acknowledgements cannot count as success. Errors preserve explicit
not-submitted versus possible-submission classification; loss after handoff is
unknown unless an exact native refusal establishes otherwise.

Successful disconnect joins native close and actual guardian exit. Cooperative
cleanup has a finite 1,500 ms allowance, including forced guardian retirement;
failure stays explicit. Repeated disconnect has no additional effects; a handle
whose owner has already stopped returns disconnected rather than inventing a
new cleanup receipt. Startup failures and fatal operation outcomes wait for
owned retirement before completion, retaining uncertainty when cleanup cannot
be confirmed. No public operation performs an automatic retry.

The facade accepts these sessions for typed read/write, discovery and health.
The existing `:ble` Runtime point profile uses the same Client and codecs with
explicit `target` label and Peer configuration; the configured target must
exactly match the Form target before acquisition. The label is a consumer
binding, not an inferred native UUID, MAC address or authentication claim.
Runtime retains command `:accepted` status. The GATT streaming profile joins
the notification receiving entry below. Manual pairing and sleep observation
remain unsupported. Existing BlueZ/custom-client behavior is
preserved, including conservative errors from untrusted custom clients.

| Case | Client stimulus and falsifier |
| --- | --- |
| CB-C1 | Pure peer/options/characteristic boundaries reject malformed/forged input without startup; default permission and independent instances remain explicit |
| CB-C2 | Facade discovery/read/request/command preserve exact route, bytes, generation and evidence through an independent native process |
| CB-C3 | Queue flood, expiry, dead callers/owner, startup loss and native faults remain bounded; expired unsent work never appears on the wire |
| CB-C4 | Marker/acknowledgement and error mutations cannot fabricate success or known-unsent evidence; cleanup and status remain private |
| CB-C5 | Public Runtime reads/writes retain target binding, codecs, caller deadline and command status; unsupported profiles/security acquire nothing |

The [public Client record](../provenance/corebluetooth-client-2026-10.md) binds
thirteen process/facade/Runtime cases, the complete fast gate and extracted
archive compilation to the exact committed source. Notification, sleep and
installed-host obligations remain separate.

The [Apple write API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue(_:for:type:)),
[per-mode length API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:))
and [readiness API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/cansendwritewithoutresponse)
provide SDK vocabulary. The installed macOS 27.0 SDK headers were inspected;
that inspection does not qualify runtime permissions, a peripheral or RF behavior.

## Native notification ownership

The SDK owner adds explicit `subscribe(request, route, mode, credit, now,
deadline)`, `unsubscribe(request, subscription, now, deadline)` and
`acknowledge(subscription, sequence, now)` entry. These are internal native
interfaces; the public receiving entry below owns Client streaming. Calls share
the existing serial queue, monotonic request namespace, generation and original
1..60,000 ms control deadline. At most one point operation or notification
control is outstanding, while established streams may receive alongside a point
operation on another route. A read refuses a route being established, active,
stopped or previously retired as a stream, because the SDK value callback has no
request identity. Writes retain their separate callback/evidence path.

Modes are auto, notify and indicate. Auto chooses notify when available,
otherwise indicate. An indication-only characteristic admits auto/indicate;
a notification-only characteristic admits auto/notify. For both properties the
Apple API enables notifications only, so auto/notify select notify and explicit
indicate refuses before SDK invocation. This is the
[documented setNotifyValue behavior](https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:)),
not the BlueZ mode-selection policy. An already notifying unowned characteristic
refuses; the owner never adopts or disables another consumer's subscription.

At most sixteen streams are live. Every successfully submitted start consumes
its route for the connection generation, including a subsequently failed or
stopped start; reuse needs an explicitly opened new generation. Subscription
identity is its original nonzero request number, with the exact characteristic
object/service/peripheral association. Establishment succeeds only after the
matching notification-state callback, no error, unchanged properties and an
enabled `isNotifying` state before the original deadline. Foreign/retired
callbacks cannot establish another stream. Stop closes report admission before
calling the SDK and succeeds only after the matching disabled callback. No
automatic retry or mode substitution occurs.
The control result's `enabled` field names the requested target; only `ok`
establishes the matching observed state. A failure does not assert that the
remote configuration changed or remained unchanged.

Each stream reserves 1..64 report credits at start; all streams together reserve
at most 64. Reports contain an owned 0..512-byte value and an increasing nonzero
uint64 sequence. They describe `corebluetooth_value_update`, not a synthetic
initial value, canonical Property truth or independent ATT-origin evidence.
Before establishment, at most the reserved credit is retained, then published
only after the successful establishment result. Equal and empty updates remain
separate reports. A missing value, oversized update, changed association,
notification failure, exhausted credit/sequence or refusing sink closes the
generation with continuity loss; no unreported drop is success.

Acknowledgement is cumulative, nondecreasing and no greater than the last
successfully published sequence. Exact duplicate acknowledgement is inert;
regression, future sequence and foreign subscription refuse without increasing
credit. Retired streams retain their published, unacknowledged credit until
acknowledged; stop cannot free credit still held downstream. Unpublished early
values are discarded on failure/stop. There is no automatic acknowledgement at
pipe write or native callback return. The later Host/Client join must return
credit only after bounded final receiver admission or explicit retirement of
those exact records.

Permission/link/adapter/service/clock loss or control expiry retires all streams,
detaches delegates and releases native objects before publishing a pending
control failure. Failure or close retains actual confirmed/unconfirmed cleanup;
old delegates cannot publish into another owner. Sleep observation remains a
separate required lifecycle input.

| Case | Native notification falsifier |
| --- | --- |
| CB-N1 | Independent selector cases cover all property/mode combinations; unsupported/foreign/duplicate selections invoke no SDK toggle |
| CB-N2 | Start/stop use the exact SDK characteristic; matching state and original deadline are required before success |
| CB-N3 | Early/equal/empty/512-byte updates preserve owned bytes and ordering after establishment; no initial read is performed |
| CB-N4 | Exact/over credit, sixteen streams, future/regressing/duplicate acknowledgement and retired outstanding credit remain bounded |
| CB-N5 | Value/state errors, missing/oversized values, changed association/properties and sink refusal close the generation once |
| CB-N6 | Point reads cannot alias stream callbacks; writes and distinct-route reads retain their own exact result path |
| CB-N7 | Deadline equality, backward clock, permission/adapter loss and close during start/stop release objects before pending failure |
| CB-N8 | Retired/foreign callbacks, attempted route reuse and independent owners cannot create continuity or duplicate settlement |

`priv/fixtures/corebluetooth-notifications-v1.json` supplies twelve literal
property/mode outcomes and six control-state outcomes. The SDK fixture consumes
every cell through actual injected selectors; vector presence alone proves none
of these outcomes. The public Client/Runtime streaming join is specified below.

The [SDK notification record](../provenance/corebluetooth-notifications-2026-10.md)
binds the 24-case SDK corpus, 48 sanitizer component cases, owning fast gate and
archive/build checks to the exact committed inputs and their qualification limits.

## Native notification IPC

The revision-1 point handshake and point messages are unchanged. Notification
entry is explicit and additive: older hosts reject the unsupported operation,
and no stream report is sent to an ordinary point consumer. Requests retain
the existing strictly increasing decimal request IDs and original deadlines.
All notification objects require integer `stream_version: 1`.

`subscribe` parameters contain exactly `stream_version`, `address` (the existing
generation/route pair), `mode` (`auto`, `notify` or `indicate`) and integer
`credit` in 1..64. Successful result contains exactly `stream_version`,
`subscription_id` (the original request ID), `route`, `requested_mode`,
`effective_mode` and `credit`. Generation remains in the outer reply. The exact
discovery snapshot determines UUIDs and properties; acknowledgement cannot
substitute a route, mode or credit. A refused, unsubmitted start consumes no
native route; a submitted start consumes it for the generation.

`unsubscribe` parameters contain exactly `stream_version` and the original
`subscription_id`. The native SDK must confirm the disabled state. The Host
then emits a retirement control before its null success reply. That control
contains exactly `version`, `generation`, `stream_version`,
`event: notification_retired`, `subscription_id`, `route` and `last_sequence`.
It fences that stream, not other streams. No future callback may publish for
the retired identity. At most one point operation or stream establishment/stop
is active; another request receives busy. Whole-generation close still overtakes
active work. Acknowledgements have their own bounded control path.

Each report contains exactly `version`, `generation`, `stream_version`,
`event: notification`, `subscription_id`, `route`, `sequence` and the canonical
byte `value`. Sequences are increasing contiguous nonzero uint64 values per
stream. Empty/equal updates remain distinct. The SDK publishes establishment
before values; a Driver violating that order, a foreign identity, substituted
route, sequence gap, unsupported value or over-credit report retires the
generation without success. All emitted reports remain FIFO with replies and
retirement controls, including under partial writes.

The consumer sends an acknowledgement object with exactly `version`,
`generation`, `stream_version`, `event: notification_ack`, `subscription_id`
and `sequence`. It is not a request and does not consume a request ID or reply
slot. Acknowledgement may advance only through records actually transmitted to
stdout for that stream. Exact duplicates are inert; future, regressing, foreign,
wrong-generation and malformed acknowledgements terminate the generation before
credit reaches the SDK. Per-stream published/transmitted identity and a bounded
global output ordinal prevent acknowledgement of merely queued output. No pipe
write or callback automatically returns consumer credit.

The Host retains at most sixteen live streams, 64 shared reserved credits and
64 unacknowledged report records, including callback-inbox and output ownership.
A stopped stream retains its published unacknowledged credit. Route state is
bounded by the 256-entry discovery snapshot, not an unbounded lifetime registry.
Serialized SDK callbacks use a fixed 80-entry single-producer inbox;
the consumer drains at most 80 events per turn. Values reserve the shared
64-record budget before entering that inbox and release it only on validated
consumer acknowledgement or whole-generation disposal. Callback delivery never
waits for stdout or the Host output mutex. Overflow refuses and ends continuity.

Pending stream failures wait for native retirement and destruction before reply.
Late successful controls cannot renew their original deadline or survive close.
Cleanup exceptions remain unconfirmed. Native cleanup uses saturating deadline
arithmetic; a failing cleanup clock cannot extend native output draining.
The public Client/Runtime receiving join
must validate these exact bindings and return credit only after bounded final
receiver admission or explicit retirement of those exact records.

| Case | Native notification process falsifier |
| --- | --- |
| CB-W1 | Explicit start/stop, all mode/property cells, exact bytes/binding and point compatibility traverse independent Driver processes |
| CB-W2 | Early/foreign/gapped/over-credit Driver reports cannot publish success; valid empty/equal/max-size reports remain distinct |
| CB-W3 | Missing/duplicate/future/regressing/foreign/unsent acknowledgement never fabricates credit; stopped outstanding records remain reserved |
| CB-W4 | Busy, original deadline, late control, active close and cleanup refusal retain one result and actual retirement |
| CB-W5 | Concurrent serialized callbacks, unread stdout, fragmented input and multiple streams remain bounded without callback/output-lock contention |

The [native notification IPC record](../provenance/corebluetooth-notification-ipc-2026-10.md)
binds the committed source, independent Driver processes, production SDK adapter
join, sanitizer corpus and exact archive checks. Public Client/Runtime receiving
is specified below; sleep observation and installed-host qualification remain
separate obligations.

## Public notification receiving

The CoreBluetooth Client implements `subscribe/3` and `unsubscribe/2`; facade
sessions use the existing `Wotex.BLE.subscribe/2` and `unsubscribe/2` calls.
Subscription options contain exactly required `address` and optional `receiver`,
`mode`, `max_queue_length`, `value_type`, `byte_order` and `timeout`. Receiver
defaults to the caller and must be a local PID. Mode defaults to auto and follows
the native Apple policy above. Queue length is 1..10,000, default 1,000; codec
and timeout use the existing Procedure validators. A stream reserves the lesser
of sixteen and its queue limit. Sixteen live or establishing streams and 64
shared reserved credits include queued starts; local refusal sends no native
request. Exact UUID/generation/route selection preserves duplicate routes.

The subscription handle retains the actual connection generation and private
session reference. One original deadline spans queueing, native establishment
and public handle claim. The delivery owner monitors the establishing caller,
receiver and connection. The connection relays opening results itself, so an
exit cannot replace a specific native/timeout error with a monitor race. Early
reports stay within their reserved credit until the caller consumes its handle
reply and claims delivery; the opening reply does not consume a report slot.
Caller loss after native handoff or expired claim retires the generation.
Dead queued callers release unsent custody without dispatch. No synthetic
initial read or automatic acknowledgement occurs.

Reports require the exact closed native frame, generation, subscription, route,
next per-stream sequence and canonical 0..512-byte value. Delivery metadata has
exactly source `corebluetooth_value_update`, the complete discovered native
Characteristic map, requested mode and effective mode. Equal and empty updates
remain distinct. The source describes an SDK value callback, not independently
qualified ATT origin, authority, a physical effect or canonical Property truth.
Configured codecs run before delivery. Malformed values or receiver overflow
end delivery with at most one terminal error.

The BEAM ledger retains at most 64 report records. A private owner/token receipt
returns credit only after bounded selected-receiver mailbox admission; forged,
duplicate or foreign receipts create no credit. Only the consumed contiguous
prefix of each stream advances its cumulative acknowledgement. Cancellation
fences public delivery before requesting native stop. The exact ordered native
retirement barrier releases that stream's remaining discarded records before
the unsubscribe reply can succeed. Missing, changed or unsolicited barriers
cannot establish cleanup. Route reuse and reads on previously streamed routes
refuse for this generation; writes retain their separate evidence path.

An idle connection stops the selected stream without ending other streams. If
another native operation holds control, cancellation retires the entire
generation and preserves uncertainty for a submitted write. Abnormal delivery
owner loss also ends the generation. A dead delivery PID alone proves no native
cleanup: cancellation joins the connection's actual retirement. A generation
retains at most 256 exact retired handles, bounded by its discovery routes, for
idempotent cancellation; forged references cannot claim that receipt. Connection
cleanup keeps its 1,500 ms budget; the delivery owner allows 1,600 ms and the
public cancellation call 1,700 ms. A stopped connection supplies no new receipt.

The existing `:ble_gatt` Runtime profile accepts explicit CoreBluetooth options
and the exact configured URI target independently of the private Peer. Its relay
owns the connection; caller-supplied `owner` is rejected. Property observations
and Event subscriptions use the same native receiving path, a 64-frame opening
buffer and bounded Runtime-owner forwarding. Runtime metadata validation binds
the configured backend, native characteristic and requested/effective mode;
well-formed foreign routes are ignored and malformed metadata ends delivery.
CoreBluetooth relay cleanup has a 1,700 ms grace. No portable Form invents an
SDK route or private peripheral identity.

| Case | Public receiving falsifier |
| --- | --- |
| CB-R1 | Literal mode cells, duplicate routes, forged handles and exact stream binding cannot retarget delivery |
| CB-R2 | Equal/empty/max-size reports, per-stream sequence/credit and exact receiver receipts remain bounded |
| CB-R3 | Opening handoff, queued expiry, caller/receiver loss and sixteen-stream/shared-credit admission preserve original custody |
| CB-R4 | Missing/false retirement, stopped-route reuse, dead delivery owner and active-point cancellation cannot fabricate cleanup or unsent writes |
| CB-R5 | Real Runtime Property/Event streams preserve backend-specific metadata, codecs and joined cleanup |
| CB-R6 | Runtime owner loss, receiver overflow, malformed frames and private status cannot leak values or leave an unowned generation |

The [public receiving record](../provenance/corebluetooth-receiving-2026-10.md)
binds the committed implementation, independent process and production Host
cases, Runtime receiving, exact archive compilation and remaining qualification.
