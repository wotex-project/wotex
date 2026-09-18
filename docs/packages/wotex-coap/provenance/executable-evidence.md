# CoAP executable evidence

Evidence describes exact source cohorts. A passing package gate does not accept
all secure transports, software stress or artifact adoption.

| Cohort | Executed evidence | Limits |
| --- | --- | --- |
| source digest `3ecd430d192f` | Five independent libcoap UDP/PSK DTLS tests on Elixir 1.20.2 / OTP 29.0.4; normal and native ASan/UBSan builds | UDP, Block1/Block2, authenticated PSK operations and Observe/cancel; no PKI or OSCORE claim |
| `1479968` | Complete latest-toolchain gate, 189 tests, 95.6% coverage | Native PKI certificate/identity/CRL tests use an OTP DTLS peer |
| `32bceed` | Complete latest-toolchain gate, 191 passing checks (2 doctests, 8 properties, 181 tests), 95.5% coverage | Documentation/contract cohort; interop is explicitly excluded from the ordinary gate |

The [UDP/DTLS peer receipt](software-udp-dtls-v1.json) contains the independently
verified source digest, exact peer source/archive/binary hashes, commands,
result/log digests and zero retained peer/UDP resources. This receipt identifies
the executed source digest and does not assert an independently verified Git
commit association. Native peer builds use libcoap 4.3.5 at
`7cf7465b784baded4de183290c547d582becfd28`. The executed orchestration is Python;
protocol traffic is exchanged with native `coap-server`. This is a historical
receipt and does not transfer acceptance to the later .13 Mix tasks. The tracked
CoAP source and package no longer contain Python. The sanitizer lane is macOS;
the required Linux full-software lane is a separate acceptance obligation.

## Implemented assertions

Tests under `test/wotex/coap/` cover codec boundaries, exchange correlation and
lifecycle, complete Block1/Block2, owned Observe registration/renewal/cancellation,
discovery and RFC 6690 parsing, native PSK/PKI admission and real Runtime UDP
Property/Event streams. The native PKI suite checks exact DNS/IP SAN, certificate
time/usage, unknown critical extensions, untrusted roots, CRL expiry/signature,
revocation and isolated simultaneous trust snapshots. `dtls_test.exs` includes
replayed and tampered-record outcomes and bounded cleanup. This does not claim
continued service after every malformed DTLS record or a complete certificate
chain-depth fault matrix.

`runtime_error_test.exs` executes the I04 finite class/retry table and concrete
integration cases F02–F07 through real ConsumedThing calls. A separate loopback
UDP test transmits read/write requests and proves that an uncertain mutation
stays permanent through Runtime even with explicit idempotence. Native effect
and diagnostic details are not retained in Runtime causes.

`profile_test.exs` executes F01 over UDP through the public profile and real
ConsumedThing route, including the preserved extension and zero remaining
sockets. It covers all three unary operation/media cells, explicit null/false/
zero/empty outcomes, rejected forged contexts/profiles and a complete response
held past the callback deadline. `runtime_stream_test.exs` uses the public
Observe profile for its Property/Event lifecycle assertions.

`runtime_dtls_test.exs` executes the public DTLS profile through ConsumedThing
with real OTP PSK and PKI peers. Its assertions cover scoped immediate/configured
credentials for read/write/Action calls, zero-I/O invalid custody/profile cells,
authentication failure or handshake deadline without a CoAP mutation, configured
Property/Event observations, exact-route cancellation, and receiver death during
and after establishment. It checks authenticated socket release and credential-
free Runtime handles and diagnostics. These are OTP peer tests, separate from
independent libcoap secure interoperability and the complete software matrix.

`security_oscore_test.exs` executes S06's pure credential boundary. Exact and
generated cases cover secret, salt, sender, recipient and ID Context byte limits;
distinct endpoint IDs; absolute UTF-8 store paths; omitted ID Context
normalization; forged structs; cross-mode fields; and redacted inspection. The
constructor performs no store or network access. These assertions do not admit
an OSCORE connection or accept the planned native owner.

`test/interop/dtls_pki_test.exs` adds independent libcoap PSK/PKI native
operations, Observe/cancel, certificate/CRL faults and authenticated-record
replay/corruption assertions. It also runs real ConsumedThing unary operations
for all three media types, both credential custody modes and secure Property/Event
subscriptions through explicit cancellation and receiver death. Its ExUnit-owned peers and record proxies check
cleartext refusal and actual listener/client socket release. The
[DTLS verification guide](dtls-interoperability.md) specifies source/build pins,
reproduction and remaining limits. The historical UDP/PSK receipt above does not
acquire PKI coverage from these later tests.
The [native sequence receipt](native-sequence-v1.json) identifies a real public-API
libcoap regression with two narrowly scoped source patches. Rejected sender
reservations emit no UDP datagrams; accepted sends remain inside the reserved
boundary. The test passes on macOS and Linux with ASan/UBSan and leak detection.
It does not exercise a durable filesystem, a native Port or an independent peer.
The [native store receipt](native-store-v1.json) identifies exact RFC 8613
C.1–C.3 derivations, persisted directional-key reuse rejection, filesystem/lock
faults, interrupted atomic replacements, SIGKILL, capacity and sequence bounds.
Its real libcoap callback assertions cover durable-write failure before wire
transmission. These primitives do not implement the production Port or accept
end-to-end restart/replay behavior through that owner.
The [native JSON receipt](native-json-v1.json) identifies exact-source parser and
framer tests for UTF-8, decoded duplicate keys, exact 64-bit integers, finite
allocation bounds, split/coalesced input and terminal EOF/failure. These native
primitives do not accept the complete helper protocol or its report-credit/body
assembly behavior. The [native body/credit receipt](native-body-credit-v1.json)
identifies bounded payload/hash validation and cumulative credit primitives.
Actual process/Port saturation, cancellation deadlines and complete native-v1
traces remain unaccepted. The [native block receipt](native-block-v1.json) records
public-API raw UDP fault-peer cases for advertised/actual body bounds and changed
ETag behavior. Linux probes assert requested SDK binary lengths before allocation;
negative controls fail against the preceding SDK patch set. The peer exercises
the shared block engine, not an independent OSCORE security implementation.
The [native protection receipt](native-protection-v1.json) records 15 forged
plaintext responses to protected GET/POST/PUT requests and three positive controls (ordinary UDP, empty RST and a protected exchange).
Its protected client/server exchange uses the same SDK; the raw UDP fault peer
is independent of the SDK response encoder. A negative control exposes plaintext application dispatch without the response-admission patch. These
fixtures do not accept durable replay, production owner/bridge restart,
independent secure interoperability or complete stress/matrix closure required
by [the ordered plan](../plans/software-implementation.md).

The [native command receipt](native-command-v1.json) records 86 C11 admission
cases on macOS and Linux with the Linux AddressSanitizer and UndefinedBehaviorSanitizer
lane enabled. Observe commands require an explicit Boolean `renew`; omission,
null, numbers, strings and objects fail before filesystem, socket or SDK access.
This structural decoder evidence does not accept the production worker, Port
owner, request correlation, report credit or durable-session integration.

The [native lifecycle receipt](native-worker-lifecycle-v1.json) binds the first
same-binary worker cohort. Three macOS ExUnit cases execute the public custody
entry and assert ready/open/body/request/close output, escaped correlation IDs,
exclusive lock contention, consumed-identity rejection and malformed-input
teardown. A Linux ASan/UBSan build feeds the internal worker a coalesced trace
and compares every output byte. The worker decodes and erases credentials,
durably consumes boundary 32, holds the store through close and returns
`native_unavailable` for request before network I/O. It does not link libcoap;
protected requests, Observe, credit, cancellation, response encoding, replay,
saturation and the final production executable remain unaccepted.

The [native worker exchange receipt](native-worker-exchange-v1.json) binds the
next production source cohort. The worker verifies libcoap 4.3.5, creates one
fixed-suite OSCORE context/session, supplies the durable store callback, and
uses libcoap's token, retransmission and whole-body block engine for one active
unary request. A same-stack protected peer executes GET with query/Accept and
Block1 POST with an associated verified body through the public custody entry. It
asserts exact response option/payload projection, explicit empty payload and
credential-free stdout on macOS and Linux; the Linux build runs with
ASan/UBSan and leak detection. That receipt does not accept streamed response
output, Observe, credit, cancellation, replay, independent secure
interoperability or Mix build/run orchestration.

The [native worker stream receipt](native-worker-stream-v1.json) binds the next
production source cohort and its sixth ordered SDK patch. A same-stack protected
peer receives a 32,769-byte Block2 body through exact begin/chunk/end frames and
a final Message body reference, then completes a Block1 POST on the same session.
This sequence asserts that completed whole-body delivery releases libcoap's
first-response hold. Both public-custody macOS and Linux ASan/UBSan/leak lanes
verify the complete sequence. Observe, credit, cancellation, replay, independent
secure interoperability and Mix build/run orchestration remain unaccepted.

The [native worker Observe receipt](native-worker-observe-v1.json) binds the
next production source cohort and its seventh ordered SDK patch. The patch
preserves the authenticated response Partial IV used as the 24-bit OSCORE
Observe value. Through public custody, the same-stack peer proves that
registration emits its control result before the retained initial report,
zero credit emits no report, cumulative credit advances only after complete
stdout writes, a fresh notification advances both Observe and report sequence,
and cancellation uses the original token with no later report. Both macOS and
Linux ASan/UBSan/leak lanes execute the sequence. Streamed reports, renewal, the
observation fault matrix, replay, independent secure interoperability and Mix
build/run orchestration remain unaccepted.

The [native worker streamed-report receipt](native-worker-report-stream-v1.json)
binds the next production source cohort. A fresh protected 32,769-byte
notification emits exact body begin, 32,768-byte and one-byte chunks, body end,
and final report frames with contiguous credit sequences and a body reference.
The final Message retains the notification's authenticated Observe value and
five-field metadata. Cancellation then completes through its reserved control
path while all five report credits remain outstanding. Both macOS and Linux
ASan/UBSan/leak lanes execute the sequence. Renewal, Property/Event overload
faults, replay, independent secure interoperability and Mix orchestration remain
unaccepted.

The [native worker renewal receipt](native-worker-renewal-v1.json) binds the
next production source cohort. After a streamed report advertises Max-Age zero,
the worker waits the one-second minimum, sends GET Observe=0 for the original
route and token with a new Message ID, and emits the authenticated renewal
response as the next credited report. A separate public-custody run proves that
`renew: false` still emits its complete initial Max-Age-zero report, then sends
best-effort token-matched cancellation, emits exactly one `observation_stale`
terminal envelope and exits cleanly. Both macOS and Linux ASan/UBSan/leak lanes
execute both policies. Negative renewal responses, renewal deadline and explicit
cancel races, Property/Event overload faults, replay, independent secure
interoperability and Mix orchestration remain unaccepted.

The [native worker observation-fault receipt](native-worker-observation-faults-v1.json)
binds the next production source cohort. Separate protected renewals return a
negative status, omit Observe, change Content-Format or remain silent through
the finite deadline; the worker emits `remote_response` with status,
`invalid_observation_response`, `representation_changed` or `timeout`
respectively. The finite BEAM wire vocabulary admits the newly executed invalid
renewal code. In two further public-custody runs, eight unacknowledged reports
exhaust credit. Two later Property reports coalesce to the latest complete value,
while one pending Event report followed by another emits
`overlapping_event_report` and token-matched cancellation. Both macOS and Linux
ASan/UBSan/leak lanes execute this matrix. Duplicate/stale/wraparound injection,
an in-flight renewal/cancel race, actual output-pipe saturation, replay,
independent secure interoperability and Mix orchestration remain unaccepted.

The [native worker freshness receipt](native-worker-freshness-v1.json) binds the
next production source cohort. The worker uses a standalone native admission
primitive that executes equal, older and exact half-range rejection, the
strictly-greater-than-128-second escape, same-serial renewal and fresh
representation-change ordering. Stale inputs carry a changed Content-Format and
leave all accepted freshness/identity state unchanged. A further public-custody
run starts the protected peer's sender sequence at FFFFFF and delivers the next
authenticated notification with Observe zero. Both macOS and Linux sanitizer
lanes execute the primitive and protected wrap. Authenticated duplicate/stale
injection through the complete protected exchange, the renewal/cancel race,
actual output-pipe saturation, replay, independent interoperability and Mix
orchestration remain unaccepted.

The [native worker renewal/cancel receipt](native-worker-renewal-cancel-v1.json)
binds the next production source cohort. A protected zero-Max-Age subscription
starts renewal with its original token and a new Message ID, then receives an
empty acknowledgment so renewal remains in flight. The cancel command first
uses libcoap's tracked path; when that cannot submit, the exchange builds a
public-API GET Observe=1 fallback with the original route, token and Accept.
The peer receives exactly one cancellation with another Message ID. Because no
application-usable confirmation follows, the command returns exact `timeout`,
closes the worker cleanly and permits no further server report. macOS and Linux
sanitizer lanes execute the same trace. Successful race confirmation, an
intervening Observe response before confirmation, authenticated duplicate/stale
injection, actual output saturation, replay, independent interoperability and
Mix orchestration remain unaccepted. The
[pending owner-loss receipt](native-worker-pending-owner-loss-v1.json) corrects
the cause of that `timeout`: libcoap's OSCORE send hold delayed the cancellation
past the command deadline, and without it the peer's response confirms the
cancellation.

The [native worker owner-cleanup receipt](native-worker-owner-cleanup-v1.json)
binds the next production source cohort. After a protected observation is
established and its first credited report is written, the harness closes the
public custody owner's input without a close or cancel command. Custody
propagates EOF and starts its finite teardown; worker exit cleanup sends one
best-effort Observe=1 request with the original route and token before releasing
the libcoap session. The peer removes its observer, custody reaps the helper and
returns exact owner-loss status within 1,000 ms, and the context lock is released.
macOS and Linux sanitizer lanes execute the same trace. Owner loss during pending
registration, renewal or cancellation, receiver death through a production
BEAM owner, actual output saturation, replay, independent interoperability and
Mix orchestration remain unaccepted.

The [native worker output-saturation receipt](native-worker-output-saturation-v1.json)
binds the next production source cohort. After establishment and initial credit,
the harness fills the actual owner output pipe until a nonblocking write returns
`EAGAIN` and performs no further owner reads. Two bounded credit intervals then
dispatch fourteen protected 16 KiB notifications whose base64 payload bytes
alone exceed custody's 262,144-byte output capacity. The worker continues
protected network progress while report output is backpressured. Owner EOF still
causes one original-route/token cancellation, peer-observer removal, exact
owner-loss status and resource cleanup within 1,000 ms. macOS and Linux sanitizer
lanes execute the same trace. Actual BEAM Port-mailbox sampling, reserved-control
delivery with both channels saturated, pending-operation owner loss, replay,
independent interoperability and Mix orchestration remain unaccepted.

The [native worker network-wait receipt](native-worker-network-wait-v1.json)
binds the next production source cohort. The preceding worker polled only its
owner pipes with a 50 ms interval and serviced libcoap without waiting on its
socket, so every protected round trip waited for that interval; a 20,000-byte
Block1 upload took 4,047 ms. The worker now waits on libcoap readiness and its
next timer together with the owner pipes. An epoll build polls libcoap's
descriptor and bounds the wait with `coap_io_prepare_epoll`; other builds pass
the owner descriptors to `coap_io_process_with_fds`. A zero-timeout poll then
reports exact owner descriptor events, so pipe failure, EOF and closing behavior
are unchanged. The production harness completes 32 sequential protected GET
exchanges in less than 1,000 ms; the preceding worker failed that assertion
after 3,532 ms. The complete harness, including every earlier protected trace,
passes on macOS through `mix wotex.software.build` and on Linux with ASan/UBSan
and leak detection.

`native_command_encoder_test.exs` executes six exact tests for the matching
BEAM transmit boundary. It encodes all nine operations, canonical byte values,
explicit OSCORE credentials and exact five-field lines; omits absent optionals;
checks path, scalar, body-chunk and 128 KiB line bounds; and allocates each
decimal uint64 request identity once before exhaustion. The immutable allocator
retains no command or credential. These tests do not write a Port or prove that
the production helper accepts the lines.

`native_connection_test.exs` executes sixty-four contract-injection tests for the
BEAM process boundary. The tests launch the manifest-verified executable through
the exact `--custody ABS_DIRECTORY` entry, inspect the open and close envelopes,
and assert the pinned ready identity, monotonic correlation, finite ready/close
waits and credential-free retained/status state. The connection owns one
generation-bound admission table; full ordinary capacity cannot block its
separate close control, concurrent close callers join one termination, and an
abandoned close initiator is reaped. Normalized requests execute in FIFO order,
charge queue time to the deadline and correlate complete inline or streamed-body
Messages. Stream events tolerate arbitrary Port splits and coalescing, bind to
the active request ID, verify the complete 32,769-byte body and consume its
reference exactly once before delivery. Failed hashes, foreign IDs and an
unreferenced completed body close without partial delivery. The tests distinguish
absent and explicit empty outbound bodies, verify exact 32,768-byte upload chunks,
hash, offsets, monotonic command IDs and final body reference, and preserve
effect `none` for upload error, timeout, close and body-ID exhaustion before the
native request is submitted. Upload command exhaustion, rejected Port writes and
a cancelled submission marker also close before mutation dispatch. The tests
distinguish cancelled queued mutations from submitted mutation
uncertainty, reject forged capabilities before native I/O, reclaim caller loss,
and close on active timeout, malformed response, ID exhaustion or failed Port
write. Malformed, duplicate, truncated and oversized output closes the
generation. A helper that exits with status 0 and no partial frame while close is
active completes that close with `:ok`, and a second close also returns `:ok`; the
same exit during an active GET or PUT returns `connection_closed` with effect
`none` or `unknown`. A nonzero exit during close remains `native_protocol_error`.
Killing the configured owner releases the exact helper within
1,000 ms. Five public-boundary tests select this owner only for explicit
`coap` OSCORE configuration, preserve the two-field session, normalize an absent
or explicit empty body and formats, dispatch through `send/2` and method helpers,
reject mismatched or incomplete selection before process creation, and dispatch
discovery with its exact 65,536-byte native response ceiling. The discovery
cases accept an exact streamed limit and reject a 65,537-byte declaration before
assembly. Native Observe cases reject invalid admission before Port traffic,
open initial zero credit, deliver correlated inline and 32,769-byte streamed
reports, advance cumulative credit only after validation, and cancel the exact
subscription while report credit is in flight. Concurrent cancellation callers
join one close, receiver death releases the helper, and reports arriving during
cancellation are validated without public delivery. The injected executable is
a protocol fixture; these tests do not accept the production libcoap worker or
an actual protected exchange.

`runtime_oscore_test.exs` executes the explicit `:coap_oscore` BindingProfile
through real ConsumedThing unary and Property-observation calls. Unary dispatch
uses an immediate typed credential, while Observe uses configured custody and a
nil immediate credential. The relay validates the native route, buffers the
complete initial report, decodes its five-field metadata, and cancels the exact
subscription generation. Security-mode ambiguity, cross-scheme credentials and
a missing backend fail before helper creation. The manifest-bound executable is
a deterministic protocol fixture; this evidence does not accept the production
libcoap worker, durable store behavior, protected traffic or independent OSCORE
interoperability.

`native_admission_test.exs` executes four exact tests for the WCO-N02 pre-mailbox
capacity primitive. Ninety-six concurrent callers produce exactly 64 ordinary
leases and 32 busy results. Separate singular close control prevents later
ordinary admission; owner death and deadline expiry are observable, generation
and table ownership reject foreign capabilities, and table-owner termination
removes all state. Submission markers preserve the queued-versus-cancelled
effect boundary. These component tests do not write a Port or accept public
unary/Observe dispatch. The separately tested `Native.Connection` now owns this
table and consumes its ordinary and close-control records. The component-only
tests do not establish the complete owner behavior described above.

`native_backend_test.exs` executes WCO-N01/N02 manifest and executable
verification. It covers exact option keys and path bounds, ordinary-file and
executable-mode checks, the 1 MiB manifest ceiling, strict bounded JSON, pinned
libcoap version/revision, lowercase binary SHA-256 and changed-file rejection.
The verifier starts no Port and changes no permissions. Public connection
selection is covered by the owner fixture above; the production native process
remains unaccepted.

`native_wire_test.exs` executes 13 exact tests and one generated property at the
pure BEAM receive boundary. It covers the 128 KiB JSON-line ceiling, duplicate
members, integer bounds, exact ready identity and response correlation, canonical
base64, the 32,768-byte inline threshold, resolved 1 MiB bodies, Message option
rules and the finite native error vocabulary. A native `remote_response` failure
projects its CoAP code byte into `details.code`, the WCO.06 result shape used by
the UDP and DTLS paths; a missing or out-of-range status fails as a protocol
error. These tests exercise receiver-side
outcomes corresponding to native-v1 F01, F02, F08 and F10–F13. They do not run a
native helper or accept body assembly, process closure, report credit or Port
ownership.

`native_body_test.exs` executes nine exact tests and one generated property for
the pure inbound body state. It covers native-v1 F03, F04 and F14, empty and 1
MiB bodies, 32 KiB chunks, offsets, interleaving, exact event fields, identifiers,
lowercase hashes, canonical bytes, poisoned-state reuse and complete-body
consumption. Only the completed `take/2` result exposes payload bytes; Inspect
redacts the assembly fields. Common event correlation, report sequences,
deadlines and process cleanup remain owner obligations.

`native_report_test.exs` executes ten exact tests for unary and subscription body
envelopes, complete reports and established terminal failures. It covers exact
subscription/generation/sequence correlation, inline and completed streamed
bodies, the F15 payload threshold, Message-to-metadata equality, default Max-Age,
canonical ETag bytes and the reserved no-credit terminal shape. These pure tests
do not assert sequence continuity, cumulative acknowledgment, queues or process
cleanup.

`native_report_ledger_test.exs` executes eight exact tests for the BEAM-side
credit state. It covers zero initial credit, a single in-flight credit command,
strict uint64 sequence continuity, the eight-frame and 1 MiB outstanding wire
bounds, exact delivery tokens, one retained complete report, contiguous
cumulative acknowledgment and the six-frame F15 accounting trace. This immutable
state does not run a helper, write a Port, prove native replay handling or admit a
consumer queue by itself.

## Required verification

### Datagram deadline assertions

`exchange_lifecycle_test.exs` contains the event-driven WCO-P01 exchange
assertions: bounded admission, owner/caller termination during I/O, exact
retransmission bytes, empty ACK/separate response correlation, duplicate-CON
ACKs, retained MID exhaustion and bounded response-cache eviction/expiry.
`native_contract_test.exs` executes the pure contract corpus and all four
native helpers' method/body/URI/Accept behavior. `blockwise_test.exs` preserves
the complete-body regressions. These existing implementations are not replaced
by deadline evidence.
The cancellation trace awaits the unsubscribe result and normal owner/adapter
termination after the final response; it does not race a process-state query
against that expected shutdown.

`exchange_deadline_test.exs` adds the missing WCO-C03/WCO-V02 delayed-timer
boundary. The explicit test clock advances independently from timer delivery,
so a correct correlated response at or after the absolute deadline cannot
become success. A response received before expiry but held in its transfer
worker until expiry also fails; queued writes have no transmission. The tests
retain read effect `none`, transmitted-mutation effect `unknown`, and complete
connection/adapter/timer cleanup. A response one millisecond before expiry is
the positive boundary control.

The stale-traffic cases inject 297 wrong-token NON, wrong-MID ACK and wrong-MID
RST messages into each of a NON exchange and an empty-ACK-confirmed exchange.
They assert unchanged timer identities/deadlines, no further transmission and
bounded call/MID/response state before exact expiry. These deterministic
Datagram-port assertions are not independent-stack interoperability or a
resource bound against arbitrary mailbox flooding. RFC 7252 (June 2014) remains
the protocol revision; the finite interaction budget is WCO-C03 library policy.

The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/coap/exchange_deadline_test.exs test/wotex/coap/exchange_lifecycle_test.exs test/wotex/coap/native_contract_test.exs test/wotex/coap/blockwise_test.exs
```

### Initial-report continuation assertions

WCO-P02 preserves the existing WCO-S02/WCO-D01 implementation. In
`blockwise_test.exs`, WCO-V03 checks negotiated upload numbering and exact
atomic acknowledgments; WCO-V04 checks generated reassembly, first-report
validation, identity changes, missing continuations and actual UDP dispatch.
The continuation properties retain the first message and omit Observe from
distinct-token GETs without fetching block zero.

Additional boundary assertions exercise 4.08/4.13 after an acknowledged upload
prefix and negative/changed-ETag download responses after the upload completes.
They retain numeric remote status, unknown mutation effect and permanent,
non-retryable classification, with no second application request. Exact 1 MiB
and 4096-block continuations succeed; one additional byte or one fewer allowed
exchange fails without returning a prefix. The first block is charged to the
exchange budget. Equivalent unsigned Content-Format encodings compare equally,
and first-response/request elective extensions survive their respective paths.

`execution_test.exs` exercises the public Connection continuation with colliding
token allocations. It skips the first-response token, stops after eight
collisions without transmission, and rejects an invalid first body before
allocating identities. `observation_test.exs` checks WCO-V10 over loopback UDP:
a newer Property notification with a different ETag cannot replace the body
being assembled; only the newest pending report survives. Its separate Event
overlap assertions retain terminal failure and cleanup rather than coalescing.

These are pure, injected-port and first-party UDP fault-peer assertions against
RFC 7959 (August 2016), RFC 9175 section 3 (February 2022), and RFC 7641
(September 2015). They do not add independent secure interoperability or accept
the WCO-P09 software/stress matrix. The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/coap/blockwise_test.exs test/wotex/coap/execution_test.exs test/wotex/coap/observation_test.exs
```

### Observe registration and freshness assertions

`observation_test.exs` exercises WCO-S03/WCO-V05–V07 over loopback UDP: a handle
requires successful registration and a complete initial body; confirmed reports
receive ACKs; repeated datagrams do not repeat delivery. Serial wraparound from
FFFFFF to zero is fresh. Missing Observe, negative status, initial-body timeout,
server termination and fresh Content-Format changes retain their terminal
errors and owned cleanup. A successful response without Observe terminates an
active relationship as well as failing initial registration.

`execution_test.exs` applies the explicit clock to the live observation owner.
Equal and older serials, and both directions of the half-range ambiguity, remain
stale at 128000 ms and become fresh at 128001 ms. The stale inputs carry changed
ETag, Content-Format, Max-Age and payload; they receive ACKs without changing the
accepted report, expiry, timer identities or delivery count. Their arrival does
not postpone the strictly-greater-than-128-second escape. Fresh reports still
pass representation validation. Wrong-token CON/NON and wrong-host/port reports
leave observation state unchanged; the matching report with the same MID remains
deliverable.

The registration fault cases send an error status, a truncated Observe option
and an overlong Observe value through the Datagram port. Malformed datagrams are
discarded and cannot complete registration; the unchanged finite deadline ends
the attempt. Each failure returns no handle, emits one terminal error, sends
best-effort cancellation on the original token/URI, and releases the connection,
adapter and timers. Cancellation here does not claim remote confirmation.

`observation_value_test.exs` retains pure report-validation and serial-boundary
assertions. `native_contract_test.exs` and `observation_trace_test.exs` execute
the fixed WCO-D05 oracle and cancellation trace. These assertions use RFC 7641
(September 2015) freshness and RFC 7252 (June 2014) datagram rules. The terminal
Content-Format policy is local; this evidence does not accept independent-peer
interoperability or the WCO-P09 software/stress matrix. The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/coap/execution_test.exs test/wotex/coap/observation_test.exs test/wotex/coap/observation_value_test.exs test/wotex/coap/observation_trace_test.exs test/wotex/coap/native_contract_test.exs
```

### Observe renewal and cancellation lifecycle assertions

`observation_lifecycle_test.exs` covers WCO-C03/C05 and WCO-V08–V10/V15 through
the explicit Datagram and clock ports. Cancellation confirmed by the peer before
expiry succeeds when local completion occurs one millisecond before the caller's
deadline, but returns timeout at or after it. Concurrent cancellers share one
exchange; the longer-budget caller can succeed while the expired caller returns
timeout. Both cases close locally without repeating cancellation or inventing a
second terminal stream event after peer confirmation.
Negative cancellation status and a terminal 2.31 Continue remain errors, close
locally and do not claim confirmation or send a second cancellation. Late replies
to the aborted renewal or Block2 continuation cannot complete cancellation or
deliver a value; the matching cancellation response is still required.

The route test retains once-decoded percent escapes, empty path/query components,
literal plus and explicit Accept zero across registration, renewal and cancellation.
The full unsigned Max-Age value uses bounded 60000-ms timer slices against its
absolute expiry. An unchanged serial is accepted by renewal. Replayed canceled
expiry and phase-deadline references leave the renewed report and timers unchanged.

Negative renewal status, missing Observe, changed Content-Format and deadline
failure terminate once with original-token/URI cleanup and no automatic restart.
A failed Block2 continuation cannot deliver its accumulated prefix or promote a
complete pending Property report. Changed ETag, remote error, missing Block2 and
deadline failures exercise that rule. Receiver death during blocked renewal or
assembly releases the observation worker, connection, adapter and timers.

Existing `execution_test.exs` assertions cover zero Max-Age and suspended work.
`observation_test.exs` retains actual UDP socket release, foreign-handle rejection,
concurrent cancellation, original wire defaults, latest-Property coalescing and
terminal Event overlap. `observation_trace_test.exs` executes the fixed
`WCO-F-OBSERVE-CANCEL-RACE` byte oracle twenty times per run, including repeated
notification ACKs, no canceled deliveries and zero final owned resources.
`blockwise_test.exs` retains pure and UDP representation/budget regressions.

RFC 7641 (September 2015) supplies Observe lifecycle semantics; RFC 7252
(June 2014) supplies URI processing and exchange correlation; RFC 7959
(August 2016) supplies Block2 representation rules. Finite caller deadlines,
coalescing and Event-overlap failure are local policy. These tests do not replace
independent-peer or complete WCO-P09 software/stress acceptance. The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/coap/observation_lifecycle_test.exs test/wotex/coap/observation_test.exs test/wotex/coap/execution_test.exs test/wotex/coap/observation_trace_test.exs test/wotex/coap/blockwise_test.exs
```

### Discovery and Runtime stream assertions

`discovery_test.exs` exercises WCO-S04/D03/D04 and WCO-V11 through public native
calls over loopback UDP. GET, Accept 40, response status and Content-Format precede
parsing. The 65536-byte transfer ceiling accepts the exact limit and rejects the
next byte during assembly. Absent and empty queries remain distinct. A 1024-byte
encoded query succeeds with each decoded option inside its 255-byte limit;
an additional encoded byte fails before transmission. Repeated and empty query
components, once-decoded percent escapes and literal plus survive continuation.

The Block2 parser cases split UTF-8 inside a code point. No link result precedes
the final block. The assembled description retains raw anchors, relation strings,
first-occurrence title spelling and ordered repeated language/extension values.
A late malformed attribute, strict-singleton duplicate, control byte, incomplete
UTF-8 sequence or excess discarded attribute rejects the entire description.
The existing native workflow discovers, reads, observes, mutates through a second
explicit session, delivers fresh equal values, acknowledges duplicates and cancels
the original route. Advertised absolute targets initiate no connection.

`link_format_test.exs` covers the WCO-D03 grammar and multiplicity rules. Exact
1024-byte URI, name, unquoted, UTF-8 quoted, escaped and discarded duplicate tokens
succeed; another encoded byte fails. Thirty-two occurrences of `title` are
accepted even when only one is retained; the next fails. Generated valid
Unicode strings preserve their exact bytes across quoting and escaping.

`runtime_stream_test.exs` constructs real Property and Event contexts through
ConsumedThing and the public Observe profile. Both stream kinds accept complete
Block2 initial bodies with the first report's five-field metadata, without
forwarding a prefix or replacing Max-Age with continuation metadata. Both contexts
exercise JSON null/false/zero/empty values, UTF-8 text and arbitrary octet streams.
Duplicate-key JSON, incomplete JSON and invalid UTF-8 text produce structured
decoding errors without delivering a value or inventing transport loss. Explicit
stop still cancels the established token/route and releases owned resources.
Existing assertions retain fresh equal-value delivery, duplicate suppression,
terminal native errors, bounded queues and owner/receiver-loss cleanup.

`mapping_test.exs` retains WCO-I03 Form extension and zero-acquisition rejection
assertions. `native_contract_test.exs` and `observation_trace_test.exs` execute the
unchanged WCO-D05 corpus and exact cancellation oracle. The relevant sources are
[RFC 6690 section 2](https://www.rfc-editor.org/rfc/rfc6690.html#section-2)
(August 2012), RFC 5988 (October 2010), RFC 7252 (June 2014), RFC 7641
(September 2015) and RFC 7959 (August 2016). Parser ceilings, strict-singleton
rejection and Runtime ownership remain package policy. These pure and first-party
UDP assertions do not establish independent secure interoperability or complete
WCO-P09 software/stress acceptance. The focused command is:

```sh
WOTEX_PATH_DEPS=1 mix test test/wotex/coap/link_format_test.exs test/wotex/coap/discovery_test.exs test/wotex/coap/mapping_test.exs test/wotex/coap/runtime_stream_test.exs test/wotex/coap/native_contract_test.exs test/wotex/coap/observation_trace_test.exs
```

### Authoritative library gate

`WOTEX_PATH_DEPS=1 mix check --no-retry` includes strict compilation/static checks,
unit/property/doctests, coverage, docs, dependency checks and unpacked out-of-tree
package compilation. Coverage executes the default ExUnit suite exactly once;
`mix test` remains the fast loop. Every invocation builds a fresh archive in a
system-temporary directory and prints its SHA-256. The archive compiler uses
the explicitly tested development dependency BEAM files; it does not establish
independent dependency-archive adoption. Generated package sources and compiled
outputs are removed; the exact archive remains outside the repository.
Interoperability requires explicit invocation and fails on
missing peers/responses. The mandatory final software matrix is Elixir 1.18.4 /
OTP 27.3.4.15 and Elixir 1.20.2 / OTP 29.0.4; the complete secure/stress matrix is
not accepted by the cohorts above. Hardware and certification are separate.

[WCO.08](../specs/WCO.08-native-build-and-software-evidence.md) defines explicit
Mix builds/runs, native manifests, bounded Port framing and durable context
rules. The [native build receipt](native-build-v1.json) records the implemented
`mix wotex.native.build` path on macOS arm64: bounded pinned download, ordered
patch verification, static libcoap compilation, exact version/OSCORE and worker
probes, runtime manifest verification and read-only reuse all pass. On Elixir
1.18.4 / OTP 27.3.4.15 the first Linux software build failed with
`extraction_failed`: that `erl_tar` rejects libcoap's
`examples/contiki/coap_config.h -> ../../coap_config.h.contiki` link as
`unsafe_symlink`. Extraction now passes only validated files and directories to
`erl_tar`, creates the two digest-bound links explicitly and verifies them; the
same Linux build then passes on both runtimes. The
[software build receipt](software-build-v1.json) records the macOS arm64
`mix wotex.software.build` path: the upstream peer and 12 manifest-bound native
fault/vector executables compile and execute under bounded guardians, all 63
artifacts publish atomically, and read-only reuse passes. The
[software run receipt](software-run-v1.json) records the manifest-verified macOS
arm64 run: 15 independent libcoap UDP, PSK and PKI tests, 12 same-stack OSCORE
tests, 8 lifecycle stress tests, 2 saturation tests and 13 native corpus tests pass on Elixir 1.20.2 / OTP 29.0.4, with owned
peers and zero retained processes, ports or library-state resources.

`test/software/lifecycle_stress_test.exs` executes the WCO-C09 matrix once per
transport: UDP and DTLS PSK/PKI against the independent peers, OSCORE against the
same-stack peer. One session completes 1,000 alternating PUT/GET operations with
exact values. Thirty-two concurrent callers each receive their own resource's
representation. With the owner suspended, 96 callers yield exactly 64 responses
and 32 `busy` failures; native sessions reserve before the mailbox and datagram
sessions admit when the owner reads each call. One hundred open/close, 100
Observe/cancel and 100 receiver-termination cycles each return owner ports and
processes to baseline within 1,000 ms, peer debug records count one created and
one removed subscription per Observe cycle, and each OSCORE helper process is
gone. A suspended receiver with `max_queue_length: 2` ends its observation with
one `receiver_overflow`. The forced-failure case per transport ends a 1,500 ms
request against a 3-second peer delay with `timeout`, answers requests from a raw
UDP fault peer with a truncated option or non-DTLS bytes, and closes the peer
mid-session; each failure has effect `none` and releases its resources. The run
reports BEAM total memory and OSCORE helper RSS every 100 operations without
asserting a trend: BEAM totals vary by at most 0.6 MiB per transport and helper
RSS stays below 2 MiB. The stress lane found three defects fixed in preceding
commits: stale peer traffic after exit cancellation, fatal handling of discarded
malformed datagrams, and `native_protocol_error` from a close racing a finished
helper. It does not accept pending-operation owner loss, Port-mailbox sampling or
the native-v1 corpus.

The [Linux software lane receipt](software-linux-v1.json) runs the same
`mix wotex.software.build` and `mix wotex.software.run` inside Linux arm64
containers built from `test/software/Dockerfile.linux`, once on Elixir 1.20.2 /
OTP 29.0.4 and once on Elixir 1.18.4 / OTP 27.3.4.15, from commit `4325f52`. Each
lane builds libcoap with the nine ordered patches and compiles the 12 native
fault/vector executables with ASan/UBSan, including the production-worker
exchange harness, and all exit 0; each software run passes all 47 tests, including
the ExUnit-owned RFC 8613 endpoint traces, with zero retained resources. The
production helper and peer are byte-identical across lanes. The minimum lane first
exposed the OTP 27 archive link failure fixed in `d8d856f`. The two saturation
tests added afterwards have run only on macOS. The helper that ExUnit drives in these lanes is
not itself sanitizer-instrumented; its sanitized evidence remains the
`test/native/Dockerfile` harness lane.

`test/interop/oscore_test.exs` is same-stack evidence: the peer is the
software-build `coap-server` with a matching OSCORE configuration, and the client
is the manifest-verified Mix-built helper behind the public native owner. Each
case uses a fresh context store and a distinct sender ID. Protected
GET/PUT/POST/DELETE, a 4.04 as `details.code`, a 43,500-byte echoed body and
discovery precede a graceful close; the helper process is gone and reopening the
same context returns `fresh_context_required`. A mismatched master secret returns
`security_handshake_failed` with effect `none` and terminates the generation
within 1,100 ms. A 1 MiB Block1 upload and Block2 download complete inside one
60,000 ms deadline. Observe delivers inline and 42,000-byte streamed changes made
by a second UDP client, rejects ordinary requests while active and cancels
idempotently; peer debug records show exactly one created and one removed
subscription. Receiver death and owner death during a pending request each end
the native owner within 1,100 ms and reap the helper. A real ConsumedThing
`readproperty` call selects `:coap_oscore` and decodes the protected JSON value.
Through an ExUnit UDP relay, a confirmable 2.05 with an empty OSCORE option and a
token no request used arrives before the real response and the protected GET
still succeeds, as it does after an ACK carrying the request's MID and token with
an option length past the datagram. A captured authenticated notification
delivered three more times yields no second value, delivering it again after a
newer notification yields none, and an unprotected 2.05 with
the observation token followed by the genuine notification with an altered tag
leaves the observation delivering the next change. A further relay case records every datagram after receiver death:
each confirmable peer message has an ACK or RST with its message ID before the
helper exits. Pending-operation owner loss, the live replay window, independent
OSCORE interoperability and the stress matrix are outside this cohort.

The [native worker stale-traffic receipt](native-worker-stale-traffic-v1.json)
binds the fix for a failure that repeated Observe receiver-death generations
exposed against the software-build peer. The helper sent its best-effort exit
cancellation and exited at once; the peer answered with an empty ACK and a
separate confirmable response, retransmitted it toward the dead endpoint and
queued the next generation's response behind it when the operating system reused
that UDP port. Every generation also began with libcoap's default token `0x01`,
and a stray protected response without a request association ended the active
exchange. Exit cleanup now services the cancellation exchange for at most 20 ms,
inside custody's 25 ms termination signal. Each session seeds its token counter
with 8 random bytes, following the RFC 7252 section 5.3.1 recommendation of at
least 32 random token bits. `COAP_EVENT_OSCORE_NO_SECURITY` no longer ends the
active exchange, because libcoap raises it only when a response token has no
request association. The native harness requires a first token of at least 5
bytes; the two relay cases and this token assertion fail against the preceding
helper. Unprotected nonempty responses are still rejected before token
correlation and end the active exchange, and an abruptly killed helper still
cannot acknowledge a pending peer response.

The [native worker malformed-datagram receipt](native-worker-malformed-datagram-v1.json)
binds the next source cohort. A C09 forced-failure lane answered a protected
request with an ACK carrying its MID and token and a truncated option. The helper
returned `connection_closed` at once because the worker treated
`COAP_EVENT_BAD_PACKET` as fatal, although libcoap raises that event only after
discarding an unparseable or uncorrelated datagram. The event is now ignored; a
correlated bad response still reaches the exchange as `COAP_NACK_BAD_RESPONSE`
and ends it with `invalid_response`. The relay regression fails against the
preceding helper and passes on macOS through the software run; the complete
native harness also passes the Linux ASan/UBSan/leak lane.

The [native worker notification-verification receipt](native-worker-notification-verification-v1.json)
binds the next source cohort. RFC 8613 (July 2019) section 8.4.2 requires the
client to stop processing a notification that fails verification and states that
the error does not cancel the observation. The worker ended established
observations with `observation_failed` on `COAP_EVENT_OSCORE_DECRYPTION_FAILURE`,
`NO_PROTECTED_PAYLOAD` or `DECODE_ERROR`. While an observation is established
and no request is pending, those events now discard the notification; they still
end a pending request, registration, renewal or cancellation. libcoap acknowledges
the refused confirmable notification at the message layer, so its value is lost as
if the datagram were dropped and the next change is delivered. The tampered-relay
regression fails against the preceding helper; the replay/duplicate case already
passed and closes an evidence gap.

The [native worker pending owner-loss receipt](native-worker-pending-owner-loss-v1.json)
binds the next source cohort. Owner EOF while a protected registration still
awaited the peer sent no cancellation, because exit cleanup cancelled only an
established observation. Owner EOF while a renewal awaited the peer also sent
none: libcoap sets its OSCORE client hold on every `coap_send`, because a client
recipient context never leaves its initial replay state, and clears it only when
a response arrives. Constructing the cancellation therefore blocked inside
`coap_client_delay_first` until custody's 25 ms termination signal killed the
worker. The same hold stalled a renewal timeout's terminal cancellation for five
seconds and turned a cancellation behind an unanswered renewal into a command
`timeout`. Patch 0008 removes the hold, and exit cleanup now abandons a pending
registration as a possible peer observer while ignoring callbacks. The harness
closes the owner during a pending registration, renewal and cancellation. Each
reaps the worker with owner-loss status, and the peer receives exactly one
cancellation within 1,000 ms. A renewal-timeout observation now ends within
3,500 ms, and a cancellation behind an unanswered renewal returns `result: null`.
The harness fails against the preceding helper.

The [native worker intervening-response receipt](native-worker-intervening-response-v1.json)
binds the next source cohort. The harness holds the worker's cancellation in the
unserviced peer socket and sends a notification ahead of it. libcoap keeps one
OSCORE association per token and refreshes it when the cancellation is sent, so
the notification, protected for the registration request, fails verification.
The worker ended the pending cancellation with `security_handshake_failed`, which
supersedes the notification-verification cohort's rule for pending renewals and
cancellations. libcoap also deleted the refreshed association on that failure,
so the peer's genuine confirmation found none. The worker now discards OSCORE
verification failures whenever an observation exists, and patch 0009 keeps a
request association after a message fails verification. The confirmed case
returns `result: null`, the unanswered case returns `timeout`, and neither writes
a report despite open credit. A notification in flight
across a Max-Age renewal is likewise discarded, and the renewal response
delivers report 2 with the new value. The preceding helper returns
`security_handshake_failed` for the cancellation and ends the renewed observation
with `observation_failed`. With only the worker change, the confirmed cancellation
returns `timeout`; with only the patch, both cases fail as before.

The [native worker stale-notification receipt](native-worker-stale-notification-v1.json)
binds authenticated stale injection through the complete Mix-built helper. The
relay replays notification 41 three times after 42 is delivered; no value
follows and 43 is delivered next. Against a helper whose freshness admission
never reports a stale serial, that relay case delivers 41 again. The same mutant
still passes the earlier back-to-back duplicate, which a layer before freshness
admission discards. No source changes accompany this cohort.

`test/software/native_corpus_test.exs` executes native-v1 cases through the
manifest-verified helper in the software run. A test-owned UDP socket is the
open generation's peer. F16-F20 send the corpus observe commands, which omit
`renew` or give it null, 0, "true" or {}; each helper closes its generation with
a nonzero exit, writes no reply for request 17 and sends no datagram, while the
same command with `renew: false` sends the protected registration. F06 opens,
closes and reopens one context store: the reopen returns `fresh_context_required`,
the registry bytes stay unchanged and a following request closes the generation
without a datagram. A helper whose decoder admits any `renew` value fails all
five command cases. The runner compares with the corpus `expected` values and
passes no expected value to the helper.

`test/support/oscore.ex` implements RFC 8613 context derivation, nonce, external
AAD, plaintext, OSCORE option and AES-CCM-16-64-128 protection in ExUnit support;
`test/wotex/coap/test_oscore_vectors_test.exs` reproduces the Appendix C.1, C.2,
C.4, C.5, C.7 and C.8 vectors byte for byte. `test/support/oscore_peer.ex` uses it
as a scriptable protected UDP endpoint independent of libcoap. The corpus runner
drives F21-F23 against it. The corpus originally fixed token `AQ==` and Message
IDs 71 and 72, which the helper cannot produce since its tokens are random, and
its intervening response was an ACK whose Message ID libcoap would never
correlate. Each authenticated response now names the helper request it answers
and substitutes that request's wire Message ID and token. In F21 the registration
is answered with Partial IV 9: the helper replies with the subscription, the
credit reply precedes report 1, and the report carries Observe 9 and the corpus
metadata. In F22 a notification protected for the registration arrives after the
cancellation and writes nothing, the confirmation returns `result: null`, a later
notification writes nothing, and a second cancel returns `invalid_request` without
a datagram. In F23 a registration answered without Observe returns
`invalid_observation_response` and the helper exits 0. A helper restoring the
earlier rule that OSCORE failures end a pending request returns
`security_handshake_failed` for F22.

The credit and loss traces use the same peer. The acknowledged registration
response is the first produced report, and later reports are non-confirmable
notifications with increasing Partial IVs. In F05 an Event subscription with
eight credits writes eight reports; the ninth waits in the pending slot and the
tenth ends the subscription with `overlapping_event_report`, a terminal without
`report_seq`, after which the helper exits 0. The corpus had named that terminal
`session_lost`, which is a Runtime transport status, not a native code. In F09
eight and then four reports follow credit 0 and 4; replayed and regressing
credit (4, 2, 0) returns `result: null` without releasing a report, a thirteenth
report waits, credit 12 then releases exactly report 13, and the subscription
still cancels. F24 replaces the corpus's abstract `session_lost` failures with two
authenticated 4.04 notifications: one `observation_failed` terminal follows, the
second writes nothing and the helper exits 0. A helper that keeps a second
pending Event report fails F05.

F07 cannot run through the helper: each context opens at sender sequence zero and
is consumed on exit, so 2^40 is unreachable. `test/native/oscore_store_send_test.c`
now executes it against the patched SDK. A store reserved to 2^40 backs a libcoap
client whose next sender sequence is 2^40; three GET sends return
`COAP_INVALID_MID`, the peer socket receives nothing and the store boundary stays at
2^40, because libcoap refuses before encrypting and never asks for a reservation.
A reservation past 2^40 then returns `WCO_STORE_EXHAUSTED`, whose code is
`sequence_exhausted`. The corpus runner contract records this placement.

The helper half of F15 runs against the same RFC 8613 endpoint, which now serves
protected Block2 transfers: it sends each payload in 1,024-byte blocks with one
ETag and answers every follow-up block request libcoap sends with a new token. The
registration response carries the corpus's 32,768-byte payload and, after credit
0, is written as one inline report. A 32,769-byte notification then produces
`body_begin`, two `body_chunk` frames, `body_end` and its report, report sequences
2 to 6; the chunks reassemble the payload, match the begin digest and precede the
single report, and two credits remain unused. A helper whose inline limit is one
byte lower fails F15.

`test/software/native_saturation_test.exs` suspends the actual `Native.Connection`
owner with `:sys.suspend/1` after a protected subscription is established against
the ExUnit RFC 8613 endpoint. The peer then sends 40 non-confirmable notifications
while the test samples the owner's mailbox every 10 ms for 600 ms and counts newline-
terminated Port frames by type. For a Property subscription the report frames reach
exactly eight and never exceed it, at most one in-flight credit reply accompanies
them, no other frame appears, the Port output queue stays empty and the buffered
bytes stay under eight 131,072-byte frames. A 4.04 notification then adds exactly
one terminal frame beside the full report window; after resume the receiver gets at
most eight values and the terminal error, and the owner exits within 1,100 ms. For
an Event subscription the eighth report is followed by one
`overlapping_event_report` terminal. Killing that suspended owner makes the helper
send its exit cancellation, which the peer receives and verifies with inner Observe
1, and the helper process is gone within 1,100 ms. A helper whose credit window is
16 fails both tests. This lane does not also saturate the OS pipe, because the
runtime keeps draining the Port; `native-worker-output-saturation-v1.json` covers
that pipe condition.

The [native worker uncorrelated-plaintext receipt](native-worker-uncorrelated-plaintext-v1.json)
binds the next source cohort. The response-admission patch raised
`COAP_EVENT_OSCORE_NO_PROTECTED_PAYLOAD` for every plaintext nonempty response on
an OSCORE session before token correlation, so the worker ended an active protected
GET with `security_handshake_failed` when a stray or spoofed plaintext 2.05 carried
a token no request had used. Patch 0010 raises the event only when an OSCORE
request association exists for the response token and otherwise discards the
datagram. The relay case now also injects a plaintext 2.05 with an unused token
before the genuine response and the GET still succeeds; against the preceding
helper it returns `security_handshake_failed`. A new protection-vector variant
sends a plaintext response with an unused token and requires no delivery and no
protection event; it fails against the nine-patch SDK. The fifteen correlated
plaintext variants still report exactly one protection failure each.

The [native worker renewal-code receipt](native-worker-renewal-codes-v1.json)
binds the next source cohort. The worker reported `remote_response` with the
numeric status for every renewal code outside 2.00–2.30, so a protected renewal
answered with 2.31 Continue ended the observation as a remote error with status
95. It now reserves `remote_response` for class 4 and 5 codes (128–191), as it
already did for unary and registration responses, and ends a renewal answered
with 2.31 or a class 3 code with `invalid_response`. Two new renewal-fault
cases send 2.31 and 3.00 through public custody against the same-stack peer;
both pass on macOS and on Linux with ASan/UBSan and leak detection, and the 2.31
case fails against the preceding helper. The four earlier renewal faults keep
their codes.

Software peers now run under the workspace's native command guardian with
output bound 0, which passes the peer's output straight to its owning BEAM and
ends the peer's process group when that BEAM's pipe closes. Before, a peer
started with `start_supervised` outlived every test: ExUnit stops such children
before `on_exit`, the peer owner does not trap exits, and libcoap ignores
SIGPIPE, so `coap-server` kept running with parent PID 1 after its Port closed.
A control run of `test/interop/oscore_test.exs` with the preceding helper left
such an orphan. The guardian's 16 MiB relay bound first stopped the peer during
the 1 MiB OSCORE body test; the pass-through mode removes that bound for peers
only, and `native_build_command_test.exs` asserts 17,000,000 bytes of passed-
through output and owner-loss reaping. `test/software/peer_guardian_test.exs`
kills a child BEAM that owns a libcoap peer or the independent peer with
SIGKILL and requires every process naming the peer's executable to end within
five seconds; the preceding helper leaves the libcoap peer running. The software
run now counts the live processes whose arguments name a workspace file after
the suite, allowing the five-second cleanup, and fails the run when any remain
or the process table cannot be read. It never counts its own BEAM or that BEAM's
ancestors, so a shell that started the run and names workspace files in its
arguments is not taken for a peer. All nine software-lane files, 57 tests,
pass on macOS arm64 against a fresh software build with no process naming the
workspace afterwards; these runs used the lane files directly.

The [native worker termination receipt](native-worker-terminated-v1.json) binds
the next source cohort. On the Elixir 1.18.4 / OTP 27 Linux lane with four
CPUs, one receiver-death cycle of the OSCORE lifecycle stress test left the
peer's observer in place. Custody closes the worker's input on owner loss and
sends SIGTERM 25 ms later, and the worker kept the default action for that
signal, so a worker not yet scheduled was terminated before it sent its exit
cancellation. The worker now ends its event loop on SIGTERM with status 143,
still sends the one cancellation and skips only the wait for its response. A new
case signals a worker that has an established protected observation while its
input is still open; the peer receives exactly one cancellation and the worker
exits with 143 on macOS and on Linux with ASan/UBSan and leak detection, while
the preceding worker sends none.

The independent upstream-stack OSCORE cohort in
`test/software/independent_oscore_test.exs` drives the manifest-bound helper
against `org.eclipse.californium:cf-plugtest-server` 3.14.0, admitted by exact
archive SHA-256
`0bf82d45791eeebbf9d781d0e66f47ddafe67ba36984a432771127f1ee6dd7d5` during the
software build and executed by a Java runtime recorded by path, digest and
version. Its five cases pass on macOS arm64 with OpenJDK 21.0.12.1: protected
GET/POST/PUT/DELETE with the exact Location-Path of the protected POST,
protected discovery containing `</oscore>;osc`, a 1,280-byte Block2 body and an
exactly recovered Block1 upload, three ordered notifications with distinct
Observe values and Max-Age 5 whose delivery stops after cancellation, a relayed
duplicate protected response that yields one result and no client
retransmission, and a relayed one-bit ciphertext change in a notification that is
discarded while the observation continues. Because the peer admits one client
sender identity and keeps a replay window for its lifetime, each case owns one
peer instance and one fresh client context. Renewing the full software-run
receipt with this cohort and running it in the Linux lanes remain open; the Java
peer is a test peer only and is neither a runtime nor an orchestration
dependency of the package.

The [clean-source receipt](clean-source-v1.json) runs `mix check` from `git clone
--no-local` copies of the committed wotex, wotex-runtime and wotex-coap HEADs in
Linux arm64 containers, once on Elixir 1.18.4 / OTP 27 and once on Elixir 1.20.2 /
OTP 29, as an unprivileged user under an init process. Every configured tool passes
on both runtimes, coverage is 95.3%, the archive tool compiles the Hex package out
of tree and both runtimes produce archive
`92d3b5cf75031456f718ecc7791b557d2f0b3d7066f5f0699abf29f096ffe291`, and the clones
stay clean. The matrix first found four defects on OTP 27, fixed in `65945eb`,
`a109595`, `1f013a4` and `6edd61b`: two Dialyzer opacity findings, a coalesced
duplicate-reply fixture race, a fixture helper slow to stop on SIGTERM, and coverage
of 94.9%. A root-run container also let a mode-0 artifact test read its file, so
the lane runs unprivileged.

The [custody leak-audit receipt](native-custody-leak-audit-v1.json) runs the eleven
opaque-stream custody cases in the `test/native/Dockerfile.custody` image with
LeakSanitizer enabled and the `--leak-audit` instrumentation allowance. Every case
exits 0 without a leak report. WCO-G10 launches 200 short children with alternating
inherited signal state and directly reaps all 200 in 213 s. It first exceeded the
180-second aggregate alarm: that bound was below 200 launches times the 500-ms reap
deadline plus the named 1,000-ms instrumentation allowance, so the leak-audit alarm
is now that 300-second product. The ordinary lane keeps its 20-second alarm and all
per-child limits.

Independent upstream-stack OSCORE interoperability is not yet accepted. The historical Python result retains only its own
recorded cohort.
