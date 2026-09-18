---
spec:
  id: WBL.04
  title: "Complete BlueZ GATT central software profile"
  status: accepted
  version: 1.1.4
  owner: wotex-ble
  updated: 2026-09-17
---

# WBL.04 Complete BlueZ GATT central software profile

Read [WBL.01](WBL.01-library-contract.md) and the [implementation sequence](../plans/software-implementation.md).
[WBL.05](WBL.05-standalone-client-and-preservation.md) fixes the native API, protocol workflows and concrete fixture contract.
The accepted native backend is [WBL.07](WBL.07-native-backend.md). Current
pure APIs, persistent native D-Bus ownership, Runtime mapping and scoped virtual
BlueZ results are described separately in the implemented profile and provenance.
A scripted D-Bus response proves a boundary, not a GATT exchange.

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

The first-party `Wotex.BLE.BlueZ.Connection` owns a persistent C++17 libdbus
Port selected by `lifecycle: :persistent`. `executable` names that absolute native
binary; baseline one-shot busctl read/write has its separate documented mode.
The helper uses .13's pinned library, bounded event loop and C07 framing. One
private D-Bus connection owns discovery, Agent pairing and all GATT procedures;
StartNotify/StopNotify have the same unique sender throughout their lifetime.

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
calls Device1.Disconnect or starts pairing during open/close. Owned mode may call Device1.Connect,
wait for Connected and ServicesResolved within the absolute deadline, and call
Disconnect on cleanup only if this handle established the connection. A device
already connected when opened remains borrowed at the link layer. Concurrent
close callers join the same bounded cleanup result, with at most 64 waiting
callers; excess callers receive `:busy` without another native close attempt.

C03's 1000 ms grace releases library-owned processes, bus sender, listeners and
subscription/Agent state. For a link this owner established, it also bounds
submission of Device1.Disconnect; local close does not attest that BlueZ has
already disconnected the controller. Pinned BlueZ
[`device_request_disconnect` and `DISCONNECT_TIMER`](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/device.c)
schedule daemon-owned kernel disconnection with a two-second timer. The required
VM fixture measures sender/resource release within 1000 ms and separately
requires Connected=false within 3500 ms from close entry, recording both
latencies. Do not extend the library's cleanup grace, send privileged HCI
commands or disconnect a borrowed link to satisfy that separate drain assertion.

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

For a pending explicit Pair, cancellation rejects our pending Agent prompt and
unregisters only our Agent. If Pair completion remains unknown, close our unique
D-Bus sender and its session generation. Never call Device1.CancelPairing or
RemoveDevice: at the pinned revision, CancelPairing with no pending request can
issue an unpair command. BlueZ watches the Pair request's sender and can itself
disconnect the peer when that sender disappears. Consequently an explicitly
requested Pair may lose an otherwise borrowed link during cancellation; ordinary
borrowed discovery/open/close still sends no Device1.Disconnect. Preserve existing
bonds and make no claim that an unresolved Pair did not finish. This follows the
pinned [Pair sender and cancellation implementation](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/device.c)
and [unpair command implementation](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/src/adapter.c).

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

Read parameters have exactly `address`; write parameters have exactly `address`
and `value`. Address has exactly `service`, `characteristic`, `object_path`,
`handle`, and `generation`, with absent optional selectors represented by null.
UUID fields are normalized strings, and selectors use S01's bounds. Write value
and read result use the exact C07 bytes envelope; write success result is null.
Resolve the current peer's UUID associations and supplied selectors together;
multiple matches fail `:ambiguous_characteristic`, zero matches fail
`:address_mismatch`, and a stale supplied generation fails `:stale_discovery`.

Immediately before WriteValue, the bridge emits exactly `version: 1`, the
active write request `id`, and `event: "write_submitted"`. This is a phase marker,
not success or proof of effect. Accept it once for the current active write;
wrong IDs, duplicates, extra fields, or a read/other phase close the generation.
An acknowledged write result without this marker is invalid. A received typed
pre-submission rejection has `effect: :none` only when the native procedure
proved no WriteValue call occurred. Submitted failures have `effect: :unknown`.
Process loss or malformed output during an active write remains conservative
unknown even if the marker was not observed; a queued, never dispatched write
has no effect. Never retry either case automatically.

For this bridge only, C07 failure `error` additionally permits optional `name`.
It is at most 128 ASCII bytes, starts with `org.bluez.Error.`, and has nonempty
D-Bus identifier segments (ASCII letter/underscore followed by letters, digits,
or underscores). Preserve it only as `Error.details.dbus_name`; there is no
message-text field. All other unknown fields remain invalid, and `status`, when
present, remains numeric. The prefix is protocol-specific; the bounds are this
library's narrower limit over [D-Bus error-name syntax, revision 0.43](https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-names-error).
The [pinned BlueZ characteristic API](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst)
owns method signatures and named procedure failures.

On an ATT transaction timeout, BlueZ owns bearer invalidation. The wrapper
closes its affected session and requires an explicit new connection; it must
not keep issuing operations on a suspected failed bearer. A shorter local read
deadline cancels local work and closes this session generation to prevent late
response reuse. Cleanup does not imply that an in-flight ATT write was canceled.

## WBL-S04 — Notifications and indications

`subscribe(session, request)` includes concrete characteristic address,
`receiver`, `mode: :auto | :notify | :indicate` (default auto), and C05 queue bound.
The request map uses `address` for the concrete Address, with optional `receiver`,
`mode`, `max_queue_length`, `value_type`, `byte_order`, and `timeout`; reject other
keys. Each established subscription has its own monitored owner process. Its
opaque handle adds a redacted `session_reference` bound to the originating
connection generation. A foreign session reference fails before I/O, including
when the subscription owner is dead. Repeated cancellation of a well-formed,
already-dead same-session owner is idempotent under C05. Keep at most 64 active
subscriptions per connection and no lifetime tombstone registry.
Before StartNotify, install the Value PropertiesChanged listener on the exact
characteristic and BlueZ owner generation. Return the C05 handle only after
StartNotify succeeds. Buffer at most one early Value signal until then. A
second early Value fails establishment with `:response_limit` and cleans up;
never silently discard an arbitrary number of early reports. Emit the subscribe
acknowledgement before releasing the buffered value to the bridge output.

The native subscribe parameters are exactly `address` (S03 shape), `mode`
(`auto`, `notify`, `indicate`) and `queue_limit` (integer 1..10000). The latter
translates the public queue bound into .13 report-credit admission. The success result has exactly `subscription_id`
(the establishment request ID), `generation: 1` (this bridge owner's generation),
`characteristic` (S01's complete typed discovery record), `requested_mode` and
`effective_mode` (`notify`, `indicate`, `bluez_selected`). The characteristic's
own generation remains its discovery-snapshot identity; it is not the bridge
owner generation. Unsubscribe parameters are exactly `subscription_id` and its
successful result is null. Unsubscribe uses a separately correlated control
lane so an unrelated blocked read cannot postpone receiver cleanup. Data and
control requests share the 64-request admission bound. Failed or stalled
StopNotify closes this sender within C03's ownership cleanup grace.

Value envelopes have exactly .13's `session_generation` and `report_sequence`,
plus `version: 1`, `subscription_id`, `generation: 1`, `event: "value"`,
`value`, and `metadata`. The value uses the C07 bytes envelope and metadata with
exactly `source: "bluez_value_change"`, the established `characteristic`,
`requested_mode`, and `effective_mode`. Validate all bound metadata, not only the
subscription ID. Only value envelopes consume cumulative report credits.

A terminal error control has exactly `session_generation`, `version: 1`,
`subscription_id`, `generation: 1`, `event: "error"`, `value: null`, and
`metadata` with exactly `error`, using S03's bounded failure shape. It has no
`report_sequence` and consumes .13's separate finite control reservation. Deliver
at most one terminal error before that stream's retirement barrier in FIFO order.
Unknown or stale subscription IDs are never deliveries.

BlueZ StartNotify does not expose a procedure selector. If only notify or only
indicate is advertised, the requested matching mode or auto succeeds. If both
flags exist, require auto; explicit mode fails `:unsupported_procedure_selection`
before StartNotify. Do not promise an explicit indication choice that this API
cannot make. Record requested and effective mode (`:bluez_selected` for both)
in metadata. BlueZ performs CCCD handling and ATT indication confirmation;
never issue a second manual CCCD write or forged confirmation.

Accept only Value changes from the bound interface/path/sender and byte type.
Every bound signal is a new value-change report; D-Bus exposes no ATT sequence
identity for value-based deduplication. A successful ReadValue can also update
Value. Reports therefore carry source :bluez_value_change, not an assertion that
each signal originated in an ATT notification; see WBL-N02. No synthetic initial read is emitted as a notification.
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
This selector applies only to stream start/stop Forms; its presence on a Property
read/write Form fails `:invalid_selector` before acquisition.
For read/write conversion use `wotex:bleValueType` (`bytes` by default; otherwise
the S01 type names `uint8`, `int8`, `uint16`, `int16`, `uint32`, `int32`,
`uint64`, `int64`, `float32`, `float64`, `boolean`, `utf8`) and
`wotex:bleByteOrder` (`little` by default or `big`). These are library extensions,
not Bluetooth SIG or W3C terms. Reject invalid known values; preserve unrelated
extensions. The same decoder applies to subscribed byte values. An Event here carries a characteristic value change; it does
not claim a decoded SIG application profile. Pairing is explicit native control,
never a side effect of reading a Form. Runtime security requirements that BlueZ
cannot attest must fail as unsupported rather than treating Paired as proof of
a requested encryption/MITM level.

The `:gatt` Runtime profile requires the explicit first-party `client: Wotex.BLE.BlueZ`
and `lifecycle: :persistent` backend configuration. Its Transport rejects an
`owner` option because the relay owns the stream's native connection. The Transport
`max_queue_length` option bounds the relay/native delivery queues using C05's
1..10000 range and default 1000; it is removed before connection configuration.
The Runtime's final receiver mailbox bound remains a separate child-spec option.

Bridge operations are `open`, `discover`, `read`, `write`, `subscribe`,
`unsubscribe`, `pair`, `agent_reply`, `health`, `close`. Discover is a bounded
snapshot of the selected connected peer's GATT objects, not an unfiltered scan.
Return at most 64 objects per page, with an opaque generation-bound cursor;
object changes invalidate the cursor. Keep the complete bounded snapshot in
the bridge, and enforce C07 line size on each page.
Byte values use C07 base64 envelopes; paths/UUIDs/flags remain explicit strings
or finite enums. A stream report includes subscription ID, generation, bytes
and effective mode plus source `bluez_value_change`. A pairing challenge uses a separate typed event with a
unique challenge ID and deadline; replies must match that ID exactly once.

The pairing event envelope has exactly `version: 1`, the active Pair request
`id`, `event: "agent_challenge"`, and `challenge`. Its challenge map has exactly
`id`, `peer`, `kind`, `value`, and `timeout_ms`; peer has the same three string
fields as open, and kind/value use N01's finite types. `timeout_ms` is the
remaining native budget, never a foreign absolute clock reading. The BEAM owner
sets Challenge.deadline_ms from its own monotonic clock and the smaller of that
budget and its original Pair deadline. Only that active request, peer and
challenge can invoke policy. Agent configuration never enters the bridge.
`agent_reply` parameters are exactly `challenge_id` and `decision`; decision is
`{"action":"accept"}`, `{"action":"reject"}`, or `{"action":"pin" | "passkey",
"value": typed_value}`. The reply uses its own unique request ID and a null
success result. Dispatch this bounded control request while Pair is waiting;
never put it behind Pair in the serial operation queue. Unknown/duplicate prompt
IDs reject the pairing and cannot answer a later prompt.
`health_check/1` in persistent mode performs Properties.GetAll on the original
Device1 path and unique BlueZ sender. Revalidate Adapter/Address/AddressType and
the boolean Connected/ServicesResolved values; return exactly
`{:ok, %{connected: true, services_resolved: true}}` only when both are true.
The native `health` request has empty parameters and the same two string-keyed
booleans in its success result. Missing/malformed state fails `:invalid_response`,
changed identity fails `:peer_changed`, and false state fails `:disconnected`.
Baseline mode retains its probe-required error. Health does not imply that a
particular characteristic remains readable or attest encryption/MITM.

The pure `capabilities/0` baseline map remains compatible. Add
`capabilities(:oneshot | :gatt)`, returning `{:ok, map}` or
`{:error, %Error{code: :unsupported_profile}}` for every other selector.
`:oneshot` returns the baseline map. `:gatt` changes only `transport` to
`:bluez_dbus`, `supports_streaming`/`discovery_capable` to true, and `operations`
to `[:read, :write, :discover, :pair, :subscribe, :unsubscribe, :health_check]`.
The 512-byte value bound and conservative reliability/order/QoS fields remain.
This static backend declaration performs no probe and asserts no peer capability.
Device1 state meanings use the pinned
[BlueZ Device API](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Device.rst).

## Acceptance scenarios and software fixture

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

Pin BlueZ to `2123ab772fbe97d1369fc9e179ea87c3469cf98f` and production
libdbus 1.16.2 as .13. The independent GATT provider may use dbus-next 0.2.3
(source `74dc9706e8d0ebb17f27818b8ef9e214172514ec`), solely as a test peer. Build BlueZ with its test and
emulator tools. Use an isolated Linux VM with `CONFIG_BT_HCIVHCI` support and two virtual
LE controllers created by `btvirt -L -l2`; verify no physical HCI controller
is present before selecting fixture devices. Run a disposable private D-Bus and
bluetoothd, and a fixture GATT server with duplicate UUID instances, readable/
writable values and separate notify-only/indicate-only characteristics.

A distribution kernel that omits this driver may use its unmodified matching
`hci_vhci.c` built by [Kbuild](https://docs.kernel.org/kbuild/modules.html)
against the exact guest kernel headers, configuration and `Module.symvers`.
Record the source archive, driver source, configuration and module hashes plus
vermagic; load that module only in the disposable guest. Required `/dev/vhci`
and exactly two `/sys/devices/virtual/bluetooth/hci*` controllers remain runtime
assertions. A missing or mismatched driver fails the lane.

Capture actual server writes, active notification sessions and disconnects.
Inject permission/authentication failures in the fixture service and D-Bus
boundary; label each as service-policy or wire evidence. Missing VHCI, BlueZ,
peer or required response fails the selected software lane. An ordinary container
without kernel support is not an acceptable skipped pass. Physical radios are
unnecessary; virtual-controller evidence does not claim RF qualification.


## Native executable admission

Persistent native startup requires all four selectors: `executable` and
`executable_sha256` for the SDK host, and `guardian` and `guardian_sha256` for its
independent process guardian. Paths are absolute valid UTF-8 strings of at most
4096 bytes without NUL; hashes are exactly 64 lowercase hexadecimal characters.
Pure option validation performs no filesystem access. Both executable identities
must pass WBL.07 admission within the original startup deadline before either
process starts. The consumer keeps deployment files immutable through execution.
