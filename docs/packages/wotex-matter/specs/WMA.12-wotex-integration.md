---
spec:
  id: WMA.12
  title: Wotex integration and evidence contract
  status: accepted
  version: 1.1.3
  owner: wotex-matter
  updated: 2026-09-18
---

# WMA.12 Wotex integration and evidence contract

This accepted specification makes [.10](WMA.10-software-contract.md) and
[.11](WMA.11-standalone-client-and-preservation.md) usable with the public Wotex
packages. The [catalogue](catalogue.yaml) and executable-evidence record identify
the accepted implementation. Every `I` requirement below is mandatory for
software completion.

## WMA-I01 — Dependency direction and owned values

The protocol's native client/value APIs work without constructing a Thing
Description, Runtime Context or BindingProfile. Mapping and Transport are leaf
adapters over those APIs. Compile dependencies remain the released `wotex` and
`wotex_runtime` requirements in `mix.exs`; `WOTEX_PATH_DEPS=1` is only the explicit
development override. No runtime sibling discovery, global registration or
application callback exists.

| Owner | Reused contract | This package's obligation |
| --- | --- | --- |
| Wotex core | [WTX.01](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex/specs/WTX.01-thing-description.md) and [WTX.02](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex/specs/WTX.02-affordance-values.md) version 1.1.0, [WTX.03](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex/specs/WTX.03-errors-extensions-and-compatibility.md) version 1.3.0: ThingDescription, Form, DataSchema, security references, bounded JSON/extensions | Use public constructors/accessors; do not copy TD parsing, default-operation tables or JSON-LD fetching into the protocol |
| Wotex Runtime | [WRT.01](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-runtime/specs/WRT.01-consumed-thing-runtime.md) version 1.4.0: ConsumedThing, Context, BindingProfile, Request, Result, Credentials, Transport, Subscription, Retry | Implement existing ports; preserve identity, deadline and ownership semantics |
| This protocol | .00/.10/.11: native values, operation validation, backend, errors and cleanup | Revalidate inputs at I/O boundaries; SDK delegation does not transfer this obligation to consumer code |
| Wotex Conformance | [WCF.01](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-conformance/specs/WCF.01-conformance-runner.md) version 1.1.0: isolated artifact/vector/evidence contracts | Optional external report integration; no production dependency in either direction |
| Wotex Lab | Explicit reference consumer and artifact adoption | May consume immutable public archives; a local protocol pass does not close Lab's claims |
| Wotex Directory / Nx / Continuum | Discovery values / numerical conversion / inert exchange values | Consumer composition only; no dependency, automatic registration, persistence or canonical state promotion |

The reference review used the checked-in contracts and public APIs of the
sibling packages in this repository at the specification versions in the table:
the [core package contract](https://github.com/wotex-project/wotex/blob/main/packages/wotex/CLAUDE.md),
[Runtime WRT.01](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-runtime/specs/WRT.01-consumed-thing-runtime.md),
the [HTTP binding contract](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-http/CLAUDE.md) and
the [MQTT binding catalogue](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-binding-mqtt/specs/catalogue.yaml).
These references identify reviewed contracts, not a claim that they are published
or a replacement for package-version constraints. HTTP/MQTT intentionally own
bindings only; their no-client rule does not erase this package's native profile.

## WMA-I02 — Explicit Runtime profile factory

Add pure `profile/0` on `Wotex.Matter`, returning a `Wotex.Runtime.BindingProfile` for
`:oneshot`. Add `profile/1`, accepting only the atoms below and returning
`{:ok, profile}` or `{:error, %Error{code: :unsupported_profile}}`.
No constructor checks installed modules, opens a backend, reads environment or
advertises a mode whose required implementation/evidence has not been admitted.
Until a mode is implemented it returns unsupported. Mode availability is a static
library-version decision; actual configured peer capabilities still fail explicitly.
`profile/0` requires executable baseline integration evidence.

| Mode | BindingProfile id | URI schemes | Exact operations | Stream meaning |
| --- | --- | --- | --- | --- |
| `:oneshot` | `:matter` | `matter` | readproperty, writeproperty, invokeaction | none |
| `:controller` | `:matter_controller` | `matter` | readproperty, writeproperty, invokeaction, observeproperty, unobserveproperty, subscribeevent, unsubscribeevent | attributes / Matter events |

The baseline profile has `media_types: []`. The baseline adapter exposes native protocol values, not a general content decoder. The empty media-type set is an explicit Runtime selection wildcard, not a claim that JSON/XML/CBOR serializers are implemented. The baseline preserves Forms that omit contentType; the reviewed core Form.to_map/1 preserves that omission. An explicitly supplied contentType fails with :unsupported_content_type before I/O until a separately named serialization profile defines it. This is the accepted native binding policy; current-profile behavior is recorded separately in .02. Do not interpret TD 1.1's application/json default as evidence of a JSON wire encoding for these native protocols. The .02/.10 conversion selectors are authoritative. A future negotiated serialization profile requires a separate named profile and exact codec fixtures. Do not advertise media-type conformance from this wildcard.
All modes inherit the same media policy unless .10 states a narrower supported
cell. A profile declares possible operations, not backend presence, authorization
or physical effect. The caller passes profiles in precedence order and routes
by their exact id in the transports map. No adapter fallback is permitted.
Every other TD operation, including Thing-level aggregate operations, is unsupported.

Both target modes use the first-party C++ backend: .13 defines per-operation
existing-store ownership for :oneshot and persistent ownership for :controller.
The retired .03 Python factory is no longer a runtime option.

The sample OnOff attribute is read-only; setting a light uses the On or Off command through an Action. Runtime paths are concrete. Native wildcard reads, commissioning, fabric custody and recovery do not become implicit Form operations.

The integration test constructs the real consumer boundary as follows (target
factory API; `td_map`, `transport_options` and credential port are explicit test
inputs, not ambient configuration):

```elixir
{:ok, td} = Wotex.ThingDescription.from_map(td_map)
profile = Wotex.Matter.profile()
{:ok, consumed} = Wotex.Runtime.ConsumedThing.new(td,
  profiles: [profile],
  transports: %{Wotex.Runtime.BindingProfile.id(profile) =>
    {Wotex.Matter.Transport, transport_options}},
  credentials: {TestCredentials, credential_options})
{:ok, context} = Wotex.Runtime.Context.new(request_id: "read-1", deadline: deadline)
Wotex.Runtime.ConsumedThing.read_property(consumed, "reading", context)
```

`TestCredentials.resolve/4` admits only a selection whose names are `["none"]`
and definitions are `%{"none" => %{"scheme" => "nosec"}}` for this synthetic
fixture; return `{:ok, nil}` there and a structured failure otherwise. It is a
test port, not a production credential default. Target-configured secure native
backends retain all .10 security requirements even when this test selection
supplies no immediate credential. The protocol peer adapter uses only the input's
`peer_reply` stimulus; expectations remain exclusively in the asserting test.

## WMA-I03 — Mapping, route and value boundary

Use `ThingDescription.from_map/1` or `parse/2`, and `Form.new/2` with its real
Property/Action/Event context. Let Runtime select the Form and resolve base/href.
The transport consumes `Request.resolved_href`; it must not independently resolve
a different base or silently replace the request's selected Form.
The decimal fabric ID must exactly equal config.target and the initialized controller fabric. The node/endpoint/cluster/member is revalidated in that fabric, with peer ACL enforcement.

Preserve unknown extension terms using `Form.to_map/1`, including nested values.
Reject invalid known protocol/security selectors before I/O. An unknown extension
is retained data and cannot become an executable option. Keep protocol addressing,
wire conversion and units separate: a native integer is not automatically a
particular temperature unit or a valid application DataSchema instance.
Core `Wotex.DataSchema.new/1` validates the schema description itself. Validation
of an observed application value against that description is a separate explicit
consumer concern; neither core nor Runtime is claimed here to perform it. Never
call core internal schema-validation modules as an application-value validator.

“Before I/O” in a Transport rejection means zero protocol acquisition or
transmission. ConsumedThing resolves its credential port before invoking Transport;
this package cannot claim that an external credential resolver performed no I/O.
The resolver must enforce its own policy and bounds. Native API validation still
precedes credential reads performed by this package itself.

Return `Result.new(request.request_id, request.operation, payload, opts)` after
full protocol validation. Use status `:ok` for a completed representation or
acknowledgment. Use `:accepted` only where the native protocol result explicitly
means acceptance with a pending result; never infer it merely because an operation
is a write. Protocol numeric status belongs in bounded metadata, not Result.status.
False, zero, empty binary, empty list and explicit null cannot be conflated with
an absent response. Protocol type/status/timestamps remain the .10 projection.
Binary payloads remain BEAM binaries; JSON fixture normalization uses the explicit
`{"type":"bytes","base64":"..."}` envelope only for transport across the test harness.

### Controller payload projection

The `:oneshot` profile retains .02/.03 scalar/JSON-compatible bridge results.
For `client: Native`, require `lifecycle: :oneshot` and .13's existing-store
options. Convert inputs through the admitted descriptor schema before acquisition;
convert successful typed read results through that same descriptor to scalar,
null, array or schema-record values. A write acknowledgement is the string
`"written"`; a status-only command result is nil. Other admitted command results
use their response descriptor. One-shot metadata is empty. The controller profile
requires `lifecycle: :persistent` and retains its distinct typed projection.
Neither native mode admits a Python factory option.
The `:controller` profile uses the .11 report contract with one anonymous outer
`TLV.element()` as Result.payload and as each stream value. Do not unwrap it to a
scalar or silently change the oneshot profile. For example a Boolean false is
`%{tag: :anonymous, type: :boolean, value: false}`; explicit null uses type :null.
Nested containers preserve their tags and native byte values.

A successful attribute read/observation has metadata exactly
`%{matter_kind: :attribute, path: %{fabric_id: f, node_id: n, endpoint: e,
cluster: c, member: a}, status: 0, data_version: uint32_or_nil}` before Runtime
adds its own request identity on streams. A write returns payload :written with
metadata `%{matter_kind: :attribute, path: path, status: 0}` after acknowledgment.
An Action returns the typed command response element (or nil for status-only),
with `%{matter_kind: :command, path: requested_path, response_path: path_or_nil,
status: 0}`. A subscribed Event returns its typed event element with
`%{matter_kind: :event, path: path, status: 0, event_number: uint64,
priority: numeric_priority, timestamp: %{kind: :epoch | :system, value: ms}}`.
An absent data version is nil, never zero; failure paths return Error, never a
successful null. Runtime projections use descriptor-defined types, not a false
claim that the SDK retained original wire integer width. Concrete profile Forms
select exactly one path. Batch result shapes stay on the native API.

## WMA-I04 — Errors, credentials and deadlines through Runtime

Extend the native Error value additively with `class`, one of `:timeout`,
`:unavailable`, `:rate_limited`, `:protocol`, `:permanent` or nil. Keep `code`,
`field`, `details`, `retryable` and `effect` for direct protocol consumers.
Runtime's current `Error.with_cause/2` retains only module/code/phase/class from
external errors. It discards native details, effect and retryable; do not claim
these survive a ConsumedThing failure, copy them into secret-bearing text or
modify Runtime to fit this package.

| Native failure | Runtime-visible class | Required retry test |
| --- | --- | --- |
| Pre-I/O deadline, or failed read deadline | timeout | readproperty, attempt 1/max 2 -> retry; mutation -> stop by default |
| Unavailable peer before send, or failed read connection | unavailable | same default operation restriction |
| Admission busy before send | rate_limited | explicit attempt budget required |
| Wrong correlation, malformed result, invalid remote protocol response | protocol | stop |
| Invalid input/route/profile/security, unsupported operation/type | permanent | stop |
| Mutation with effect unknown, including timeout after send | permanent | stop even with consumer idempotent?: true |
| Unclassified bounded failure | nil | stop |

The unknown-effect mutation rule overrides the general timeout/unavailable rule.
Native retryable must be false whenever effect is unknown. The finite class
classifies a failure; this library does not schedule a retry. Add executable tests
through `ConsumedThing` and `Runtime.Retry.decision/3` for this exact table.

Credentials are resolved by the consumer's explicit `Credentials.resolve/4`
implementation using selected TD security definitions. Returning nil means that
port accepts the selected requirements without immediate credential material;
the binding still enforces its .10 backend security policy. A sample no-security
resolver must reject other requirements, not return nil for every scheme.
Never put credentials in a Form, Request, Result, handle or telemetry. Persistent
native credential custody is explicit configured state and does not relax the
ExecutionContext's immediate-use lifetime. Follow .10's exact accepted credential
types and stream restrictions; unsupported combinations fail before acquisition.

Honor one interaction budget through mapping, route checks, connect/authenticate,
exchange and decode. Cleanup may use only the explicit C03 grace after failure;
it never extends the deadline for an operation to succeed. Convert `Context.remaining_ms/2` once using the matching
clock kind, then track a monotonic deadline. A nil Runtime deadline still uses
the .00 finite transport ceiling. Queue and setup time never reset the budget.

## WMA-I05 — Runtime stream ownership

For modes listing streams, the pid passed to `Transport.subscribe/4` is the
**Runtime subscription owner**, not the final consumer receiver. Add a private
`RuntimeRelay` process owned by and monitoring that pid. The relay is the receiver
of the unchanged native subscribe/2 API; it translates native deliveries to
`{:wotex_transport_frame, frame}` and terminal statuses for the Runtime owner.
Merely setting the native receiver to the Runtime owner is invalid: Runtime does
not understand the native `{:wotex_protocol, ref, event}` envelope.

The relay owns its native Session/subscription, starts only on this explicit call,
and has opening/bound/closing/closed states. It returns the transport handle only
after native establishment. During opening it buffers at most 64 native reports;
excess reports fail with receiver_overflow and cleanup. On binding, validate
reference/generation/target before releasing those reports in order. Late,
unrelated or canceled reports are discarded; no report can reopen the relay.
In bound state use the C05 owner-queue check before forwarding. Frame values are
`{:value, value, metadata}` or `{:error, library_error}`; decode_frame/3 validates
and applies the specified protocol conversion, returning the corresponding Runtime
result. The relay has already validated native session identity; raw external
messages cannot bypass that association. Metadata carries no native SDK handles.

On stop, failed establishment, Runtime-owner death or native terminal failure,
the relay closes the native subscription/session exactly once and exits within
C03's grace. Its work must remain interruptible during native I/O. No consumer
receiver, borrowed backend or consumer supervisor is stopped. The transport
handle identifies this relay and its generation, not an arbitrary target URI.
`decode_frame/3` runs in that owner's process and returns validated value/metadata,
a bounded error, or `:ignore` for specified control/unrelated frames. Do not send
native `{:wotex_matter, reference, event}` messages to Runtime and expect decoding.

The consumer obtains `ConsumedThing.observation_child_spec/4` or
`event_subscription_child_spec/4` and explicitly supervises it. Integration
examples/tests set `max_queue_length: 1000, overflow: :stop, restart: :temporary`
and an explicit id/receiver; Runtime otherwise permits an unbounded queue/default
drop behavior. This receiver bound is separate from the native-owner queue bound
in .00. Receiver death, open failure, explicit stop, canceled timers and terminal
loss must each release every owned native resource within .00's cleanup grace.

Cancellation uses the exact established route and generation. The stop Form may
be different and cannot redirect cleanup. Runtime may call unsubscribe with nil
credentials after failed stop-credential resolution; release local resources and
use already owned native state without retaining an earlier ExecutionContext.
Send only Runtime's supported statuses: reconnected for a retained session,
session_lost or transport_down for terminal loss. Terminal loss stops the Runtime
owner; automatic resubscription belongs to explicit consumer supervision.
No-stream modes return a structured unsupported error without creating a process.

## WMA-I06 — Acceptance through public packages

The concrete [integration corpus](../../../../packages/wotex-matter/priv/fixtures/wotex-integration-v1.json) fixes a
synthetic TD, selected route/command and public payload projection. It is labelled
specified_unexecuted until its assertions run. JSON validity or an identifier
in a fixture does not accept a work package. The driver receives only input,
never expectation; the test process compares the returned projection. Atoms become
finite documented strings and bytes use the envelope above. Exclude pids, refs,
clocks, secrets and implementation-specific map keys from normalized observations.

`runtime_read` projects the native message to its listed operation and typed
address fields; additional internal fields are excluded explicitly. Peer reply
kinds select an exact protocol PDU or a tagged Client success as named by input.
The finite `scripted_client` selector resolves to a test-only Client module; its
explicit target/options come from input, never from expectation. Clock offsets
are relative to the test-owned monotonic origin. A loopback peer may reserve an
ephemeral port and substitute its one symbolic endpoint consistently in input
and normalized observation; it cannot change addresses using expected output.
`error_retry_projection` injects the named failure stage into the native error
classification boundary, obtains the library Error (the expected class is not
supplied), and passes it through a test Runtime Transport's failure return and
ConsumedThing. It then calls Retry with the input options. `retained_native_effect`
asserts whether Runtime's cause includes that field; it must be false. This
classification test does not advertise support for the input WoT operation in
a production profile; its test profile explicitly admits that one operation.
The native error fields shown are stimuli,
not a bypass of the production classifier or a consumer permission to set class.
The full I04 table also needs malformed/unclassified and default mutation cases.

Add `test/wotex/matter/runtime_integration_test.exs`, exercising real core and
Runtime public APIs with an explicitly selected deterministic protocol peer/port.
Record each I requirement and concrete case ID in its assertion name. Do not
construct forged Request structs as the only integration proof. Cover:

1. Real TD construction, contextual defaults and two Form choices; use two
   explicit profiles when supported, otherwise test the unsupported second mode; exact resolved href, target, command and unchanged extensions.
2. Read payload identity and write/Action acknowledgment for every declared cell;
   unsupported context, route, media/security selector and malformed input cause
   zero acquisitions/requests. No native-only operation appears in a profile.
3. The complete I04 error-class/retry table through ConsumedThing, plus wrong
   Result identity/operation, false/zero/null and bounded non-secret metadata.
4. Every declared stream through an actual Runtime child specification: initial
   report only when the native protocol provides one (otherwise assert none),
   equal fresh reports, unrelated/stale frame, failed open, stop Form with
   changed target, overflow, receiver death and terminal-status cleanup.
5. No native SDK/physical device is needed for these port-contract tests. Repeat
   the selected complete interaction with the required .10 software peer to
   establish protocol evidence. Injected-port success is labelled accordingly.

For final acceptance, run from an immutable package archive and isolated consumer
project with public core/Runtime dependency versions, not an accidental shared
build. Record the subject, dependency, fixture and adapter SHA-256 identities,
exact Elixir/OTP versions, command, result and cleanup counts. Repeat the minimum
and current runtime matrix in .00. A path-dependency gate proves local integration;
it does not prove released artifact adoption.

[Wotex Conformance WCF.01](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-conformance/specs/WCF.01-conformance-runner.md) version 1.1.0
requires expectations to stay runner-side and subjects to stay outside its
production dependencies. This corpus is a protocol-test interchange, not an
already accepted WCF corpus. Its current document-operation normalization does
not automatically support these native protocol operations. A later external
adapter must use an admitted WCF operation/schema or explicitly version that
extension in the owning project; never relabel a local test as conformance.
No external report integration is required to implement these protocol tests.

## API and evidence classification

Profile factories, explicit selector validation and Error.class must satisfy
I01–I06 with public-boundary assertions and the required software lanes. Current
implementation scope is recorded in .02 and executable evidence. A scenario
family may need many concrete cases; attaching identifiers to unrelated passing
tests cannot establish acceptance.

W3C terminology and Form/default-operation ownership refer to
[TD 1.1, Recommendation 2023-12-05, sections 5.3.4.2 and 5.4](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/).
The [Scripting API Note 2023-10-03](https://www.w3.org/TR/2023/NOTE-wot-scripting-api-20231003/)
is conceptual guidance, not an API conformance claim. The client modes, limits,
fixture projection, retry restrictions and test gates here are library policy.

The native implementation and bounded callback flow follow [WMA.13](WMA.13-native-backend.md). Runtime owns the final subscription process; an
opening worker owns only its temporary call. Native resources must be tied to
the final owner before establishment waits, and late successful native replies
must be cancelled when that owner is gone. Store/SDK ownership remains explicit
native configuration; no immediate ExecutionContext credential is retained.
