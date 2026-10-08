# WRT.06: Bounded, inert codec profile

Specification `WRT.06@1.2.0`. Package owner: `wotex_runtime`.
Contract: accepted optional specification; implementation status: `partial`.
This optional profile defines deterministic decoding of explicit bytes and
metadata into inert typed values. It is not a transport, device enrollment,
Property truth or Action authorization interface. Numerical budgets are
engineering ceilings to be qualified, not measured performance claims.

## C01 — Contract and capability boundary

A registered codec contract has an exact id/version/digest, input byte grammar,
closed metadata/configuration grammars, output value schema, success/refusal vectors,
and supported input-format revisions. The contract is local immutable data.
The generic profile does not define device-specific decoding. A binding MUST
reject an unregistered codec or mismatched schema/contract digest before decode.
Protocol owners define their projections through public documented APIs.

WRT.04 descriptors for this profile have `kind: codec`, API id `wotex.codec`
and API version `1.0.0`; `support` and `permissions` are empty; state is
`stateless`, `none`, `message_boundary`, `null`. The BEAM binding is
`beam-codec` version `1.0.0` with null artifact/entrypoint. The process binding
is `process-codec` version `1.0.0` with an admitted native executable artifact.
Native packaging remains target-specific; semantic portability is not binary
portability. An unknown binding, including `wasm-codec`, is refused.

Inputs are only bytes, validated metadata and non-secret admitted configuration.
Configuration is a flat object under the metadata grammar and limits below;
the registered codec contract binds the descriptor's configuration-schema
id/digest. Configuration identity is SHA-256 over its RFC 8785 JCS bytes.
BEAM receives that exact object; process codecs receive it once in `hello`.
No socket, process registry, executable path, clock, random source, credential,
store handle or device reference is passed into decoding. Implementations MUST
not perform I/O, fetch schemas, update durable state or grant authority. A
trusted BEAM callback is not technically sandboxed; it is accepted only under
the explicit trusted-code model. Untrusted native code requires a separately
specified and evidenced enforcement profile denying network/device/store and
ambient filesystem access; v1 does not supply such a sandbox.

The public target API below defines decoding, values and return shapes now.
The process grammar is also specified now; independent implementations must
prove they follow it. WoTEx is unreleased. Interface design does not wait for
post-release compatibility analysis or certification.

## Public target API

`Wotex.Runtime.Codec.decode/5` takes a WRT.04 Plan, input binary, metadata map,
WRT.01 Context, and explicit executor `{module, config}`. It returns
`{:ok, %Wotex.Runtime.Codec.Result{}}` or
`{:error, %Wotex.Runtime.Implementation.Error{}}`. The module is an explicitly
supplied trusted consumer atom, never resolved from descriptor text. Admission
checks and Call construction occur before one executor callback. The facade
revalidates the node and all result identities before returning success.
Malformed returns become `protocol_fault`; raised/exited/thrown callbacks become
`codec_unavailable` without foreign text. It never silently retries or starts
a native instance. Executor configuration references an explicitly owned host
or trusted decoder; it contains no reusable credentials.

The `Wotex.Runtime.Codec.Executor` behaviour has exactly `decode/4`:
`(input_binary, metadata_map, Call, consumer_config)` ->
`{:ok, Result} | {:error, Implementation.Error}`. It owns deadline observation,
current-admission revalidation, worker/host custody and C04 process exchange.
The pure decoder never receives those execution inputs. The
`Wotex.Runtime.Codec.Decoder` behaviour has exactly `decode/3`:
`(input_binary, metadata_map, configuration_map)` ->
`{:ok, node_map} | {:error, code}`; code is one of C04's four deterministic
codec refusals. This callback performs no effects under C01.

`Wotex.Runtime.Codec.Call.new/2` takes Plan and Context and returns a tagged
validated Call or Implementation.Error. Call has exactly `plan`, `context`.
The Plan's registration must have a non-null matching codec-contract reference,
and its descriptor must name the exact C01 API/binding tuple. Missing or wrong
registration/schema/contract is refused before any executor callback.

`Wotex.Runtime.Codec.Result.new/2` takes node map and validated Call and returns
a tagged Result or Implementation.Error. Result has exactly `value`,
`descriptor_sha256`, `deployment`, `contract_id`, `contract_sha256`,
`configuration_sha256`, `binding`, `instance_key`, `request_id`. Identity comes
from Call/Plan and the registration, never decoder output. Context contributes
request identity, not credentials. Foreign substituted fields fail correlation.

`Wotex.Runtime.Codec.Value.validate/1` returns `{:ok, node_map}` or a structured
error under C02/C03. `Value.encode/1` returns `{:ok, jcs_binary}` or that error
after validation and encoded-size admission. Both are pure and bounded; every
constructor revalidates forged structs. These are specified signatures and
layouts for implementation, not claims that exports already exist.

### Trusted BEAM executor

`Wotex.Runtime.Codec.Beam` implements `Codec.Executor.decode/4`. Its explicit
consumer configuration is a closed atom-keyed map with exactly `decoder`,
`contract`, `task_supervisor`, `current_inputs`, `now`. Decoder is the installed
trusted module implementing `Codec.Decoder`; contract is the exact registration
codec-contract reference. The consumer qualifies that module against that
immutable contract. Runtime does not load code from descriptor text or prove
module bytes from a reference. A mismatch is `schema_mismatch`.

Task_supervisor is an already running, consumer-owned Task.Supervisor pid.
The consumer provisions one per instance with `max_children: 1`; this gives
atomic one-active/zero-queued admission. A second call returns `overloaded`.
Decoder tasks are temporary. The supervisor is never shared between instance keys.
Current_inputs is a zero-arity consumer callback returning current WRT.04
Inputs; now is a zero-arity consumer clock returning an integer monotonic
millisecond reading or a valid DateTime matching Context's deadline. With a
null deadline either clock kind is accepted. The executor revalidates current
admission before worker start and before accepting output. Clock mismatch or
backwards movement refuses execution; equality at the original deadline or
effective decode budget is expired. The budget is the minimum of remaining
Context time, 1,000 milliseconds and admitted request_ms.

The executor starts one temporary task under that explicitly supplied
supervisor, passing only decoder module, bytes, metadata and admitted
configuration to the decoder. An ephemeral custodian monitors the caller before
task creation, attaches before decoding and kills the worker on owner loss.
Worker termination also closes that custodian. Owner death or timeout kills
the task; the executor confirms
worker termination before returning. No VM or descendant isolation is claimed
for trusted BEAM code. Tasks catch decoder exceptions, exits and throws before
they can become raw task crash diagnostics. Decoder failures use the four
deterministic refusal codes; malformed returns are `protocol_fault`. No retry
or fallback follows worker loss. Loading Beam starts neither supervisor nor
worker; decode is the explicit start boundary.

## C02 — Values and determinism

The output is one node in this closed recursive algebra. Objects have exactly
the listed keys. JSON numeric values are used only for bounded protocol counters
and decimal exponent; codec integers use canonical decimal strings.

| Node | Exact JSON shape and value grammar |
|---|---|
| Null | `{"type":"null"}` |
| Boolean | `{"type":"boolean","value":true}` or false |
| Text | `{"type":"text","value":"..."}`; valid UTF-8, no normalization |
| Bytes | `{"type":"bytes","base64":"..."}`; canonical Base64 |
| Signed integer | `{"type":"sint","value":"-12"}`; signed 64-bit, no plus, leading zeros or negative zero |
| Unsigned integer | `{"type":"uint","value":"12"}`; unsigned 64-bit, no leading zeros |
| Decimal | `{"type":"decimal","coefficient":"123","exponent":-2}`; coefficient canonical signed 64-bit string, no nonzero trailing decimal zero; exponent integer `-32768..32767`; zero is coefficient `"0"`, exponent 0 |
| List | `{"type":"list","items":[node,...]}`; order is meaningful |
| Object | `{"type":"object","entries":[{"key":"...","value":node},...]}`; keys unique, 1–128 UTF-8 bytes, ascending unsigned UTF-8 byte order |

Signed zero, NaN, infinity, ambiguous binary-float-to-decimal conversion and
values outside this algebra are refused `unsupported_value`. A protocol that
needs those values must explicitly define another versioned projection; generic
hosts do not guess, truncate or coerce. Decimal represents coefficient times
ten to exponent. Units and missingness come from the registered output schema;
null, absence, zero and empty bytes remain distinct. Consumers choose any
conversion into domain values or tensors under the owning schema.

For identical bytes, metadata, admitted configuration and contract revision,
decoding MUST return the same typed tree or same codec refusal code, independent
of clock, machine endian order, concurrency or invocation history. Scheduling
timeout, overload and process loss are host failures, not deterministic decode
refusals. No binary-float tolerance is implicit. Comparison uses the node's
RFC 8785 JCS bytes; object entries are already sorted by the rule above.
Implementation and request identity are compared separately from value bytes.

## C03 — Admission limits

| Resource | Maximum |
|---|---:|
| Decoded input bytes | 65,536 |
| Canonical metadata or configuration JSON bytes / fields, each | 4,096 / 16 |
| Metadata/configuration nesting | One flat object; each value string, boolean, null or signed safe JSON integer in `-9007199254740991..9007199254740991` |
| Metadata/configuration key / string-value UTF-8 bytes | 128 / 256 |
| Output JCS JSON bytes | 65,536 |
| Output node nesting / typed nodes | 8 / 1,024 |
| Items or entries in one typed collection | 256 |
| Text/bytes decoded size | 4,096 |
| Full wire JSON collection nesting / total JSON nodes | 24 / 4,096 |
| Full frame including LF | 131,072 bytes |
| Concurrent / queued decode requests per instance | 1 / 0 |
| Startup / decode / cleanup budgets | 5,000 / 1,000 / 1,000 milliseconds |
| Retained stdout queue / raw stderr | 262,144 / 4,096 bytes |
| Process memory under the declared enforcement profile | 67,108,864 bytes |

The effective limit is the minimum of these ceilings, descriptor limits and
consumer policy. Runtime admission validates byte lengths and flat metadata
before calling a codec. The decoder validates input structure before producing
output. The host revalidates output schema/algebra/size even when a trusted
callback returns a forged node. Parsing/encoding must stop before over-bound
allocation. Output typed-node depth starts at 1 for the root and increases at
each child node; full wire depth counts each JSON object/array starting at 1.

Use canonical RFC 4648 Base64 with standard alphabet, required final padding
and zero pad bits; whitespace and URL-safe variants fail. Maximum encoded
input length is 87,384 ASCII bytes, checked before decoded allocation.
Zero-length input is admitted by the generic profile; the codec contract may
refuse it. Process limits include its descendants. Unavailable required memory
or cleanup enforcement fails admission; a BEAM binding cannot advertise the
per-process memory ceiling as isolated VM enforcement. It must declare that
limitation in its trusted profile and refuse policy requiring hard isolation.

Budgets include framing, dispatch, decoding and output admission. The host
owns the local deadline, with equality expired. BEAM decoding runs in an
explicit consumer-owned bounded callback worker when cancellation is required;
WRT.01 synchronous transport calls remain in their caller. Workers receive no
transport credentials. No hidden startup or shared worker pool is introduced.

## C04 — Process framing and handshake

The process uses stdin/stdout UTF-8 JSON lines, one object per LF-terminated
frame, no CRLF, BOM or blank line. No literal CR/LF appears inside the JSON
body; string content may use JSON escapes. Whitespace other than CR/LF is
allowed within JSON. Reject duplicate keys at every level, extra fields,
invalid Unicode, trailing bytes and floats. All protocol integers are safe
JSON integers whose tokens have no fraction or exponent. Partial reads and
coalesced frames must be supported with the same allocation limits.
Stdout is protocol-only; stderr is counted, discarded
and never rendered or exposed in errors. Excess output terminates the child.

All frames include `v: 1` and a `type` below, with exactly the specified keys.
Host instance id/generation follow WRT.05. Descriptor and contract hashes are
full lowercase SHA-256. Contract id is a WRT.04 contract token.

| Direction / type | Exact keys beyond `v`, `type` | Meaning |
|---|---|---|
| Host `hello` | `instance_id`, `generation`, `descriptor_sha256`, `contract_id`, `contract_sha256`, `decode_ms`, `configuration`, `configuration_sha256` | Send once after verified explicit spawn; `decode_ms` is effective maximum `1..1000`; configuration is the validated flat object |
| Child `ready` | Same keys as hello except `configuration` | Exact echo of registered identity/budget/configuration hash; not an integrity proof |
| Host `decode` | `seq`, `request_id`, `budget_ms`, `bytes`, `metadata` | `seq` starts at 1 and increments without reuse; request id 1–256 UTF-8 bytes; budget `1..decode_ms`; bytes has exactly `type: bytes`, `base64` |
| Child `result` | `seq`, `request_id`, `value` | One validated C02 node; correlated to the sole pending request |
| Child `refusal` | `seq`, `request_id`, `code` | One deterministic codec refusal: `invalid_input`, `unsupported_format`, `unsupported_value`, `output_limit` |
| Host `stop` | No extra keys | Cease operation and exit normally after closing resources |

`ready` must arrive within startup budget and before any decode. The child
MUST validate configuration schema/hash before decoding input;
invalid configuration fails startup with no ready frame. Protocol
negotiation MUST NOT downgrade an unsupported version. Wrong/missing/duplicate ready,
any early child result, unsolicited frame, duplicate reply, mismatched sequence
or request id is `protocol_fault`; terminate the instance. Host decode before
ready is `instance_not_ready`. A second concurrent call returns `overloaded`
without sending any frame. Sequence exhaustion retires the instance before
another request; no wrap is permitted.

The process lifetime itself fences generation: no result from an old Port can
be accepted through a new owner. On cancellation/timeout, terminate this
stateless generation and confirm descendant cleanup within budget; v1 has no
cancel frame, no late-reply cache and no implicit restart. A result arriving
after the local deadline is never successful. EOF before ready is
`startup_failed`; EOF while pending is `codec_unavailable`. On stop, accept no
new output; signal/escalate/reap under custody if the process does not exit.

For example, decode input byte `0x01` uses `{"type":"bytes","base64":"AQ=="}`.
A contract that interprets that byte as unsigned integer returns
`{"type":"uint","value":"1"}`. The generic host does not assume this
mapping; it is a required vector only if the registered contract declares it.
`AR==` is rejected for nonzero pad bits even though permissive Base64 decoders
may produce the same byte. A `uint` value of `"18446744073709551615"` is
admitted; `"18446744073709551616"` is refused, with no floating conversion.

## C05 — Results, errors and provenance

Success returns the validated node and non-secret identity: descriptor,
deployment/build/payload where applicable, codec contract/configuration
identity, binding version, instance/generation and caller request id.
Consumers decide whether to retain sensitive input/output; generic telemetry
contains lengths and fixed outcomes only. Raw bytes, metadata values, output,
stderr and exception messages MUST NOT appear in public errors or telemetry.

Host error codes are `invalid_input`, `unsupported_format`,
`unsupported_value`, `output_limit`, `invalid_metadata`, `schema_mismatch`,
`deadline_exceeded`, `overloaded`, `protocol_fault`, `codec_unavailable`,
`startup_failed` and `cleanup_unconfirmed`, plus WRT.04/05 refusals. Phases are
`admission`, `startup`, `decode`, `output` and `cleanup`. Codec refusals are
permanent for identical inputs; availability/budget failures are separately
classified and never silently retried. A refused codec does not fall back to
same-VM evaluation or a different decoder.

## C06 — Acceptance and future bindings

The public algebra, Call/Result constructors, executor facade and trusted BEAM
executor are implemented. `test/wotex/runtime/codec_test.exs` checks canonical
values, bounds, pre-callback refusal, identity substitution and redaction.
`test/wotex/runtime/codec_beam_test.exs` exercises actual supervised workers,
owner death, timeout cleanup, overload and current-policy/late-reply refusal.
These tests do not establish independent process-codec interoperability or
consumer usefulness. Process framing, native custody/enforcement, independent
implementations and the protocol-owner projection remain open.

Required evidence, stored under the package's `priv/` or `test/support/`:

| Requirement | Cases |
|---|---|
| C01 | Data-only mapping control versus codec; no I/O/credential APIs supplied; registration/schema mismatch; passive load and explicit worker/child start |
| C02 | Every node, 64-bit extrema, normalized decimals, missing/null/empty distinctions, Unicode byte ordering, repeated/cross-instance deterministic output; reject NaN/overflow/coercion |
| C03 | Equality and one-over cases for every size/depth/count/budget; expansion before allocation; wrong metadata; forged output; actual process-memory enforcement |
| C04 | Independent host and child implementations; fragmented/coalesced frames; malformed UTF-8, duplicate/extra keys, Base64 pad bits, wrong handshake, unsolicited/duplicate/late response; kill during partial write; sequence exhaustion |
| C05 | Secret canaries in input, output, configuration and stderr absent from public errors, inspection and telemetry; implementation identity retained |
| Lifecycle | Owner death, hung decoder, saturated output, escaped descendants, timeout cleanup, two simultaneous instances and stateless generation switch |

A future WASM or other portable binding must pin runtime release/digest,
artifact/ABI format, import allowlist, memory/fuel/interruption accounting,
compile-cache identity, native dependency closure and deterministic value rules.
It must pass the same codec success/refusal vectors plus denied-import and
runtime fault vectors. Benchmarking and physical target qualification occur
only in explicitly invoked lanes. A successful native codec does not establish
WebAssembly support or binary portability.

[WRT.04](WRT.04-implementation-admission.md) governs trust/admission and
[WRT.05](WRT.05-implementation-lifecycle.md) governs generations/replacement.
The [delivery programme](https://github.com/wotex-project/wotex/blob/main/docs/architecture/portable-delivery-plan.md)
defines the go/stop decisions. No protocol package or runtime dependency is
added by this specification alone.
