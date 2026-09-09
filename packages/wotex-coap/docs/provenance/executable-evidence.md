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
OSCORE known-answer/replay/store fault tests, native helper ownership and complete stress/matrix closure remain
required by [the ordered plan](../plans/software-implementation.md).

## Required verification

`WOTEX_PATH_DEPS=1 mix check --no-retry` includes strict compilation/static checks,
unit/property/doctests, coverage, docs, dependency checks and unpacked out-of-tree
package compilation. Interoperability requires explicit invocation and fails on
missing peers/responses. The mandatory final software matrix is Elixir 1.18.4 /
OTP 27.3.4.15 and Elixir 1.20.2 / OTP 29.0.4; the complete secure/stress matrix is
not accepted by the cohorts above. Hardware and certification are separate.

[WCO.13](../specs/WCO.13-native-build-and-software-evidence.md) defines explicit
Mix builds/runs, native manifests, bounded Port framing and durable context
rules. Implementation status remains partial until the required exact assertions
and those task runs pass. No Python-based result transfers to an unbuilt tool.
