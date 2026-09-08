---
spec:
  id: WMB.10
  title: "Complete Modbus TCP client software profile"
  status: accepted
  version: 1.0.0
  owner: wotex-modbus
  updated: 2026-09-09
---

# WMB.10 Complete Modbus TCP client software profile

Read [WMB.00](WMB.00-library-contract.md) first. This target contract closes the
software obligations of the existing eight-function TCP profile; it does not
turn this package into every member of the Modbus standards family. The baseline
at commit `0c2a7f4` already implements the main wire, conversion and Form paths.
The build work is boundary hardening, lifecycle/admission, compatibility and
complete software evidence. Tests passing at that commit are recorded in
[executable evidence](../provenance/executable-evidence.md).

## Revision and scope decision

Modbus Application Protocol V1.1b3 (2012-04-26), sections 4–7, and TCP/IP Guide
V1.0b (2006-10-24) govern this client. [WMB.01](WMB.01-protocol.md) and
[WMB.02](WMB.02-form-profile.md) define the existing profile. All normative links
and access limitations are in [primary sources](../provenance/primary-sources.md).

Required function codes are 1, 2, 3, 4, 5, 6, 15 and 16. A Modbus server, gateway,
RTU/ASCII serial driver, file-record services, native discovery, polling scheduler
and Modbus Security endpoint are outside this TCP profile. Keep unsupported
selectors explicit errors. A TLS tunnel must not be labelled a conformant Modbus
Security implementation: the separate Security v36 (2021-07-30) specification
also describes certificate and role handling. Do not add those transports as
unreviewed shortcuts while completing the defined profile.

## WMB-S01 — Address, command and conversion invariants

The [standalone/preservation contract](WMB.11-standalone-client-and-preservation.md)
defines exact helper results, compatibility message admission and concrete
fixture adapters. These obligations apply throughout S01–S04.

Public entry points remain `Address.new/3`, `Command.new/4`, `Value.encode/3`,
`Value.decode/3`, the named read/write helpers and `request/2`.
Wire offsets are zero-based 0..65535; ranges cannot cross 65536. Unicast units
are 1..247 or 255. Unit zero and reserved units remain rejected. Validity must
hold again when a forged `Address`, `Command` or `Session` reaches an encoder or
socket boundary. No bitstring truncation, implicit integer wrapping or arbitrary
atom coercion is permitted.

| Operation | Quantity/input | Native success |
| --- | --- | --- |
| Read coils/discrete inputs | 1..2000 bits | `{:ok, boolean_list}` |
| Read holding/input registers | 1..125 words | `{:ok, integer_list}` |
| Write single coil | Boolean or exactly 0/1 | `:ok` from the named/compatibility helper |
| Write single register | Integer 0..65535 | `:ok` |
| Write multiple coils | 1..1968 Boolean or 0/1 entries | `:ok` |
| Write multiple registers | 1..123 integers 0..65535 | `:ok` |

Typed values remain signed/unsigned 16/32/64-bit integers and finite IEEE754
32/64-bit floats. Byte and word order are explicit conversion options with unique known keys; TCP
register bytes are always big-endian. Exact width is required. Both signed zero
and all finite boundary values roundtrip; NaN/infinity are rejected. Booleans
and integers are not interchangeable outside the explicit coil convention.

## WMB-S02 — Wire validation

`Codec.decode/1` must preserve the complete-frame/unconsumed-tail contract. PDU maximum
is 253 bytes; TCP ADU maximum is 260. MBAP protocol ID is zero and length is
2..254, including Unit Identifier. Enforce the length before waiting for a body.
Each response must match transaction, unit and function. Reads validate exact
byte count and zero unused coil bits. Writes validate the full echoed address,
quantity or value. An exception has exactly function-or-0x80 plus one code byte;
unknown exception numbers remain structured remote failures.

No success is returned for an empty socket read, incomplete ADU, extra PDU bytes,
wrong echo or stale transaction ID. A framing/correlation failure closes the
session so a later request cannot consume the offending stream tail.

## WMB-S03 — Serialized connection lifecycle

Keep one socket owner and one active wire request. Implement the 64-call admission
bound, admitted-caller monitors and absolute deadline from WMB-C03. Allocate a
transaction ID only to admitted, non-expired work; never reuse an outstanding
ID. Wraparound is safe because only one request is active and failed sessions
close. An owner or active caller death during receive must initiate cleanup
without waiting up to 60 seconds. A canceled read may close the session; a
canceled write reports unknown effect and closes it. No automatic reconnect or
write replay is allowed.

`disconnect/1` succeeds repeatedly. A request after close returns
`:connection_closed`. If link establishment races with owner death, no unowned
socket survives. Child specifications must allow the consumer to select its own
supervision policy; there is no package supervision tree on dependency load.

## WMB-S04 — Forms, health and capability precision

The URI is `modbus+tcp://numeric-IP[:port]/unit/address?quantity=N`; default port
502 and default human address base one. `modv:zeroBasedAddressing=true` selects
wire offsets. Query keys and duplicates are rejected exactly as WMB.02 specifies.
Entity/function selection and explicit scalar widths cannot issue writes to
read-only entities. Unknown extensions roundtrip. `modv:timeout` and
`modv:pollingTime` do not start timers or authorize an infinite request; the
explicit finite Runtime timeout is authoritative.

`health_check/1` retains the documented register-zero compatibility probe and
can fail on a healthy server whose register zero is not readable. Its meaning
must stay explicit. Add `health_check/2` accepting a validated read Command for
consumers needing a different probe; writes are rejected as health probes.
Only an actual matching read response produces `{:ok, :healthy}`.
`receive/2`, `subscribe/2` and `unsubscribe/2` retain their unsupported behavior;
Modbus polling belongs to an explicitly chosen consumer scheduler.

Capabilities report the eight functions, TCP and security `:none`, with a 253-byte
PDU limit. Do not call that limit the complete TCP ADU size or imply every helper
accepts 253 payload bytes. Unsupported credentials/security fail before a socket
is opened. Runtime closes every scoped connection and preserves request identity.

## Acceptance scenario families

These IDs identify test families, not already executable vectors. Concrete
inputs and exact projected outputs are in the .11 fixture corpus; every family
still needs its complete boundary/fault expansion in executable tests.

| ID | Input or fault | Required observation |
| --- | --- | --- |
| WMB-V01 | Each quantity at 0, 1, maximum, maximum+1; offset+quantity 65536/65537 | Exact boundary success/error; invalid cases transmit nothing |
| WMB-V02 | Forge a Command after construction: function 256, negative unit/offset, mismatched quantity/value | Structured validation error; no truncation into a valid ADU |
| WMB-V03 | Every split of a representative ADU and two coalesced ADUs | `:more` until complete; exact retained tail; no duplicated bytes |
| WMB-V04 | Wrong transaction/unit/function, byte count, padding or write echo | Error and closed session; next call cannot consume old data |
| WMB-V05 | Exception code 1, known device failure, unknown 255, truncated/extra exception bytes | Numeric remote status retained only for exactly valid exception shape |
| WMB-V06 | All integer width edges; four byte/word order combinations; finite float and NaN/infinity encodings | Exact expected registers/value or explicit unsupported non-finite error |
| WMB-V07 | Active slow call, queued write with shorter deadline, caller death, 65th admitted call | Expired/dead queued work sends nothing; overflow is `:busy` |
| WMB-V08 | Owner death during blocked receive; startup failure at socket acquisition; repeated disconnect | WMB-C03 cleanup bounds; no surviving owned process/socket |
| WMB-V09 | Register-zero probe rejects; explicit readable probe succeeds; write probe supplied | Accurate health result; write probe sends nothing |
| WMB-V10 | Wrong Form operation/entity, credential, address base and unknown extension | No forbidden I/O; unchanged extension map; scalar width preserved |
| WMB-V11 | Pinned libmodbus peer exercises all eight functions, write/readback and remote exception | Actual asserted responses; missing peer fails |
| WMB-V12 | WMB-C09 stress, failure injection and minimum-version matrix | Complete correlation/cleanup evidence; no required software lane skipped |

Use the existing libmodbus v3.1.12 fixture at commit
`9af6c16074df566551bca0a7c37443e48f216289`. Extend its C fixture only to make
failure scenarios deterministic; malformed-wire tests remain separate from the
independent peer's standards behavior. No physical equipment is needed.
