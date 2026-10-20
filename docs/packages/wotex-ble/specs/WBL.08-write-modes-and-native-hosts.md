# WBL.08 — Explicit write modes and native host parity

Version: 0.3.0. Updated: 2026-10-20. Status: accepted target.
Implementation: partial; explicit BlueZ modes and native queue evidence are
implemented. CoreBluetooth and installed-host qualification remain open.

## Scope and operations

This additive generic GATT contract covers explicit write modes and a separately
selected CoreBluetooth host. Vendor commands and consumer authority stay outside
this package. Existing acknowledged BlueZ operations keep their current default.

**WBL08-01.** The successor write operation selects `:with_response` or
`:without_response`. Unknown/duplicate mode rejects; a missing mode preserves
the existing acknowledged default. Validate characteristic identity/generation,
supported property, payload/MTU bounds, security, link and one original deadline
before queueing. An unsupported backend/mode refuses without fallback.

With-response results attribute an actual ATT response/error. Without-response
results distinguish native queue acceptance, refusal and delivery uncertainty;
they never fabricate an ATT acknowledgement or physical completion. Independent
read/report evidence is a separate consumer decision. Native IPC and Runtime
mapping retain mode, original request and evidence class end to end.

**WBL08-02.** Readiness/backpressure and queue bounds share the original
deadline. Pre-acceptance cancellation/disconnect prevents new unsent work;
post-acceptance loss retains uncertainty without replay or mode substitution.
Late callbacks cannot settle a successor connection/request generation.

## Host and lifecycle

**WBL08-03.** Select BlueZ or CoreBluetooth explicitly through public
consumer-supplied configuration. Loading the package starts no host, permission
prompt or discovery. The consumer supervises permission, pairing/security,
discovery, writes, subscriptions, cancellation and retirement. A macOS backend
does not require Linux dependencies merely to load it.

Native peripheral identifiers are private host-route identities, not portable
device IDs or authentication. Validate service/characteristic association for
the current host/link generation. Unsupported security/pairing/long-write cells
reject under an explicit backend capability matrix.

**WBL08-04.** Sleep, permission denial/revocation, adapter reset and link loss
close pending routes and report continuity loss. Reconnect supplies a new
generation/baseline, not a synthetic event or fresh restored value. Finite receive
credits/queues stop on owner death. Retirement requires actual owned native
resource cleanup; OTP timeout alone is insufficient. Private identities and
credentials never enter public errors, telemetry or portable profiles.

## Compatibility, entry and acceptance

### Frozen BlueZ write interface

`Wotex.BLE.write/4` accepts the duplicate-free option `write_mode` with exactly
`:with_response` or `:without_response`; omission selects `:with_response`.
The low-level write message carries that same optional atom-keyed member.
Reads reject it. The package Form extension `wotex:bleWriteMode` accepts exactly
`with_response` or `without_response`, applies only to Property writes and
defaults to `with_response`. It is not a W3C field. Existing acknowledged
messages, replies and Forms preserve their current representation.

With-response success remains `{:ok, :written}`. Without-response success is
exactly `{:ok, %{write_mode: :without_response, evidence: :native_queue_accepted}}`.
Runtime retains that complete value as its Result payload with status `:accepted`.
A null/`:written`
response cannot settle a command. Neither result establishes canonical state
or physical completion. Wrong/duplicate options, malformed result fields and
unsupported selectors refuse; there is no command/request substitution.

The persistent BlueZ host adds the closed version-1 operation `write_command`,
with the same exact `address`/`value` parameters as `write`. Its success result
is exactly `{"write_mode":"without_response","evidence":"native_queue_accepted"}`.
Old peers reject the unknown operation. Existing `write` still requires the
`write` flag and the request procedure. `write_command` requires the distinct
`write-without-response` flag and sends precisely `type: "command"` and uint16
`offset: 0` to WriteValue. Its normal empty D-Bus reply establishes only native
queue acceptance. Both operations use the existing correlated `write_submitted`
event and shared queue, deadline, cancellation, retirement and uncertainty rules.

Before admitting a command, refresh and validate the characteristic's explicit
uint16 MTU in 23..517. Missing MTU refuses `not_supported`; malformed MTU refuses
`invalid_characteristic`. Its payload is at most `min(512, MTU - 3)` bytes;
over-bound commands refuse `invalid_value_length` before the submission event
or WriteValue call. MTU changes invalidate discovery generation. No implicit
MTU, fragmentation, long command or retry is allowed.

| Explicit backend | With response | Without response |
| --- | --- | --- |
| Persistent BlueZ | Existing acknowledged procedure | Explicit command with current flag/MTU and native queue evidence |
| One-shot busctl | Existing acknowledged procedure | `not_supported` before process invocation |
| CoreBluetooth | Target only; no implementation claim | Target only; no implementation claim |

The [pinned BlueZ characteristic API](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst)
owns the native command/request and MTU property vocabulary. It does not qualify
an installed controller or its radio behavior.

The interface above freezes BlueZ option/result/error and IPC entry. Before
CoreBluetooth implementation, freeze its exact native capability/security
matrix, IPC and independent vectors. Old IPC peers
reject new formats rather than ignoring mode. Historic BlueZ software evidence
does not qualify macOS permissions or physical GATT/RF operation.

The [CoreBluetooth delivery contract](WBL.08-corebluetooth-host-v1.md) freezes
the explicit-clock operation port, per-mode size/readiness checks, callback
identity and retirement boundary. That native operation component has an
independent fourteen-case scripted-port corpus. Its implementation does not
instantiate or supply the SDK adapter, host process or public Client; those
remain required before the CoreBluetooth row above can claim support.

### Independent archive entry

`bin/check_archive.exs --write-mode-consumers` builds one exact core/Runtime/BLE
archive cohort and creates separate wire and Runtime consumers, each with its
own extracted dependencies (`env: :prod, override: true`), build and lock.
Inherited sibling, Mix build/dependency and Erlang library paths are cleared.
The ordinary archive check remains unchanged without the flag.

Each consumer first checks public module origins and passive loading in a fresh
VM, then runs five behavioral cases through public APIs. The wire family uses
an independently written bounded Elixir process peer through the archive's
compiled custody guardian. It checks mode/bytes, pre-dispatch refusal, legacy
and malformed replies, original queued deadlines and separate owned instances.
The Runtime family uses its own explicit Client/credential ports and checks
mode, payload/status, selector refusal, malformed evidence and independent
requests. Neither family imports production protocol/validation helpers.

Each family catches two isolated semantic mutations through assertions with
zero harness errors: command-to-request substitution and fabricated queue
evidence for the wire family; lost accepted status and ignored read-selector
applicability for Runtime. Missing/duplicate result markers, skipped cases,
compiler failures, surviving mutations and incomplete cleanup fail the lane.
Record archive, source, guardian, interpreter and lock identities and actual
counts. The parent removes all owned projects, builds and artifacts on success
or failure. These peers establish archive/software behavior, not real BlueZ,
CoreBluetooth, installed controller or physical qualification.

The [executed archive record](../provenance/write-mode-archives-2026-10.md)
binds both passive-loading cases, ten behavioral cases and four assertion-only
mutation catches to exact source/archive/launcher/guardian/lock identities.
This closes the BlueZ archive portion of WBL08-T5; its CoreBluetooth and
installed-controller portions remain open.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WBL08-T1 | 01 | Independent response/command peers observe the selected mode; command acceptance supplies no fabricated ACK |
| WBL08-T2 | 01–02 | Wrong property/MTU/mode/route, deadline, saturation and pre-send cancellation send nothing |
| WBL08-T3 | 02, 04 | Post-accept loss, late callback and reconnect preserve uncertainty; no resend or stale settlement |
| WBL08-T4 | 03–04 | Installed Mac permission/sleep/readiness/notification/owner-death/retirement corpus passes; existing Linux corpus is preserved |
| WBL08-T5 | 01–04 | Independent Runtime/archive peers retain mode/evidence and reject incompatible IPC without consumer-specific mappings |

WBL.02 owns the protocol baseline. The [Apple write-mode interface](https://developer.apple.com/documentation/corebluetooth/cbcharacteristicwritetype)
supplies native API vocabulary, not actuator qualification.
