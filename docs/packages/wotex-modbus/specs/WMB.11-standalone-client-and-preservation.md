---
spec:
  id: WMB.11
  title: "Standalone client and feature preservation"
  status: accepted
  version: 1.1.0
  owner: wotex-modbus
  updated: 2026-09-09
---

# WMB.11 Standalone client and feature preservation

Specification: `WMB.11@1.1.0`. This is the standalone behavior contract.
Requires [WMB.00](WMB.00-library-contract.md) and
[WMB.10](WMB.10-software-contract.md). The implemented helpers and their exact
assertions are recorded in [executable evidence](../provenance/executable-evidence.md).
Native Mix orchestration has separate .13 acceptance.

## Library boundary

This package must be usable as a Modbus TCP client without constructing a Thing
Description, a Form, a Runtime Request, or a consumer framework. Its standalone
product is a bounded TCP session, all eight listed function operations, exact
register conversion, and inspectable failures. The native API owns wire encoding,
correlation, stream admission and cleanup. WoT mapping translates Wotex values
into that same API; it must not contain an alternative protocol implementation.

The Wotex HTTP and MQTT packages deliberately own binding adaptation only. Their
no-client boundary is not this package's scope. The shared pattern to inherit is
explicit ownership, immutable public values, pure mapping, exact operation cells,
versioned specifications and evidence attached to claims. Loading this package
still starts no process. Native client examples must work with only explicitly
opened resources and without a Runtime process.

Modbus does not define engineering units or multi-register float layout. The
consumer supplies a device register map and conversion options. Do not infer a
temperature scale, register family, byte order, address base, or read permission
from a number such as `40001`. A reusable typed client is valuable without
inventing a universal device schema, discovery mechanism or polling service.

## WMB-D01 — Preserve the complete useful native surface

The following table is a preservation requirement, including features already
implemented. New internals may replace old machinery only while maintaining
these successful results and the stronger negative behavior in WMB.10.

| Useful asset | Required disposition and owning API | Proof obligation |
| --- | --- | --- |
| Four read helpers | Retain `read_coils/3`, `read_discrete_inputs/3`, `read_holding_registers/3`, `read_input_registers/3` | Exact function code, unit, offset, quantity and returned list for each helper |
| Four write helpers | Retain `write_coil/3`, `write_holding_register/3`, `write_coils/3`, `write_holding_registers/3` | Exact echo validation; `:ok` only after matching acknowledgment; each write independently read back |
| Float convenience functions | Retain `read_float/2` and `write_float/3` | Holding registers, two words, float32, big byte and word order; no hidden scale |
| Pure protocol assets | Retain `Address`, `Command`, `Codec`, `Value` | Independently usable with no socket, environment, clock or random source |
| Message-shaped compatibility calls | Retain `send/2` dispatch through `Command.new/4` and `request/2` | Same valid operation results as named helpers; malformed maps never escape validation |
| Session and health behavior | Retain explicit `connect/1`, `disconnect/1`, register-zero `health_check/1`; add explicit `health_check/2` | Owned cleanup and configurable actual read probe, including a healthy peer rejecting register zero |
| Connection recovery attempts | Replace implicit retry/reconnect with finite caller-controlled startup and terminal failed sessions | No second connection or write replay after uncertain effect |
| Receive/subscription callbacks | Preserve explicit unsupported outcomes | No fabricated queue, observation, native Event or polling process |

The eight named helpers and float helpers are present. Their existence
is not new implementation work; closing their malformed-input, lifecycle and
independent-peer evidence is. Compatibility refers to the declared values and
outcomes, not preservation of unvalidated input handling or unsafe retry policy.

## WMB-D02 — Exact native contracts

All names in this section are under `Wotex.Modbus` unless qualified. Constructors
return `{:ok, value}` or `{:error, %Error{}}`. Consumers must not rely on a struct
constructor bypassing validation: public operations revalidate forged values.

| Call | Inputs | Success |
| --- | --- | --- |
| `connect(options)` | Explicit numeric `host`; `port` defaults 502; `unit_id` defaults 1; finite `timeout` defaults 5000 ms | `{:ok, %Session{pid: pid, unit_id: unit, timeout: timeout}}` after successful socket ownership |
| `Command.new(operation, offset, input, unit_id)` | Exact operation atom from D01; zero-based offset; read quantity or write value/list | Validated function-specific Command |
| `request(session, command)` | Session and Command revalidated; the Command's unit is authoritative | Reads `{:ok, list}`; writes `{:ok, :written}` |
| Named reads | Session, offset, quantity; use session's unit | `{:ok, boolean_list}` or `{:ok, register_list}` |
| Named writes | Session, offset, scalar/list; use session's unit | `:ok` |
| `Value.encode(value, kind, options)` | Exact integer/finite float, supported kind, unique `byte_order`/`word_order` keys | `{:ok, register_list}` with exact width |
| `Value.decode(registers, kind, options)` | Proper exact-width list of integers 0..65535 | `{:ok, scalar}` |
| `health_check(session, read_command)` | Any validated FC 1–4 Command; command unit and range retained | `{:ok, :healthy}` only after matching positive response |
| `disconnect(session)` | Well-formed session, including an already closed one | `:ok`; owned resources released |

The connect allowlist is `host`, `port`, `unit_id`, `timeout`, `owner`,
`transaction_id`, `security`. Keys must be unique. Owner defaults to the caller
and must be a PID; initial transaction ID defaults to 0 and is 0..65535;
security must be `:none`. Host is a valid numeric IPv4/IPv6 tuple or a numeric
address string of at most 64 bytes; port is 1..65535. Invalid/unknown options
are `:invalid_options`; invalid host is `:invalid_host` on `:host`, and a
different security selector is `:unsupported_security` on `:security`. No
application environment, endpoint discovery or DNS lookup is introduced here.
A Session identifies one TCP owner, not exclusive access to an entire device.
A typed Command may deliberately address a different admitted unit on that
connection. Named helpers take their unit from the Session. This distinction
must be tested rather than accidentally overwritten by a transport adapter.

`send/2` accepts exactly `type`, `address`, and one operation-appropriate input:
`count` for reads, `value` for single writes, `values` for multiple writes.
Reject missing, unknown or mutually conflicting input forms as
`:invalid_message` before admission. Do not choose one conflicting field by map
lookup precedence. Atom operation names are a closed allowlist; strings are not
silently converted to atoms. Preserve the existing read/write result distinction.

The conversion option defaults are both `:big`; accepted orders are `:big` and
`:little`. Unknown or duplicate options return `:invalid_order`. Float helpers
retain their two-argument/three-argument defaults; a caller needing float64 or a
different order composes `Value` with an ordinary read or write helper. Explicit
zero and `false` are values. `nil`, NaN/infinity and wrong widths fail; no absent
response is replaced with zero. Error classifications and effect handling are
governed by WMB-C04 and the Wotex integration contract.

These requirements do not add a client retry loop. Validation/admission failure
has `effect: :none`; a transmitted write with missing or malformed acknowledgment
has `effect: :unknown`. The socket closes on framing/correlation failure, queued
work is failed without transmission, and no later request consumes a stream tail
from the failed exchange. The 64-admitted-call bound includes the active call.

## WMB-D03 — Complete standalone workflows

The software fixture must expose a disposable unit 1 register/coil map and an
explicitly readable health location. A complete example, tested without Runtime:

```elixir
alias Wotex.Modbus
alias Wotex.Modbus.{Command, Value}

{:ok, session} = Modbus.connect(host: "127.0.0.1", port: 1502, unit_id: 1, timeout: 3000)
try do
  {:ok, words} = Value.encode(25.5, :float32)
  :ok = Modbus.write_holding_registers(session, 10, words)
  {:ok, [16844, 0]} = Modbus.read_holding_registers(session, 10, 2)
  {:ok, 25.5} = Modbus.read_float(session, 10)
  {:ok, probe} = Command.new(:read_holding_registers, 10, 1, 1)
  {:ok, :healthy} = Modbus.health_check(session, probe)
after
  :ok = Modbus.disconnect(session)
end
```

This resource-dependent workflow uses the implemented `health_check/2`.
The independent fixture asserts the server received
one FC 16 mutation and the expected reads, no extra reconnect, and zero surviving
client socket/owner after the `after` clause. Its readback proves the peer's
register content, not calibration, engineering units or a physical effect.

A second workflow covers uncertainty: transmit a write, have a malformed peer
close before its echo, require `:transport_error` with `details.reason: :closed`
and unknown effect, then attempt a second write using
the same Session. The second call must return `:connection_closed` and transmit
nothing. An independent server response is unnecessary for this malformed-peer
lane; keep its result distinct from actual libmodbus interoperability.

## WMB-D04 — Concrete fixture and executable-oracle contract

`docs/specs/fixtures/contract-v1.json` is versioned exact input/expected-output
data. Its cases are **specified, not accepted or executed evidence** merely
because this file exists or parses as JSON. The WMB-Vxx table in WMB.10 contains
scenario families; it is not itself a packet corpus. The checked-in corpus
instantiates useful cells and must be extended to cover every required boundary,
failure and lifecycle scenario before completion.

The fixture format is local `wotex-protocol-contract@1.0.0`; it does not claim
compatibility with a different package's conformance runner. Each case has a
unique `id`, `requirements`, `scenarios`, `tier`, `operation`, `input`, and
`expectation` with `operator: "exact"` and a complete expected projection.
Execution status belongs in separately generated evidence, never in input data.

The runner implements a fixed operation allowlist below. It supplies only
`input` to the system under test. It obtains observations independently, applies
the declared projection, and compares them structurally with `expectation.value`.
Never hand expected responses to a client callback that is being assessed as
independent interoperability. Injected pure/lifecycle fixtures are labelled as
such and cannot satisfy the libmodbus lane.

| Fixture operation | Required adapter and exact observation projection |
| --- | --- |
| `codec.exchange` | Construct the Command from `input.command`, call `Codec.encode/2`, then decode `response_hex` and call `Codec.response/3`; observe `request_hex` plus normalized `result` |
| `codec.decode` | Decode `input.hex` once; observe `status`, decoded frame fields including `pdu_hex`, and `tail_hex`, or `status: "more"`, or normalized error |
| `command.new` | Call `Command.new/4`; observe `status` and function/address/values, or normalized error |
| `command.forged_encode` | Construct fields directly as a forged Command, call `Codec.encode/2`; observe normalized result; no constructor repair |
| `value.encode` / `value.decode` | Call matching `Value` function with the explicit kind and orders; observe normalized result |
| `session.trace` | Drive an explicitly injected clock and owned socket fixture through input events; observe emitted ADUs, per-call projected results, final owned resource counts |

Normalization is deterministic: permitted atoms become their fixed string
names; `{:ok, value}` becomes `{"status":"ok","value":value}` and `:written`
becomes the string `"written"`; `:ok` becomes `{"status":"ok"}`. Binary frame
fields use lowercase even-length hexadecimal. Lists remain ordered. Error
projection includes exactly `code`, `field`, `details`, `retryable`, and `effect`
under `{"status":"error","error":...}`. Additional error classification is
tested separately by the integration contract; it is not erased from production
errors. JSON `null` represents Elixir `nil`; strings never undergo unrestricted
atom creation. An output not matching the declared operation shape is a failure.

Trace events are ordered by `(at_ms, list_position)` on a virtual monotonic clock
starting at zero. `call` starts an asynchronous public operation with its given
deadline, `peer_bytes` injects bytes into the already owned socket, `peer_close`
closes that socket, and `drain` processes ready messages/timers. Request IDs in
traces are test labels, never Modbus wire IDs. Fixtures inject the initial
transaction counter explicitly through test support, without a production global
clock/identity setting. Resource counts concern only resources opened by the
test; no operating-system-wide counts or wall-clock sleeps stand in for cleanup.

For each executed case, evidence records ID, fixture file SHA-256, implementation
commit, command, toolchain, actual result and assertion outcome. Binding IDs to a
test that only loads JSON or checks that an ID exists does not meet acceptance.
Unknown fixture operations, duplicate IDs, missing cases or skipped cases fail
the required runner. P01–P04 own these adapters and assertions; P05 verifies the
complete corpus alongside independent peers and archive/matrix checks.

## Source basis

The wire examples use the fields in Modbus Application Protocol V1.1b3
(2012-04-26), §§4.2, 6.1–6.6, 6.11–6.12 and 7, and the TCP/IP Guide V1.0b
(2006-10-24). [Exact source links](../provenance/primary-sources.md) retain access
limits. Helper names and current return values were checked against the public
modules identified by the executable-evidence cohort. Strict message-map admission, fixture format,
bounded ownership and standalone release workflows are library design decisions.
