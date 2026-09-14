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

Independent PKI tests under development are not committed peer acceptance.
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
