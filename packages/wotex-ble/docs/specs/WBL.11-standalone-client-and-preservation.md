---
spec:
  id: WBL.11
  title: "Standalone central and retained behavior"
  status: accepted
  version: 1.0.0
  owner: wotex-ble
  updated: 2026-09-09
---

# WBL.11 Standalone central and retained behavior

Specification version: `1.0.0`. Status: planned target, not implemented capability.
Requires [WBL.00](WBL.00-library-contract.md) and
[WBL.10](WBL.10-software-contract.md). The baseline remains documented in
[WBL.02](WBL.02-implemented-profile.md).

## WBL-N01 — A usable native central

The release floor is a first-party Linux GATT central that works without a
Thing Description, Wotex Runtime or a consumer-authored transport. The package
owns the typed public client and persistent BlueZ bridge; BlueZ owns the radio
protocol stack. Custom Client implementations are an extension seam and cannot
substitute for completing the supplied backend. No operation starts at dependency
load. The consumer explicitly supplies the peer, bus, supervision and pairing
policy. WoT mapping delegates to these same operations and owns no second session.

All functions below are on `Wotex.BLE` unless qualified. Public target additions
are documented here before implementation; existing `connect/1`, `send/2` and
`disconnect/1` retain their compatible baseline cells.

| API | Exact contract |
| --- | --- |
| `Peer.new(%{adapter: path, address: text, address_type: type})` | `{:ok, %Peer{}}` or Error; adapter is an absolute D-Bus object path, address is six colon-separated hex octets normalized uppercase, type is `:public` or `:random`; reject names and unspecified type |
| `connect(client: BlueZ, lifecycle: :persistent, peer: peer, connection: mode, bus_address: address, owner: pid, timeout: ms)` | `{:ok, %Session{}}` only after S02 ownership and ServicesResolved; explicit private/system bus address, no environment fallback; `mode` is `:owned` or `:borrowed` |
| `discover(session, options)` | `{:ok, %{generation: integer, characteristics: [Characteristic.t()], cursor: binary_or_nil}}`; options allow `cursor` and `limit` (default 64, 1..64) only; bounded connected-peer snapshot, no radio scan |
| `read(session, address, options)` | `{:ok, value}` or Error; options `value_type` (default `:bytes`), `byte_order` (default `:little`), `timeout`; raw bytes preserved when no codec selected |
| `write(session, address, value, options)` | `{:ok, :written}` only after acknowledged WriteValue; same codec/options; no readback or write-without-response fallback |
| `pair(session, request)` | `{:ok, %{paired: true}}` after the explicit Agent policy and Device1.Pair completion; S02 policy/request fields, no implicit pairing from reads |
| `subscribe(session, request)` | S04 request plus optional explicit `value_type`/`byte_order`; `{:ok, %Subscription{}}` only after StartNotify succeeds |
| `unsubscribe(session, subscription)` | C05 idempotent local closure, same sender StopNotify and listener cleanup |
| `health_check(session)` | `{:ok, %{connected: true, services_resolved: true}}` only from the persistent peer query; baseline one-shot remains probe-required |

`Characteristic.t()` has `service_uuid`, `characteristic_uuid`, `service_path`,
`object_path`, `handle` (integer or nil when absent), `flags` (bounded strings)
and `generation`. Sort the snapshot by service path then characteristic path;
keep unknown flags as bounded strings, never create atoms. Address resolution
requires UUID associations even when an object path is supplied. `Address.new/1`
adds optional `object_path` and `generation`; a generation from discovery must
match. An absent handle is not handle zero. Cursors are session/generation-bound,
expire on any GATT topology change, and fail `:stale_discovery` rather than silently
continuing against a new snapshot. A foreign cursor is `:invalid_cursor`.

Value codecs are the finite S01 set; `Value.encode(value, type, options)` and
`Value.decode(bytes, type, options)` return `{:ok, result}` or Error. `:boolean`
accepts only true/false and one 0/1 byte; wrong length, out-of-range numbers and
unknown codec options fail `:invalid_value` before D-Bus admission. A 16-bit UUID
is normalized to its Bluetooth base form, but never selects an application codec.

Pairing request fields are `capability`, `agent: {module, config}` and optional
`timeout`. The explicit trusted module implements
`Wotex.BLE.Agent.decide(Challenge.t(), config)`. Challenge fields are `id`,
`peer`, `kind`, `value` and `deadline_ms`; kind is `:confirm_passkey`,
`:request_passkey`, `:request_pin`, `:authorize_pairing`, `:authorize_service`,
`:display_passkey` or `:display_pin`. `value` is the integer for confirmation, `%{passkey: integer, entered: 0..6}`
for passkey display, PIN text for PIN display, canonical UUID for service
authorization, and nil for the remaining kinds. Inspect redacts it.
Decision is `:accept | :reject | {:passkey, 0..999999} | {:pin, binary}`; PIN is
1..16 printable ASCII bytes. Only a matching request kind accepts a value reply;
confirmation/authorization/display kinds require an explicit accept/reject.
Unsupported Agent methods or decisions reject pairing. Invoke the policy in a
monitored, deadline-bound worker so it cannot block bridge EOF or cancellation.
A crash/timeout rejects, unregisters this Agent and returns `:pairing_rejected`.
Display acknowledgement is not a claim of user confirmation or MITM security.

Cancellation follows S02's owned-sender rule: reject the pending Agent prompt,
unregister only this Agent, and close this session generation if Pair is still
unresolved. Device1.CancelPairing is excluded because the pinned implementation
can unpair after raced completion. BlueZ may disconnect an initially borrowed
peer when a pending Pair sender disappears; this is a consequence of the explicit
pairing operation, not permission for ordinary borrowed cleanup to disconnect.
No cancellation removes an existing bond or guarantees that Pair had no effect.

Stable D-Bus name mapping is part of the public contract: `NotConnected` becomes
`:disconnected`, `NotPermitted` becomes `:not_permitted`, `NotAuthorized` becomes
`:not_authorized`, `NotSupported` becomes `:not_supported`, `InProgress` becomes
`:busy`, `InvalidValueLength` becomes `:invalid_value_length`, `InvalidOffset`
becomes `:invalid_offset`, and `ImproperlyConfigured` becomes
`:improperly_configured`. `Failed` and unknown names become `:remote_error`.
Names carry the bounded `org.bluez.Error.` prefix in error details; arbitrary
message strings are discarded. S03 fixes the optional wire `error.name` field,
128-byte ASCII identifier limit, and sole public projection `details.dbus_name`. The local phase controls effect: validation
failure is `:none`; submitted write timeout/disconnect is `:unknown`, with no
library retry. Pairing Agent cancellation uses `:pairing_rejected`; connection
loss remains `:disconnected` even during pairing.

## WBL-N02 — Preservation and corrected semantics

| Useful asset/behavior | Required disposition | Proof owner |
| --- | --- | --- |
| Service/characteristic addressing, read and acknowledged write | Retain typed API; replace assumed target paths with live GATT association validation | P01/P02/P04, F01–F05, V03/V05 |
| Notification and indication scenarios | Retain both scenarios on separate peer characteristics; implement one persistent sender and receiver lifetime | P05/P07, F06–F08, V07–V09/V11 |
| Simulator fixtures | Retain deterministic scenarios as injected tests; replace simulator-only transport with real BlueZ virtual-controller GATT | P07; no simulator capability reported as production |
| Slash-delimited topic convenience | Add pure `Address.from_topic/1` returning `{:ok, Address.t()}`; require exactly two valid UUIDs; malformed input fails `:invalid_address`, never defaults to zero UUIDs | P01, F05 |
| Generic health, reliability and QoS claims | Replace with selected-backend capabilities and actual peer-state query; no exactly-once or application-effect claim | P06/P08 |

BlueZ's cached Value can change after a read as well as a notification or
indication. Therefore every delivered S04 value carries `source:
:bluez_value_change`, requested/effective mode and the bound characteristic
identity. The public stream makes no packet-origin guarantee. Equal consecutive
signals remain two reports; a concurrent read is not a reason to suppress a
signal heuristically. The implementation emits no synthetic initial read. A
read-caused change must not be relabelled as proof of an ATT notification.
This limitation follows the pinned
[GattCharacteristic1 Value and StartNotify API](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst).

## WBL-N03 — Required complete software workflow

The P07 fixture starts two virtual LE controllers, private bluetoothd and D-Bus
with no physical HCI device. The peripheral exposes a private test service with
read/write, notify-only and indicate-only characteristics, plus two duplicate
UUID instances. Public API tests must discover and disambiguate them, read exact
bytes `3412`, decode `:uint16` as 4660, acknowledged-write `7856`, and independently
read back 22136. Test data is a package fixture, not a SIG profile claim.

Subscribe to notify-only and indicate-only targets in separate tests. The peer
changes `01` twice; retain both reports, with exact path and source metadata.
Cancellation must leave zero sessions owned by that sender, while a second
independent sender remains subscribed. Indication confirmation is observed at
the virtual peer/BlueZ boundary; the BEAM wrapper never manufactures it. A wrong
path/sender and an old generation deliver zero reports. Add read-caused Value
changes to prove the metadata limitation above. A GATT denial and disconnect
must fail rather than return the last cached value.

Pairing tests use a disposable peer and an explicit decision callback: accept,
reject, timeout and wrong challenge ID. Inspect Agent registration count and
native session count after owner death. Complete this workflow through the
native API first, then the equivalent supported WoT cells. Neither a scripted
D-Bus response nor an ExUnit fake replaces the virtual-controller lane. Pins
remain BlueZ `2123ab772fbe97d1369fc9e179ea87c3469cf98f` and dbus-next 0.2.3.

## WBL-N04 — Concrete corpus and executable acceptance

[contract-v1.json](fixtures/contract-v1.json) is fixture format `1.0.0` with
status `specified_unexecuted`. It contains concrete examples; the broader Vxx
rows in .10 are scenario families. Neither a scenario row nor parseable JSON
counts as an executed test. All Vxx alternatives and boundaries still need tests.

Each case has a unique `id`, `requirements`, `kind`, `operation`, `input`, and
`expectation`. The expectation uses `operator: "exact"` over a normalized
observation. Pure runners call the named public operation with only `input`;
expectations must never be handed to the implementation or its client adapter.
`bytes_hex` represents exact bytes with lowercase even-length hexadecimal.
Atoms become their names, tuples become arrays, maps have string keys, struct
module names are omitted, and integers retain full precision. A success projects
to `{"ok": value}`; an error projects only the listed stable `code`, `field`
when specified, and `effect`. Unlisted error fields are not asserted by that
fixture; C04 separately requires their type, boundedness and redaction. Byte
values inside output use `{"bytes_hex": "..."}`, never guessed UTF-8.

Lifecycle cases inject the ordered input `events` at explicit relative `at_ms`
using a controllable clock and a scripted backend. An event at the same time
runs in list order. Symbolic handles such as `bus-1`/`sub-1` identify distinct
resources in this test only. In BLE lifecycle inputs, `sender` identifies the
BlueZ service's signal source, while `client_sender` identifies the distinct
application connection that calls StartNotify and StopNotify. Trace and compare
these roles independently. The observation consists of ordered deliveries,
terminal results and backend call/resource counters listed in the expectation.
The runner must inspect real owner state and recorded backend calls to produce
that observation; it must not reproduce the expected state machine inside the
assertion. The trace is an injected contract test, not interoperability evidence.

Add `test/wotex/ble/contract_fixture_test.exs` during P01 and bind each pure
case as its API becomes available; add lifecycle cases in their owning package.
A case without an implementation remains explicitly unexecuted and prevents
accepting its package. Do not check in an always-skipped test or count an ID in
a comment as proof. Final evidence records case ID, fixture SHA-256, executable
test path, command, source revision and result. The selected runner must fail on
unknown fixture format/operation, missing assertion, mismatched output or absent
required peer. Native software workflows below require separate real peer tests.
