---
spec:
  id: WMB.10
  title: "Consumer-owned register process-codec execution"
  status: accepted
  version: 1.0.0
  owner: wotex-modbus
  updated: 2026-10-08
---

# WMB.10 Consumer-owned register process-codec execution

This optional owner executes the WMB.09 contract through WRT.06
`process-codec@1.0.0`. It does not own a TCP connection, change Form mapping,
install an executable or authorize a device operation. Runtime retains its
pure codec/value boundary; the consumer provisions a qualified execution driver.
The ordinary library and trusted BEAM decoder remain available independently.

## P01 — Public startup and executor

`Wotex.Modbus.RegisterCodec.Host.child_spec/1` returns a temporary child
specification. Its start argument hides configuration from inspection.
`Host.start_link/1` accepts a closed atom-keyed map with exactly `plan`,
`context`, `driver`, `current_inputs`, `now`, `owner`. Plan and startup Context
are supplied explicitly; owner is a local consumer pid. Driver is the explicit
trusted `{module, config}` implementing `Wotex.Modbus.RegisterCodec.Driver`.
Current_inputs is a zero-arity callback returning current WRT.04 Inputs; now
returns an integer or valid DateTime matching the original deadline kind.
Callbacks are consumer-owned and must return promptly. No descriptor field
chooses code, an actor, an executable path or a clock.

Startup returns `{:ok, pid}` promptly after static validation and begins opening
asynchronously. `Host.await_ready/1` returns `:ok` or Implementation.Error;
one startup waiter is admitted. `Host.stop/1` requests bounded cleanup and
returns `:ok` or Implementation.Error. At most one stop waiter is retained.
No automatic restart or fallback is scheduled. The consumer may override the
temporary restart policy explicitly and must then allocate a fresh generation.

Host implements `Codec.Executor.decode/4`; the consumer supplies `{Host, pid}`
to the Runtime facade. The exact WMB.09 contract/schema, configuration and
native process binding are required. A Call must contain the same Plan as the
owner. Different generations fail `stale_generation`; other substitutions fail
`correlation_failed`. Input and metadata are validated before driver dispatch.
Construction/loading starts no driver or native program. Explicit startup is
the only open boundary; decode never opens a replacement.

## P02 — Consumer driver contract

The consumer starts one driver actor per host before configuring Host. The
trusted driver module has four callbacks, with no library-provided default:

| Callback | Result and obligation |
|---|---|
| `profile(config)` | Pure `{:ok, %{pid: local_pid, artifact: native_reference, enforcement: enforcement_record, codec_contract: contract_reference}}` or `{:error, :enforcement_unavailable}`. References must exactly match the admitted registration; all five WRT.04 guarantees are required. A declaration alone does not establish those facts. |
| `open(host, owner, channel, plan, limits, config)` | Prompt `:ok` or `{:error, fixed_code}`. Atomically claim the otherwise unused driver, monitor host and consumer owner before acquiring resources, reverify the exact admitted immutable deployment/target closure and attach native custody/enforcement before spawn. Opening is asynchronous. |
| `write(channel, binary, config)` | Prompt `:ok` or `{:error, fixed_code}`; nonblocking bounded submission for this channel only. No retry. |
| `close(channel, cleanup_ms, config)` | Prompt `:ok` or `{:error, fixed_code}`; asynchronous bounded close, escalation and confirmed descendant reaping. An unknown/refused channel must never close another owner's resources. |

Callback failure codes are only `artifact_unverified`, `enforcement_unavailable`,
`startup_failed`, `codec_unavailable`, `overloaded`, `cleanup_unconfirmed`.
Exceptions, exits, throws and malformed returns become fixed errors; no foreign
text is retained. The channel is a fresh internal reference, not public authority.
Limits contain the effective C03 ceilings in a string-keyed map, including one
active/zero queued requests. Native paths, environment, argv, working directory,
immutable deployment, exact loader/dependency closure, memory, privilege denial,
stdout mailbox/backlog bounds and escaped-descendant cleanup are the driver's
qualified target contract. This library does not relabel a Port or process group
as that enforcement. Missing required proof refuses opening.

The driver sends only these messages to the supplied host:

| Message | Meaning |
|---|---|
| `{:wotex_modbus_codec, channel, :opened}` | Exact deployment verified; owner custody/enforcement attached; child started. Sent once, before stdout. |
| `{:wotex_modbus_codec, channel, {:stdout, binary}}` | Protocol-only bytes within the effective bounded delivery/backlog contract. |
| `{:wotex_modbus_codec, channel, {:stderr, binary}}` | Raw bytes to count and discard; never log/render. |
| `{:wotex_modbus_codec, channel, :exited}` | Child exit/EOF, not proof of descendant cleanup. |
| `{:wotex_modbus_codec, channel, {:failed, fixed_code}}` | Asynchronous driver refusal/failure. |
| `{:wotex_modbus_codec, channel, {:closed, :confirmed_local \| :unconfirmed}}` | Cleanup result after close. Confirmed means actual owned tree/resources released within the single budget. |

Driver and host death cannot depend on a Host terminate callback executing.
The independently owned driver/custodian must release partially opened native
resources on host or owner death, including while opening is blocked. Host
monitors the configured driver; its death makes cleanup unconfirmed unless an
independently qualified custodian provides the configured driver result.
Messages from another channel are discarded before parsing.

## P03 — Exchange, deadlines and cleanup

After opened and fresh admission, Host sends exactly one WRT.06 hello. It
accepts exactly the matching ready, including generation, descriptor/contract,
configuration hash and effective decode budget. Early, wrong or duplicate ready,
unsolicited output, multiple replies, substituted seq/request id, malformed
frames and extra fields terminate the generation. Fragmented frames are
supported. A complete reply followed by further partial output in the same
delivery is already unsolicited and fails before returning success.

Startup/decode/cleanup budgets are the minimum of C03 and admitted limits;
startup/decode also respect the original Context deadline. Equality is expired;
clock-kind mismatch/backwards movement refuses execution. Budgets include
framing, dispatch and output admission. Only relative budgets cross the process
boundary. The original local deadline is checked at reply acceptance, after
current-admission revalidation and output construction. Current policy must
continue to supply all required enforcement guarantees.

One request is active, none queued. A concurrent request returns overloaded
without dispatch. Sequences start at one, increase without reuse and retire
before exhaustion can wrap. The pending caller is monitored; its death retires
the stateless generation. Old channel output cannot enter a new instance.
Four deterministic codec refusals leave the instance ready; host/protocol,
deadline, owner or admission failures initiate cleanup. A valid late reply is
never accepted or evaluated by the BEAM decoder.

Stop/drain rejects new work, sends the WRT.06 stop frame once when started and
requests driver cleanup once. Startup and request timers cannot reset cleanup.
Terminal results wait for confirmed cleanup; expiry/refusal/driver death returns
cleanup_unconfirmed. Caller timeout is not evidence of child death. Stdout after
drain is discarded, stderr is never retained, and no replacement is started.

## P04 — Acceptance and qualification

The functional reference workload is WMB.09's one-to-four register grammar,
all four byte/word orders, sign/scale extremes and deterministic refusals. The
replacement criterion is changing an explicitly installed decoder/driver without
changing the consuming Host/Runtime code, while preserving contract/JCS output
and generation isolation. This is an engineering reference, not a production
consumer cost claim or a benchmark. Data-only scalar ordering remains the
counterexample. Workload cost thresholds, independent-language/native closure
and OS enforcement evidence remain separately qualified programme requirements.

Tests must cover static and current-admission refusals before open, wrong/early/
duplicate handshake, fragment/coalescing faults, correlation substitution,
deadline equality/backwards clock, overload, sequence exhaustion, owner/request
caller/driver loss, failed/hung cleanup, two independently configured instances,
deterministic refusal and secret canaries in configuration/input/output/stderr.
Scripted driver evidence proves the owner contract, not real native enforcement.
Qualified native evidence must additionally use exact installed archives and
executable/guardian/loader artifacts, demonstrate memory and escaped-descendant
limits, and pass the portable programme's independent implementation gates.
