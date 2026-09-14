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
