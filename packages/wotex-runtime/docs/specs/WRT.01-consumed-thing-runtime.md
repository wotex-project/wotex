# WRT.01: ConsumedThing runtime mechanics

Specification: `WRT.01@1.0.0`. Package baseline: `wotex_runtime 0.1.0`.
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
   `subscribeevent`, and `unsubscribeevent` only when a selected profile and
   Form both declare the operation.
3. Form selection MUST be deterministic over TD form order and consumer profile
   order. It MUST return typed absence instead of guessing a transport.
4. A request MUST carry a caller-supplied request id and optional absolute
   deadline. The package MUST NOT call a clock or generate identity.
5. Security declarations MUST be passed to a credential port immediately before
   execution. Credential material MUST NOT enter public request values or errors.
6. Short operations MUST run in the caller process.
7. A long-lived observation or Event subscription MUST start only through an
   explicit child specification. Zero, one, and multiple named instances MUST
   work without application-global state.
8. Retry classification MUST return a decision; this package MUST NOT sleep or
   retry a potentially non-idempotent operation by itself.
9. A successful result records protocol exchange only, never physical effect or
   canonical state.
10. Graceful supervisor shutdown MUST request protocol unsubscription within
    the consumer-selected shutdown budget. Explicit stop MUST NOT unsubscribe
    twice. Forced termination and transport failures require consumer recovery;
    local process termination does not prove remote cleanup.

## Evidence

Tests cover every operation category, deterministic selection, unsupported
cells, credential isolation, transport errors, retry classification, and zero,
one, and multiple subscription instances.

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
| `Result.new/4` | request identity, operation, payload, metadata | Protocol result only; `value_test.exs` |
| `Credentials.resolve/4` | selected security, Form, context, opaque consumer configuration | Immediate credential resolution; no custody transfer |
| `Transport.request/3` | request, ephemeral execution context, consumer configuration | One synchronous protocol exchange in caller |
| `Retry.decision/3` | operation, failure class, explicit attempt/max/delay/idempotence | `:stop` or `{:retry, delay}`; never sleep, timer or retry |

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
is not silently expanded by Runtime; the TD-processing contract owns defaults.

## Execution and failure matrix

| Stage | Required behavior | Prohibited inference |
|---|---|---|
| Construction | Validate TD and declared ports before execution | Configured port is trusted/authorized merely because it exports callbacks |
| Selection | TD Form order first, profile order second; exact operation/scheme/media match | Pick a fallback transport after a negative match |
| Credentials | Resolve immediately before each start/request/stop exchange | Persist returned material in Context, Request, Result or subscription state |
| Transport | Check tagged callback returns; preserve request/operation correlation | External error term or arbitrary success is canonical truth |
| Failure | Stable Runtime error code/phase and nonsecret identity details | Raw external reason in error details |
| Retry decision | Only timeout/unavailable/rate-limited classes and admitted idempotence | Automatically repeat an Action after unknown physical effect |

Current retry defaults admit `readproperty` and `queryaction`; all other
operations require explicit `idempotent?: true`. Attempts and delays are
consumer inputs, not runtime scheduling. Current transport/credential exception
propagation and callback-return correlation require the additional vectors in
RT-C02 before declaring hardened execution; a tagged-error test is not an
exception-isolation test.

## Subscription lifecycle and ownership

| State / event | Package behavior | Consumer obligation |
|---|---|---|
| Child-spec construction | Returns inert map; requires id and receiver; resolves both Forms | Choose distinct id/name, receiver PID, restart and shutdown policy |
| Explicit start | `Subscription.start_link/1` resolves credentials and invokes `subscribe/4` | Own parent supervisor and transport connection |
| Open success | Retains opaque handle and noncredential configuration | Handle/configuration must not contain credential material |
| Open failure | Process does not enter active state | Transport must account for any partially opened external resource |
| Delivery | `{:wotex_transport, payload}` becomes `{:wotex_runtime, id, payload}` | Validate source trust, persist or discard; own overload policy |
| Explicit stop | Resolve stop credentials, call `unsubscribe/4`, set closed and terminate | Observe error outcome; remote cleanup is not guaranteed |
| Graceful parent shutdown | `terminate/2` attempts unsubscribe unless already closed | Allow sufficient shutdown budget; transport must honor deadlines |
| Forced kill/crash | Cleanup cannot be guaranteed | Reconcile external subscription/session; do not infer exactly-once delivery |
| Supervisor restart | New initialization and subscription attempt | Define loss/duplicate handling and replay policy explicitly |

The returned default restart policy is `:permanent`, shutdown is 5,000 ms and
`Subscription.stop/2` defaults to 5,000 ms. Therefore a consumer wanting a
normally stopped child to stay stopped MUST choose an appropriate restart or
supervisor-removal policy. No receiver monitoring, durable offset, process
registry, automatic reconnect, deduplication or bounded mailbox is claimed.

## Limits, allocation and security

Selection scans supplied Forms/profiles; input size and list cardinality remain
consumer-bounded. Runtime forwards terms without serialization, byte limits,
schema validation of interaction payloads, or mailbox credits. Per-interaction
deadlines are propagated rather than enforced by a hidden timer. Memory and
latency claims require measured bounded inputs, not a claim of constant space.

Credential configuration, transport configuration and metadata are trusted
consumer inputs. Inspect redaction is not secret-memory erasure or a sandbox.
RT-C02 must prove callback exceptions, forged returns, receiver failure and
oversized metadata behavior before stronger security/resource claims. No new
database, framework, scheduler, credential store, policy engine or supervision
root belongs in this package to close those claims.

## Standards and compatibility

TD 1.1 operation vocabulary is inherited from `wotex`. The
[WoT Scripting API Note, 3 October 2023](https://www.w3.org/TR/2023/NOTE-wot-scripting-api-20231003/)
is conceptual guidance, not a claim to implement its JavaScript API. The exact
[TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the operation/Form baseline. WRT.01 claims only its listed Elixir mechanics.
Breaking callback, error, selection, default or shutdown behavior requires a
versioned specification/API change plus clean-consumer evidence. Package
version, normative-spec version and evidence-gate result are separate facts.
