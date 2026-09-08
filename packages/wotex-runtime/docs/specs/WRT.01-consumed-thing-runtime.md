# WRT.01: ConsumedThing runtime mechanics

Specification: `WRT.01@1.3.0`. Package baseline: `wotex_runtime 0.1.0`.
Implementation and evidence coverage are recorded in the catalogue and
repository completion plan at `docs/plans/wotex-runtime-completion.md`; this document is not a gate result.

## Ownership

The package owns immutable runtime context, binding-profile values,
deterministic Form selection, typed requests/results, credential and transport
ports, synchronous ConsumedThing operations, retry decisions, and explicit
subscription child specifications.

The consumer owns authorization, credential custody, transport instances,
durable delivery, accepted Property/Event truth, governed Action intent and
effect, clocks, and supervision.

## Requirements

1. The runtime MUST consume `Wotex.ThingDescription` through its public facade.
2. It MUST support `readproperty`, `writeproperty`, `observeproperty`,
   `unobserveproperty`, `invokeaction`, `queryaction`, `cancelaction`,
   `subscribeevent`, and `unsubscribeevent` only when a selected profile
   declares the operation and the Form declares it or receives it as a TD 1.1
   default operation through `Wotex.Form.operations/2` (`readOnly` and
   `writeOnly` reduce Property defaults; Thing-level Forms have no default).
3. Form selection MUST be deterministic over TD form order and consumer profile
   order. It MUST return typed absence instead of guessing a transport.
4. A request MUST carry a caller-supplied request id and optional absolute
   deadline: an integer is a `System.monotonic_time(:millisecond)` instant on
   the calling node, a `DateTime` is a UTC wall-clock instant, and
   `Context.remaining_ms/2` derives the remaining budget from a clock reading
   the port takes itself. Planning and retry/budget decisions MUST NOT read a
   clock or generate identity. Telemetry may read clocks only for event timing;
   those readings MUST NOT select or authorize an interaction or retry.
5. Security declarations MUST be passed to a credential port immediately before
   execution. Credential material MUST NOT enter public request values or errors.
6. Short operations MUST run in the caller process.
7. A long-lived observation or Event subscription MUST start only through an
   explicit child specification. Zero, one, and multiple named instances MUST
   work without application-global state. `init/1` MUST return before any
   protocol exchange; the open happens in a continuation so an unreachable
   transport never blocks the consumer's supervisor. The default restart
   policy is `:transient`.
8. Retry classification MUST return a decision; this package MUST NOT sleep or
   retry a potentially non-idempotent operation by itself. When a port returns
   its own structured error, the runtime MUST retain that error's atom `code`,
   `phase`, and `class` under `details.cause` and set the runtime error's
   `class`, so `Retry.decision/3` can act on it. Messages and details of the
   external error are never copied.
9. A successful result records protocol exchange only, never physical effect or
   canonical state.
10. Graceful supervisor shutdown MUST request protocol unsubscription within
    the consumer-selected shutdown budget. Explicit stop MUST NOT unsubscribe
    twice. Forced termination and transport failures require consumer recovery;
    local process termination does not prove remote cleanup.
11. Port calls MUST be isolated: a raise, exit, or throw in a credential or
    transport callback becomes `port_exception` without the exception in the
    public error, and is reported through
    `[:wotex, :runtime, :port, :exception]` telemetry for the consumer's own
    logging.
12. The subscription MUST monitor its receiver and stop with
    `{:shutdown, :receiver_down}` when it exits; MUST treat a linked transport
    exit or a `:transport_down`/`:session_lost` status as a stop with a
    `:shutdown` reason after notifying the receiver; MUST always attempt the
    protocol unsubscribe on graceful termination even when stop credentials
    cannot be resolved; and MUST honor an optional receiver mailbox bound
    (`max_queue_length` with `overflow: :drop | :stop`).
13. Every delivery to the receiver MUST be `{:wotex_runtime, id, event}` with
    `event` one of `{:ok, value, meta}`, `{:error, %Error{}}`, or
    `{:status, status}`. Raw frames sent as `{:wotex_transport_frame, frame}`
    are decoded in the subscription process through the optional
    `Transport.decode_frame/3` callback, keeping decoding off the transport's
    connection process.
14. Telemetry events listed in `Wotex.Runtime.Telemetry` MUST carry only
    non-secret identity and outcome metadata.
15. Runtime-owned admission MUST cap request identifiers at 256 bytes,
    top-level Context and Result metadata at 64 entries, ConsumedThing and
    direct-selection profile lists at 32 entries, and each interaction's Form
    scan at 128 entries. The threshold MUST be accepted and one over MUST
    return a typed error before calling a port.

## Evidence

Tests cover every operation category, deterministic selection, default
operations, unsupported cells, credential isolation, transport errors, cause
retention, port exception isolation, retry classification, deadline budgets,
telemetry, and zero, one, and multiple subscription instances including open
failure, receiver death, linked transport exit, session loss, restart after
loss, brutal kill, mailbox overflow, concurrent stop, credential failure at
close, and raised, exited or thrown callbacks at every transport lifecycle
stage. Fixed admission limits have threshold and one-over vectors; forged
Result structs are revalidated at the transport boundary.

## Public value and operation matrix

All module names below are under `Wotex.Runtime`. Constructors return tagged
success/error values; `Context.new!/1` is the explicitly raising alternative.
Consumers MUST use constructors rather than treating an Elixir struct as an
authorization or untrusted-input validation boundary.

| Surface | Input and result | Side effects and evidence |
|---|---|---|
| `Context.new/1`, `new!/1` | explicit nonempty request identity, optional deadline and metadata | Immutable value; no clock, identity generation or policy check; `value_test.exs` |
| `BindingProfile.new/1` | id, schemes, supported operation atoms and media types | Immutable declaration, not an installed driver; `value_test.exs` |
| `ConsumedThing.new/2` | validated TD, ordered profiles, explicit transport map and credential port | No process/network; rejects duplicate profile ids and missing callbacks; `consumed_thing_test.exs` |
| `FormSelector.select/5` | TD, affordance type/name, exact operation, ordered profiles | Selection or typed absence; never credential resolution; `form_selector_test.exs` |
| `Request.from_selection/3` | selection, context, input | Credential-free request retaining request identity/deadline; `value_test.exs` |
| `Result.new/4` | request identity, operation, payload, `:ok` or `:accepted` status, metadata | Protocol result only; protocol status detail lives in metadata; `value_test.exs` |
| `Result.validate/1` | a Result returned by a transport | Rechecks identity, operation, status and metadata limits even for a forged struct |
| `Limits.all/0`, `maximum/1` | the four fixed Runtime admission limits | Public, deterministic values; no environment lookup |
| `Context.remaining_ms/2` | deadline and a caller-read clock value | Pure budget arithmetic; `value_test.exs` |
| `Credentials.resolve/4` | selected security, Form, context, opaque consumer configuration | Immediate credential resolution; no custody transfer |
| `Transport.request/3` | request, ephemeral execution context, consumer configuration | One synchronous protocol exchange in caller |
| `Retry.decision/3` | operation, failure class or classified `Error`, explicit attempt/max/delay/idempotence | `:stop` or `{:retry, delay}`; never sleep, timer or retry |
| `Transport.decode_frame/3` | raw frame, request, consumer configuration | Optional; runs in the subscription process |
| `Subscription.stop/2` | explicit server and caller timeout | One unsubscribe or a typed not-running, timeout or stop-failure result; never exits the caller |

Test paths in this specification are relative to `test/wotex/runtime/`.

| TD operation | Public consumer operation | Input / completion meaning |
|---|---|---|
| `readproperty` | `ConsumedThing.read_property/3` | No write input; protocol payload |
| `writeproperty` | `ConsumedThing.write_property/4` | Explicit value; protocol acknowledgement, not canonical state |
| `invokeaction` | `ConsumedThing.invoke_action/4` | Explicit Action input; not physical-effect certainty |
| `queryaction` | `ConsumedThing.query_action/4` | Consumer invocation locator; binding decides representation |
| `cancelaction` | `ConsumedThing.cancel_action/4` | Consumer invocation locator; not proof that physical work stopped |
| `observeproperty` / `unobserveproperty` | `ConsumedThing.observation_child_spec/4`; `Subscription.stop/2` | Start and stop Forms selected together on one profile |
| `subscribeevent` / `unsubscribeevent` | `ConsumedThing.event_subscription_child_spec/4`; `Subscription.stop/2` | Event delivery lifecycle, not durable receipt |

The nine Thing-level operations have their own WRT.03 matrix. Their presence in
Runtime MUST NOT imply support by every binding profile. An omitted Form `op`
receives the TD-processing contract's default operations; Runtime applies them
through the core value API rather than re-deriving them.

## Execution and failure matrix

| Stage | Required behavior | Prohibited inference |
|---|---|---|
| Construction | Validate TD and declared ports before execution | Configured port is trusted/authorized merely because it exports callbacks |
| Selection | TD Form order first, profile order second; exact operation/scheme/media match | Pick a fallback transport after a negative match |
| Credentials | Resolve immediately before each start/request/stop exchange | Persist returned material in Context, Request, Result or subscription state |
| Transport | Check tagged callback returns; revalidate Result structs; preserve request/operation correlation; isolate raised/exited/thrown callbacks | External error term or arbitrary success is canonical truth |
| Failure | Stable Runtime error code/phase/class, nonsecret identity details, and the external error's atoms as `cause` | Raw external reason, message or details in error details |
| Retry decision | Only timeout/unavailable/rate-limited classes and admitted idempotence | Automatically repeat an Action after unknown physical effect |

Current retry defaults admit `readproperty` and `queryaction`; all other
operations require explicit `idempotent?: true`. Attempts and delays are
consumer inputs, not runtime scheduling. Retry admission MUST reject operations
outside the Runtime vocabulary, unknown or duplicate option keys, improper
lists, non-boolean idempotence, non-positive/non-integer attempt counts and
negative/non-integer delays with `:stop`, without raising. Only `:attempt`,
`:max_attempts`, `:delay` and `:idempotent?` are accepted; admission examines at
most five list cells. A retry requires `0 < attempt < max_attempts`. Defaults
remain attempt 1, maximum 1 and delay 0. `retry_test.exs` covers malformed
inputs and the operation/class/idempotence/budget matrix. This stricter
pre-release admission supersedes permissive malformed-input behavior; valid
retry decisions and the no-scheduling boundary are unchanged.

Current transport/credential exception
propagation and callback-return correlation are covered by the RT-C02 vectors;
a tagged-error test is not an exception-isolation test.

## Subscription lifecycle and ownership

| State / event | Package behavior | Consumer obligation |
|---|---|---|
| Child-spec construction | Returns inert map; requires id and a pid or registered-name receiver; validates mailbox bound and overflow policy; resolves both Forms | Choose distinct id/name, receiver, restart, shutdown, and mailbox policy |
| Explicit start | `init/1` traps exits and returns immediately; a continuation monitors the receiver, resolves credentials and invokes `subscribe/4` | Own parent supervisor and transport connection |
| Open success | Retains opaque handle and noncredential configuration; emits `subscription.open` | Handle/configuration must not contain credential material |
| Open failure | Receiver gets `{:error, error}`; process stops with `{:shutdown, error}`; no unsubscribe | Transport must account for any partially opened external resource; supervisor policy decides restart |
| Delivery | `{:wotex_transport, {:ok, value, meta}}` and decoded frames become `{:wotex_runtime, id, {:ok, value, meta}}`; failures become `{:error, %Error{}}` | Validate source trust, persist or discard |
| Overflow | With `max_queue_length`, an over-bound receiver mailbox drops the delivery (`subscription.drop`) or stops with `{:shutdown, :overloaded}` | Choose the bound and policy; unbounded by default |
| Receiver exit | Monitor fires; unsubscribe; stop `{:shutdown, :receiver_down}` | Restart or remove the child |
| Transport exit or status | Linked exit, `:transport_down` or `:session_lost` notify the receiver with `{:status, status}` then stop `{:shutdown, status}` after unsubscribe; `:reconnected` only notifies | Decide resubscription through restart policy |
| Explicit stop | Resolve stop credentials, call `unsubscribe/4` once (with a nil credential when resolution fails), set closed and terminate; simultaneous callers receive one close result and one typed `subscription_not_running` | Observe error outcome; remote cleanup is not guaranteed |
| Graceful parent shutdown | `terminate/2` attempts unsubscribe unless already closed | Allow sufficient shutdown budget; transport must honor deadlines |
| Forced kill/crash | Cleanup cannot be guaranteed; the receiver is not linked and survives | Reconcile external subscription/session; do not infer exactly-once delivery |
| Supervisor restart | New initialization, fresh credentials, and subscription attempt | Define loss/duplicate handling and replay policy explicitly |

The returned default restart policy is `:transient`, shutdown is 5,000 ms and
`Subscription.stop/2` defaults to 5,000 ms. A consumer wanting automatic
resubscription after session loss chooses `:permanent` and its own restart
intensity. No durable offset, process registry, automatic reconnect inside the
package, or deduplication is claimed.

## Limits, allocation and security

Runtime admits request ids up to 256 bytes, Context and Result metadata maps up
to 64 top-level entries, 32 binding profiles and 128 Forms for one interaction.
The threshold and one-over paths are executable evidence; rejected selection
never reaches credentials or transport. Nested metadata values and interaction
payloads remain consumer-bounded terms, and bindings decode protocol bytes
under their declared limits. The optional receiver mailbox threshold is
checked before each delivery. Per-interaction deadlines are propagated rather
than enforced by a hidden timer because synchronous callbacks must remain in
the caller. Thus no package claim is made for callback latency, total nested
term memory, transport allocation or constant-space execution.

The `telemetry` library is a runtime dependency. Its application owns one
handler table process; this package itself starts no process and attaches no
handler.

Credential-provider and transport configuration are retained opaque consumer
inputs and therefore SHOULD contain references to consumer custody, not raw
secrets. A credential returned by `resolve/4` is confined to the immediate
execution context and never retained in Request, Result, public errors or
subscription state. Port and request exception telemetry omits raw reasons and
stacktraces; only normalized kind/code and identity are emitted. Inspect
redaction is not secret-memory erasure or a sandbox. No new database, framework,
scheduler, credential store, policy engine or supervision root belongs here.

## Standards and compatibility

TD 1.1 operation vocabulary is inherited from `wotex`. The
[WoT Scripting API Note, 3 October 2023](https://www.w3.org/TR/2023/NOTE-wot-scripting-api-20231003/)
is conceptual guidance, not a claim to implement its JavaScript API. The exact
[TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the operation/Form baseline. WRT.01 claims only its listed Elixir mechanics.
Breaking callback, error, selection, default or shutdown behavior requires a
versioned specification/API change plus clean-consumer evidence. Package
version, normative-spec version and evidence-gate result are separate facts.
