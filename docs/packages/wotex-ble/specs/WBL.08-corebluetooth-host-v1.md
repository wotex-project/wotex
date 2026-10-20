# CoreBluetooth host v1

Version: 0.4.0. Updated: 2026-10-20. Status: accepted delivery contract.
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
pairing or radio behavior. The public Client, sleep observation, notification
receiving and Runtime/archive joins remain separate required host-delivery work.

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
flushes at most 65,536 bytes/64 attempts per turn. SDK callbacks enqueue through
a prompt nonblocking lock attempt; contention or output failure fences the
process. They never block waiting for stdout. Input/partial-input EOF, malformed
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
Runtime retains command `:accepted` status. The BlueZ streaming profile, manual
pairing interface and notification/sleep cells remain unsupported until their
own receiving/lifecycle delivery. Existing BlueZ/custom-client behavior is
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
