---
spec:
  id: WCO.10
  title: "Complete CoAP client software profile"
  status: accepted
  version: 1.0.0
  owner: wotex-coap
  updated: 2026-09-09
---

# WCO.10 Complete CoAP client software profile

Read [WCO.00](WCO.00-library-contract.md) first. Required software includes bounded
UDP exchanges, atomic Block1 uploads/Block2 downloads, Observe lifecycle, resource
discovery, DTLS and the explicitly selected OSCORE adapter below. TCP/WebSocket
CoAP, multicast/group communication, extended tokens, Group OSCORE and a server
implementation are separate profiles. Physical radios are unnecessary.

Baseline `1ff4320` includes the native UDP exchange, strict known-option lengths,
cryptographic tokens, complete blockwise transfers and independent libcoap
upload/echo/readback evidence. Active Observe and secure profiles are target
requirements, not implemented claims. [WCO.03](WCO.03-blockwise.md) describes the
committed blockwise behavior; preserve that tested implementation.

## Sources and architecture

RFC 7252 (June 2014) owns messages, correlation and congestion control; RFC 7641
(September 2015) Observe; RFC 7959 (August 2016) blockwise; RFC 9175 (February 2022)
token processing and Request-Tag; RFC 8613 (July 2019) OSCORE. Primary links and
the W3C draft pin are in [provenance](../provenance/primary-sources.md).

The [standalone/preservation contract](WCO.11-standalone-client-and-preservation.md)
fixes native helper signatures, URI processing, discovery results and concrete
fixture oracles. It is mandatory alongside S01–S06.

Keep the pure `Message`, `Codec`, `Block`, `Blockwise` and `Observe` modules.
Refactor `Connection` into an event-driven socket owner or extract its exchange
state into a pure value module; owner/caller monitors must be handled during
I/O. Introduce a small explicit Datagram behaviour used by UDP and OTP DTLS:
`open(config, owner, timeout)`, `send(handle, bytes)`, `set_active_once(handle)`,
`close(handle)`. Open returns `{:ok, handle}` or a library Error; send, arm and
close return `:ok` or Error. The owner receives
`{:wotex_datagram, generation, {:data, peer_ip, peer_port, bytes}}`,
`{:wotex_datagram, generation, :closed}` or
`{:wotex_datagram, generation, {:error, code}}`. Generation mismatch is ignored.
DTLS handshake/session machinery belongs to OTP `:ssl`, not a new TLS codec.
OSCORE uses a separately selected libcoap bridge; do not run two independent
CoAP retransmission engines around one secured request.

## WCO-S01 — Codec, exchange and duplicate discipline

Datagrams remain at most 1152 bytes, tokens 0..8, options 64. Validate known option
lengths, duplicate non-repeatable options, empty-message shape, reserved encodings
and unsupported critical options. Preserve unknown elective options. Unsigned
encoders emit minimal bytes; receivers accept permitted leading zero bytes.
Reject invalid response classes and a standalone 2.31 Continue as completion.
An unknown detail in a defined error class remains a numeric remote error.

One active exchange per endpoint session (NSTART=1), plus WCO-C03 bounded queued
admission. A token is unpredictable and unique for its live interaction. MIDs
are not reused for the endpoint for 247 seconds. If the finite MID space is
unavailable, fail before transmission. A CON request uses an initial delay in
2000..3000 ms, doubles the delay and retransmits at most four times using identical
MID, token and bytes. The explicit test-only `ack_timeout` does not change the
production default. NON requests are transmitted once.

Endpoint and token correlate responses; ACK/RST also require the proper MID.
An empty ACK stops retransmission but does not complete the operation. A separate
CON response gets an empty ACK. Cache accepted CON response identity by endpoint,
MID and token for the exchange lifetime, at most 1024 entries, expiring and then
evicting oldest entries. A retransmitted response is ACKed while idle or while a
different exchange runs, without redelivery. Unknown CON responses receive RST;
unrelated NON/ACK messages cannot extend a deadline. A malformed datagram cannot
crash the owner or complete a request.

## WCO-S02 — Whole-body transfer

Keep the WCO.03 atomic profile: 1 MiB body ceiling, default block size 512,
1..4096 exchanges, all sizes 16..1024, one absolute interaction deadline.
Block1 uses stable Request-Tag and validates the exact block acknowledgment;
non-final success is 2.31 with M=1 and no payload. Non-atomic per-block success
is an explicit `:non_atomic_block_write` failure, not whole-body success.
Server size reduction changes subsequent block numbering without restarting
already acknowledged writes. Block2 validates offsets, non-final size, ETag,
Content-Format, status and body/count limits. A failed continuation never yields
the accumulated prefix as a complete value. 4.08/4.13 are reported; the library
does not restart a potentially partially applied request.

Add a continuation entry point accepting a validated first Block2 response for
Observe integration. Preserve the first report's Observe sequence and original
representation identity when assembling later blocks. Continuation GETs omit
Observe and use a token distinct from the observation token. Report a new
notification arriving during assembly without allowing it to replace the ETag
of the body currently being assembled. Coalesce at most one newer Property
notification; do not build an unbounded assembly queue. For an Event subscription,
another fresh notification arriving during Block2 assembly is a terminal
`:overlapping_event_report` error; do not silently coalesce ordered Event deliveries.
Observe still represents eventual resource state and cannot promise delivery
of every historical application event.

Capabilities must distinguish `max_datagram_size: 1152` and
`max_body_size: 1_048_576`. Correct the baseline's ambiguous `max_payload_size`
documentation while retaining a documented compatibility alias. Update capability
flags only as their software proofs pass.

## WCO-S03 — Observe API and state machine

Implement `CoAP.subscribe(session, %{path: path, receiver: pid, renew: boolean,
max_queue_length: n})`; a binary path is shorthand. The connection is dedicated
to one observation until it closes. Ordinary requests and a second subscription
on it return `:observation_active`; callers can explicitly open another session.
Use the Subscription handle and native deliveries in WCO-C05. Add lower-level
`Connection.observe(pid, path, receiver, options, timeout)` and
`Connection.unobserve(pid, subscription, timeout)` with those exact argument
roles. Options are `renew` (default true) and `max_queue_length` (default 1000);
validate proper unique keyword keys. The root API normalizes its request map
before calling these functions.

| State | Input | Action and next state |
| --- | --- | --- |
| Opening | Valid GET, fresh token | Send CON Observe=0 under establishment deadline; registering |
| Registering | Successful response with one valid Observe value | Assemble initial body, deliver once, arm Max-Age; active |
| Registering | No Observe, negative status, timeout or invalid body | Fail registration, best-effort token-matched cancellation, close |
| Active | Matching fresh CON/NON report | ACK CON, assemble complete body, deliver, replace freshness timer |
| Active | Duplicate/stale report | ACK valid CON; do not deliver or extend freshness |
| Active | Unrelated peer/token | Ignore or RST under S01; no state update |
| Active | Max-Age expires, `renew: true` | Re-register GET Observe=0 with same token/new MID, finite deadline; renewing |
| Active | Max-Age expires, `renew: false` | `:observation_stale`, cancel and close |
| Renewing | Correlated valid Observe response | Validate body and reset freshness even when serial unchanged; active |
| Active/renewing | Owner/receiver death, queue overflow, server ends observation | One terminal event when receiver lives; cleanup; closed |
| Active | Explicit cancel | CON GET Observe=1 with original URI/token/new MID; canceling |
| Canceling | Matching successful response without Observe | Close and return `:ok` |
| Canceling | Failure/deadline | Close locally, return error; no later deliveries |

Freshness is RFC 7641 24-bit serial arithmetic, including wraparound and the
strictly-greater-than-128-second escape. Max-Age defaults to 60 seconds; decode
the full unsigned option. Stale traffic cannot move either clock. Renew no more
often than once per second when Max-Age is zero; report stale state during that
minimum interval. Long Max-Age values must not overflow an OTP timer: schedule
bounded timer slices against the absolute expiry. Timer messages carry generation
identity. A notification carrying Observe cannot satisfy a cancellation exchange.

Cancellation on abrupt owner death is best effort using the original token and
URI before local closure; it cannot claim remote confirmation. A registration
that may have reached the peer also needs this cleanup, even if it never returned
a valid handle. Preserve this distinction in errors and tests.

## WCO-S04 — Forms and discovery

Map `observeproperty` and `subscribeevent` to GET Observe=0; reject a conflicting
`cov:method`. Use the correct Property/Event operation context. Cancellation uses
the original handle identity. Runtime delivers only complete, freshly accepted
representations through `decode_frame/3` with status, Observe sequence, ETag,
Content-Format and Max-Age metadata. Credential selection is described below.

Add `discover(session, %{query: binary | nil})` which reads `/.well-known/core`
using complete Block2 transfer and parses Content-Format 40 under RFC 6690
(August 2012). The pure `LinkFormat.decode/2` returns bounded link maps with
`href` and a list of repeated `{attribute, value | true}` terms; preserve unknown
attributes and raw URI references. D03 defines multiplicity and anchored-link
handling; discovery itself neither resolves nor dereferences advertised targets.
Limit body to 64 KiB, links to 256, attributes per link to 32 and token/string
bytes to 1024. Repeated extension attributes survive; singleton and first-occurrence rules
are explicit in D03. Quoted delimiters and escapes must not split links; malformed
quotes, controls or excess limits fail. Discovery advertises descriptions, never
authorizes later operations or initiates connections to discovered endpoints.

## WCO-S05 — DTLS transport

`coaps://` selects DTLS and default port 5684. No implicit fallback to UDP exists.
Use explicit credential `%Wotex.CoAP.Security{mode: :dtls_psk | :dtls_pki, ...}`;
native `connect/1` and Runtime must validate it against the selected scheme.
Secret fields are excluded from Inspect/telemetry/error details. OTP ssl is an
explicit runtime facility required by the selected adapter; load alone starts
no handshake. Pin the tested OTP versions in evidence.

DTLS 1.2 is the required compatibility profile. PSK requires nonempty identity
(1..128 UTF-8 bytes) and key (16..64 bytes), an exact identity lookup, and only
`TLS_PSK_WITH_AES_128_GCM_SHA256` for the PSK cipher suite; no
default or test key is installed. PKI requires explicit trust roots, client
certificate/private key, expected server DNS name or IP, and caller-provided
revocation material. Require peer chain/signature/time/KU/EKU and SAN identity
validation, fail unknown critical extensions, and reject revoked certificates.
The PKI cipher allowlist is exactly
`TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`; require RSA certificates of at least
2048 bits and reject an unavailable suite rather than widening the policy.
Use exact SAN DNS/IP identity without CN fallback or wildcard matching.
Bound each certificate/key input to 64 KiB, at most eight trust certificates,
eight CRLs and 1 MiB aggregate credential bytes before parsing. Never fetch
issuer/CRL URLs during validation. Use bounded chain depth eight. Trust material is immutable during a session;
rotation requires a new explicit session generation. Cipher/profile mismatch,
wrong identity, wrong PSK and missing material are failures before CoAP success.
DTLS replay protection and retransmission belong to OTP; CoAP exchange identity
still applies inside authenticated datagrams.

## WCO-S06 — OSCORE adapter and durable state

Use pinned libcoap 4.3.5, commit `7cf7465b784baded4de183290c547d582becfd28`, in an
optional caller-selected C bridge with the WCO-C07 framed contract. Its own CoAP
engine performs exchanges/Observe/blockwise; do not wrap its operations in a
second native retransmission loop. Use `coap_new_oscore_conf`,
`coap_new_client_session_oscore`, release APIs and the documented sequence-save
callback from the [4.3.5 OSCORE API](https://libcoap.net/doc/reference/4.3.5/man_coap_oscore.html).
Map the same native/Runtime request and subscription contracts at this boundary.

Security.new/1 uses a mode-specific allowlist: DTLS PSK has `identity`, `key`;
DTLS PKI has `trust_roots`, `certificate`, `private_key`, `server_identity`,
`crls`; OSCORE has the context fields below. Native connect accepts `security:`.
Runtime scoped requests may use this typed value as ExecutionContext.credential,
and must close the session and discard it before returning. Runtime subscriptions
instead require explicitly configured native security and a nil immediate
credential; reject a non-nil subscription credential before opening. No raw
ExecutionContext or credential value is retained in a Runtime handle.

Select `mode: :oscore` explicitly on `coap://`, with master secret/salt, sender
and recipient IDs, optional ID Context and an absolute context-store path.
Keys are `master_secret` (16..32 bytes), `master_salt` (0..32 bytes), `sender_id`
and `recipient_id` (0..7 bytes, distinct), `id_context` (nil or 0..255 bytes),
`context_store` (absolute path). These are library limits for the fixed suite;
unknown keys or reused unsafe context identity fail before bridge traffic. The
initial suite is AES-CCM-16-64-128 with HKDF-SHA-256 from RFC 8613's test vectors;
unknown algorithms fail. No Group OSCORE or automatic context discovery.

Sender sequence reservation must be durable before encryption/transmission.
Acquire an exclusive store lock, bind state to the full context identity, reserve
a future sequence range with fsync and atomic replacement, then permit its use.
After crash, skip all previously reserved numbers. The save callback's success
must mean durable success; `fflush` alone is insufficient. Overflow of the
40-bit Partial IV space closes the context. Never silently recreate an existing
context's lost/corrupt state at zero. The required first profile does not export libcoap receiver replay state.
Therefore a context is usable by exactly one bridge process generation. Mark its
context identity consumed durably before accepting inbound traffic; after any
bridge exit, reject reuse with `:fresh_context_required`, even after graceful
shutdown. A new generation requires explicitly provisioned fresh keying context
with a different derived key/nonce space, recorded in the same durable context
registry. Merely deleting a session file or resetting a sequence is forbidden.
Sender/recipient IDs, salt and ID Context participate in key derivation; use the
RFC-defined derivation identity when detecting reuse, not a caller display name.
Within a live generation libcoap retains and enforces the replay window. Set
`replay_window` to 32. This intentional restart restriction avoids claiming
receiver replay persistence that the selected public SDK API does not provide.

## Acceptance scenario families and software peers

These IDs describe required test families. The .11 corpus contains concrete
selected inputs/output projections; its existence does not accept any family.
Each family still needs all boundary/fault variants bound to actual assertions.

| ID | Scenario | Required result |
| --- | --- | --- |
| WCO-V01 | Wrong peer/token/MID, empty ACK then separate CON, repeated CON after completion | Correct correlation, delayed completion and repeat ACK without duplicate delivery |
| WCO-V02 | Lost ACK, NON loss, fifth retry boundary, stale packet flood, expired queued write | Identical retransmission bytes; finite deadline; no expired write transmission |
| WCO-V03 | Block1 size reduction, wrong/missing ACK, non-atomic success, final Continue | Exact progression or explicit failure; no restart |
| WCO-V04 | Multi-block response, ETag/format/size change, missing block, Size2/body/count limit | Complete identity-consistent body only |
| WCO-V05 | Observe values FFFFFF→0, equal, older, half-range ambiguity, 128000/128001 ms | RFC freshness result; stale messages do not extend expiry |
| WCO-V06 | Registration without Observe, error status, truncated option, initial-body timeout | No handle; best-effort cancellation and owned cleanup |
| WCO-V07 | Confirmed notification, retransmission, server termination, unrelated token | ACK/dedup or terminal failure; no spurious value |
| WCO-V08 | Renewal same serial, zero/large Max-Age, stale generation timer | Bounded correct refresh; no tight loop or stale timer effect |
| WCO-V09 | Cancel while a notification arrives, double cancel, foreign handle, receiver death | Correct original token/URI, local closure and no late delivery |
| WCO-V10 | Observe Block2 with newer notification during assembly | Distinct continuation token, stable ETag, bounded Property coalescing; Event overlap fails |
| WCO-V11 | Link-format quoted comma/semicolon/escape, repeated extensions, singleton violations, unknown attributes, malformed quote and excess links | Exact parsed values or bounded error |
| WCO-V12 | DTLS good PSK/PKI, wrong key, expired/untrusted/wrong-SAN/revoked certificate, replayed DTLS record | Authenticated operation or failure; never cleartext fallback |
| WCO-V13 | RFC 8613 known-answer vectors, modified ciphertext/AAD/KID, replay, concurrent duplicate, sequence exhaustion | Authenticated plaintext once or rejection |
| WCO-V14 | Kill OSCORE bridge after reservation/before save completion, reopen corrupt or mismatched store | No nonce reuse or replay acceptance; fail unsafe reopen |
| WCO-V15 | Receiver overflow, owner death during I/O, saturated admission, C09 stress/matrix | Bounded cleanup and correct terminal status |

The existing libcoap server fixture proves plain UDP and blockwise. Extend it
with a resource changed by a second client, so Observe establishment, changes and
cancellation are actual peer assertions. Build its OpenSSL variant for DTLS and
OSCORE. Own disposable certificates, keys, counters and resources inside the
fixture workspace. Record exact source/build options. Same-stack OSCORE testing
must be labelled as such; RFC known-answer vectors and restart/replay fault tests
are additional required evidence. A mock security callback cannot satisfy V12–V14.
