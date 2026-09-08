# WBL.10 Complete BlueZ GATT central software profile

Read [WBL.00](WBL.00-library-contract.md) and the [implementation sequence](../plans/software-implementation.md).
Baseline `cb56121` provides UUID/address/value helpers, Forms and a bounded
one-shot `busctl` ReadValue/acknowledged WriteValue adapter. Persistent central
ownership, live target verification, notifications and software GATT peers remain
requirements. A fake D-Bus response proves the parser, not a GATT exchange.

## Scope and implementation choice

Bluetooth Core 6.3, Vol 3 Parts F/G and pinned BlueZ D-Bus APIs are recorded in
[primary sources](../provenance/primary-sources.md). Required platform is Linux
BlueZ, with an explicitly selected adapter and peer. BlueZ owns HCI, GAP, ATT,
GATT, MTU negotiation, link security, prepared-write execution and indication
confirmation. This package owns target selection, procedure selection, bounded
D-Bus calls, value conversion and subscription lifecycle. No second ATT stack.

Peripheral/server roles, arbitrary HCI commands, mesh, L2CAP channels, scanning
without explicit filters, acquired-fd streaming and cross-platform transports are
outside this profile. BlueHeron is not an implicit fallback. Physical RF testing
and Bluetooth qualification are separate from the required software GATT lane.

Implement a persistent first-party `Wotex.BLE.BlueZ.Connection` and Python
bridge using dbus-next 0.2.3. Select it explicitly with `lifecycle: :persistent`
on the BlueZ adapter; keep baseline one-shot operation for its documented
read/write compatibility cells. A new bridge version uses WBL-C07. The bridge
owns one D-Bus MessageBus connection and asyncio loop for its entire lifetime.
StartNotify and StopNotify must use that same unique D-Bus sender. Launching a
new busctl process for each notification call cannot satisfy this contract.

## WBL-S01 — Identity and procedure validation

Keep `Address.new/1` for service/characteristic UUID and optional handle.
Add `Peer.new/1` holding explicit adapter object path, canonical six-octet peer
address and address type `:public | :random`. No identity is inferred from a
friendly name. Normalize 16/32-bit UUID text to 128-bit Bluetooth base UUID;
handle is 1..65535. Preserve service instance and characteristic object path.

Enumerate ObjectManager.GetManagedObjects and validate Device1, GattService1
and GattCharacteristic1 associations. Check actual UUID, Device, Service,
Handle when supplied, and Flags before each operation or after cache generation
change. At most 4096 objects and 1024 services/characteristics per peer, 512 bytes
per value, 4096 bytes per object path. Duplicate matching characteristic UUIDs
are `:ambiguous_target` unless the explicit object path/handle disambiguates them.
Never accept an arbitrary path merely because its string starts with the peer path.

Keep values as bytes unless an explicit codec is selected. New `Value.encode/3`
and `decode/3` support signed/unsigned 8/16/32/64-bit integers, finite float32/64,
Boolean encoded as exactly one 0/1 byte, UTF-8 and opaque bytes. Integer/float
byte order defaults to little-endian and is an explicit codec option. Exact
width is mandatory; strings cannot exceed the 512-byte attribute ceiling.
There is no UUID-to-unit/value-format database guessed from characteristic names.

## WBL-S02 — Connection and pairing lifecycle

Persistent open requires `peer`, `connection: :borrowed | :owned` (default
borrowed), and the explicit D-Bus address/socket configuration. Borrowed mode
requires an already connected Device1 with ServicesResolved true; it never
disconnects the device or alters pairing. Owned mode may call Device1.Connect,
wait for Connected and ServicesResolved within the absolute deadline, and call
Disconnect on cleanup only if this handle established the connection. A device
already connected when opened remains borrowed at the link layer.

Install PropertiesChanged, InterfacesRemoved and NameOwnerChanged listeners
before checking initial state, then reconcile the snapshot so no state-change
race is lost. BlueZ owner change, device/service removal or disconnection closes
the generation and fails pending work. No automatic reconnect, rediscovery
retargeting, pairing, adapter power change or daemon startup. Connect failure
unwinds listeners and the bus connection without taking down the system daemon.

Pairing is a separate explicit native `pair(session, request)` operation.
Request selects `capability: :no_input_no_output | :display_yes_no | :keyboard_only`
and a caller-owned Agent callback, with the C03 finite deadline. Register an
Agent1 for this bus sender, forward the exact peer and challenge to the callback,
and wait for explicit acceptance/passkey. Never auto-accept confirmation,
authorization or a PIN. NoInputNoOutput still requires an explicit configured
policy callback for requests. Agent cancellation/timeout rejects the pairing and
unregisters the Agent. Do not remove an existing bond during cleanup. Credentials
and pairing challenges never enter logs/telemetry. Pairing is not a claim that
every characteristic is authorized or that MITM protection was achieved.

## WBL-S03 — Read and acknowledged write

ReadValue uses offset zero and empty options except explicit documented security
requirements; values must be bytes at most 512. WriteValue uses `type: "request"`
and offset zero. The characteristic must advertise the corresponding read/write
flag. No silent switch to a write command without response. Successful D-Bus
completion is acknowledged protocol completion, not canonical device state.
Long values rely on BlueZ's documented procedure; errors remain failures and
must not trigger a second partial write or manual execute retry.

Serialize requests for a session; BlueZ owns per-bearer ATT scheduling. Honor
WBL-C03 admission/deadlines. Map finite known D-Bus names (NotConnected,
NotPermitted, NotAuthorized, NotSupported, InProgress, InvalidValueLength,
InvalidOffset, Failed) to stable library codes; retain the bounded D-Bus error
name, never the arbitrary message text. Unknown names map to `:remote_error`.
An expired or canceled write after submission has unknown effect.

On an ATT transaction timeout, BlueZ owns bearer invalidation. The wrapper
closes its affected session and requires an explicit new connection; it must
not keep issuing operations on a suspected failed bearer. A shorter local read
deadline cancels local work and closes this session generation to prevent late
response reuse. Cleanup does not imply that an in-flight ATT write was canceled.

## WBL-S04 — Notifications and indications

`subscribe(session, request)` includes concrete characteristic address,
`receiver`, `mode: :auto | :notify | :indicate` (default auto), and C05 queue bound.
Before StartNotify, install the Value PropertiesChanged listener on the exact
characteristic and BlueZ owner generation. Return the C05 handle only after
StartNotify succeeds. Buffer at most one early Value signal until then.

BlueZ StartNotify does not expose a procedure selector. If only notify or only
indicate is advertised, the requested matching mode or auto succeeds. If both
flags exist, require auto; explicit mode fails `:unsupported_procedure_selection`
before StartNotify. Do not promise an explicit indication choice that this API
cannot make. Record requested and effective mode (`:bluez_selected` for both)
in metadata. BlueZ performs CCCD handling and ATT indication confirmation;
never issue a second manual CCCD write or forged confirmation.

Accept only Value changes from the bound interface/path/sender and byte type.
Every signal is a new report; D-Bus exposes no ATT sequence identity for
value-based deduplication. No synthetic initial read is emitted as a notification.
Notifying false, service removal, owner change and device loss terminate the
subscription. At most one active subscription per characteristic per session;
duplicate subscribe is `:already_subscribed`. Native subscriptions across
different sessions remain separate D-Bus senders.

StopNotify on the original sender/path when canceling. Once StopNotify completes,
remove the listener before acknowledging local closure. On failure, close the
owned D-Bus connection to release its notification session and report the failure.
Receiver death/overflow uses the same cleanup. A late Value callback cannot
deliver after closure. Do not stop another sender's notification subscription.

## WBL-S05 — Runtime, capabilities and bridge schema

Retain the existing package-defined Form URI and extensions; it is not a W3C
Bluetooth standard. Property read/write map to S03. Property observation and
Event subscription map to S04, with explicit requested mode in the profile
extension `wotex:bleMode`, with values `auto`, `notify`, `indicate`.
For read/write conversion use `wotex:bleValueType` (`bytes` by default; otherwise
the S01 type names `uint8`, `int8`, `uint16`, `int16`, `uint32`, `int32`,
`uint64`, `int64`, `float32`, `float64`, `boolean`, `utf8`) and
`wotex:bleByteOrder` (`little` by default or `big`). These are library extensions,
not Bluetooth SIG or W3C terms. Reject invalid known values; preserve unrelated
extensions. The same decoder applies to subscribed byte values. An Event here carries a characteristic change notification; it does
not claim a decoded SIG application profile. Pairing is explicit native control,
never a side effect of reading a Form. Runtime security requirements that BlueZ
cannot attest must fail as unsupported rather than treating Paired as proof of
a requested encryption/MITM level.

Bridge operations are `open`, `discover`, `read`, `write`, `subscribe`,
`unsubscribe`, `pair`, `agent_reply`, `health`, `close`. Discover is a bounded
snapshot of the selected connected peer's GATT objects, not an unfiltered scan.
Return at most 64 objects per page, with an opaque generation-bound cursor;
object changes invalidate the cursor. Keep the complete bounded snapshot in
the bridge, and enforce C07 line size on each page.
Byte values use C07 base64 envelopes; paths/UUIDs/flags remain explicit strings
or finite enums. A stream report includes subscription ID, generation, bytes
and effective mode. A pairing challenge uses a separate typed event with a
unique challenge ID and deadline; replies must match that ID exactly once.
`health_check/1` in persistent mode checks current Device1 Connected and
ServicesResolved; baseline mode retains its probe-required error. Health does
not imply that a particular characteristic remains readable.

## Acceptance vectors and software fixture

| ID | Scenario | Required result |
| --- | --- | --- |
| WBL-V01 | UUID short/long, handle edges, forged address, duplicate UUID instances | Exact normalization or explicit ambiguity; no wrong target |
| WBL-V02 | Codec widths/orders, UTF-8, 512/513 bytes, null/missing, non-finite floats | Exact bytes/value or pre-I/O error |
| WBL-V03 | Snapshot/listener race, wrong Service/Device/UUID/Handle/Flags | Live association validated; unrelated object cannot be used |
| WBL-V04 | Borrowed/owned/already-connected open, failed ServicesResolved, owner death | Only acquired resources/link released; daemon and borrowed link survive |
| WBL-V05 | Read/write success, each D-Bus error, timeout after write, long value failure | Acknowledged result or stable error; no retry/command fallback |
| WBL-V06 | Agent confirm/reject/passkey/cancel/timeout/wrong challenge | Explicit exact-peer decision; no automatic acceptance or leaked Agent |
| WBL-V07 | Notify-only, indicate-only, both flags with explicit mode/auto | Supported procedure or pre-I/O selection failure |
| WBL-V08 | Early Value, repeated equal value, wrong path/sender, Notifying false | Fresh bound signals only; terminal once |
| WBL-V09 | Cancel failure/double/foreign, receiver overflow/death, BlueZ restart | Same-sender cleanup; no stale delivery or leaked notification session |
| WBL-V10 | Runtime Property/Event applicability, unsupported security, extensions | Correct mapping and no false security claim |
| WBL-V11 | Real BlueZ central against virtual-controller GATT peripheral | Read/write/readback, notifications and indications actually traverse GATT |
| WBL-V12 | C09 stress/admission/matrix plus bridge EOF/log/corrupt-line faults | Bounded native/D-Bus/BEAM cleanup and no false success |

Pin BlueZ to `2123ab772fbe97d1369fc9e179ea87c3469cf98f` and dbus-next 0.2.3
(source `74dc9706e8d0ebb17f27818b8ef9e214172514ec`). Build BlueZ with its test and
emulator tools. Use an isolated Linux VM with CONFIG_BT_VHCI and two virtual
LE controllers created by `btvirt -L -l2`; verify no physical HCI controller
is present before selecting fixture devices. Run a disposable private D-Bus and
bluetoothd, and a fixture GATT server with duplicate UUID instances, readable/
writable values and separate notify-only/indicate-only characteristics.

Capture actual server writes, active notification sessions and disconnects.
Inject permission/authentication failures in the fixture service and D-Bus
boundary; label each as service-policy or wire evidence. Missing VHCI, BlueZ,
peer or required response fails the selected software lane. An ordinary container
without kernel support is not an acceptable skipped pass. Physical radios are
unnecessary; virtual-controller evidence does not claim RF qualification.
