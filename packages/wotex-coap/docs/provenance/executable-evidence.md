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
protocol traffic is exchanged with native `coap-server`. The result does not
validate the planned .13 Mix tasks. The sanitizer lane is macOS; the required
Linux full-software lane is a separate acceptance obligation.

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

`native_command_encoder_test.exs` executes six exact tests for the matching
BEAM transmit boundary. It encodes all nine operations, canonical byte values,
explicit OSCORE credentials and exact five-field lines; omits absent optionals;
checks path, scalar, body-chunk and 128 KiB line bounds; and allocates each
decimal uint64 request identity once before exhaustion. The immutable allocator
retains no command or credential. These tests do not write a Port or prove that
the production helper accepts the lines.

`native_connection_test.exs` executes sixty-three contract-injection tests for the
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
generation. Killing the configured owner releases the exact helper within
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
rules and the finite native error vocabulary. These tests exercise receiver-side
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

[WCO.13](../specs/WCO.13-native-build-and-software-evidence.md) defines explicit
Mix builds/runs, native manifests, bounded Port framing and durable context
rules. Implementation status remains partial until the required exact assertions
and those task runs pass. No Python-based result transfers to an unbuilt tool.
