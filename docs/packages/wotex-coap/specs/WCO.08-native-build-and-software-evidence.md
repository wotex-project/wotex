---
spec:
  id: WCO.08
  title: "Native OSCORE owner, builds and software evidence"
  status: accepted
  version: 1.9.2
  owner: wotex-coap
  updated: 2026-09-19
---

# WCO.08 Native OSCORE owner, builds and software evidence

UDP exchanges remain BEAM code; DTLS remains OTP `:ssl`. OSCORE uses one
explicitly selected C executable through an Erlang Port and the pinned libcoap
exchange engine. Mix owns build/test orchestration and ExUnit owns assertions.
Python is not a runtime or target orchestration dependency. Cross-stack OSCORE
evidence runs one pinned published Java archive as a test peer only; that peer
is neither a runtime dependency, a build input of any shipped artifact, nor an
orchestration dependency, and nothing in the package or its build requires a
Java runtime. The native worker
implements same-binary startup, durable open, upload-body state, close and one
active unary libcoap exchange with inline or streamed results. It also executes
one protected Observe registration with inline or streamed reports, cumulative
credit, Max-Age renewal, stale cleanup, token-matched cancellation and
best-effort established-observation cancellation on owner EOF. The remaining
protected fault matrix and full matrix remain planned
contracts. The native build, software build, current independent UDP/DTLS
software-run cohort and same-stack OSCORE software-run cohort execute;
[provenance](../provenance/executable-evidence.md) identifies executed BEAM/OTP
and native peer evidence separately.

## WCO-N01 — Reproducible native builds

The native source is libcoap 4.3.5 at commit
`7cf7465b784baded4de183290c547d582becfd28`, archive SHA-256
`d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd`, from
`https://codeload.github.com/obgm/libcoap/tar.gz/7cf7465b784baded4de183290c547d582becfd28`.
The [public 4.3.5 OSCORE API](https://libcoap.net/doc/reference/4.3.5/man_coap_oscore.html)
owns configuration, exchange context and sender-sequence callbacks. No private
SDK layout or Python bridge is part of the interface.

Apply the ordered patches and verify their resulting source hashes from
[`native/oscore/source.json`](../../../../packages/wotex-coap/native/oscore/source.json). The sequence
patch requires a successful persistence callback before advancing the cached
boundary or encrypting a PDU. The CBOR patch avoids a null-pointer copy for a
valid empty byte string. The whole-body patch bounds advertised Size1/Size2
and cumulative byte extent at 1 MiB before SDK body allocation or resizing.
The representation patch rejects a changed ETag instead of resending the original
application request; a dispatched POST/PUT cannot be replayed to restart body
assembly. The completed-whole-body patch releases libcoap's first-response hold
after authenticated Block2 assembly so a following request is not delayed by
the internal five-second guard. The OSCORE Observe patch preserves the response
Partial IV before libcoap temporarily substitutes the request Partial IV for AAD
calculation, so the decrypted 24-bit Observe value advances with authenticated
notifications. The send-hold patch removes the OSCORE client hold that libcoap
re-armed on every `coap_send`, because a client recipient context never leaves
its initial replay state; while a request lacked a response, the next PDU
construction otherwise blocked the worker for up to five seconds. The worker
serializes exchanges and bounds each with its own deadline. The
unverified-response patch keeps a request's OSCORE association when a correlated
message fails verification, so an unverified notification cannot remove the
association a pending cancellation's confirmation needs. The
uncorrelated-plaintext patch raises the missing-protection event only for a
plaintext response whose token a pending protected request used and discards any
other plaintext response. These fixed profile policies preserve libcoap's
exchange ownership.
The native manifest records base archive, patches and
resulting source hashes separately; it cannot describe this build as unmodified
upstream. `test/native/oscore_sequence_test.c` asserts the actual public send
path on macOS and under Linux ASan/UBSan. Its narrow
[receipt](../provenance/native-sequence-v1.json) does not accept the remaining
native owner or durable store.
The [native block receipt](../provenance/native-block-v1.json) identifies the
actual UDP fault-peer regressions and Linux public allocation-length probes.
Its negative controls reproduce the unbounded estimate and new-application-request
restart behavior before the two block patches. Protected OSCORE peer/owner
coverage remains a separate requirement.

The response-admission patch rejects nonempty unprotected responses on an
OSCORE session before application dispatch and emits only
`COAP_EVENT_OSCORE_NO_PROTECTED_PAYLOAD`. Plaintext success values and error
code/diagnostic payloads cannot trigger application behavior. This is the fixed
library profile policy; [RFC 8613 Appendix D.5.3](https://www.rfc-editor.org/rfc/rfc8613.html#appendix-D.5.3)
permits unauthenticated processing errors but forbids trusting their contents to
trigger specific actions. Empty ACK/RST remain transport control and cannot
become an authenticated result. The
[native protection receipt](../provenance/native-protection-v1.json) identifies
raw UDP fault responses and a real protected same-stack peer. It does not accept
production owner, durable replay, independent-stack or complete secure workflows.

The native JSON dependency is unmodified yyjson 0.12.0, commit
`8b4a38dc994a110abaec8a400615567bd996105f`. Its
[pin and MIT notice](../../../../packages/wotex-coap/native/oscore/vendor/yyjson/source.json) identify the
archive and vendored file hashes. Compile with `YYJSON_DISABLE_NON_STANDARD=1`,
`YYJSON_DISABLE_UTILS=1` and `YYJSON_DISABLE_INCR_READER=1`; the sole read flag is
`YYJSON_READ_NUMBER_AS_RAW`. The native manifest includes these hashes and flags.
The pinned [0.12.0 API](https://github.com/ibireme/yyjson/blob/8b4a38dc994a110abaec8a400615567bd996105f/doc/API.md)
defines the fixed-pool and raw-number interfaces.

`mix wotex.native.build --workspace ABS` builds `wotex-coap-oscore` from
`native/oscore/` and the pinned static libcoap library. This task is explicit;
dependency loading and `mix compile` never build or launch the helper.
`mix wotex.software.build --workspace ABS` builds the same helper plus the
upstream `coap-server` and native fault/vector executables. The minimum
supported native environments are Linux and macOS with a C11 compiler, CMake
and an explicitly resolved OpenSSL 3 installation. Windows is unsupported by
this POSIX filesystem/process profile. The consumer supplies a built executable;
runtime downloads and system-wide installation are forbidden.

Both tasks accept exactly one `--workspace` absolute path, rejecting other,
duplicate or positional arguments. The directory is empty or has a verified
matching manifest. The OTP tar reader extracts only validated regular files and
directories; the task creates the pinned archive's two reviewed relative links
itself and verifies them, because OTP 27 rejects a `..` link target that OTP 29
accepts. Reject symlink roots, unrelated contents, archive traversal
and links escaping the workspace. Download limit is 4 MiB/30 seconds. Each
native build has a ten-minute deadline. Commands use separate argv entries.
CMake options include `ENABLE_OSCORE=ON`, `ENABLE_DTLS=ON`,
`DTLS_BACKEND=openssl`, `BUILD_SHARED_LIBS=OFF`, `ENABLE_DOCS=OFF` and
`ENABLE_EXAMPLES=ON` for peers. Compiler and OpenSSL paths/versions are resolved
once from the caller-selected `CC`, `CMAKE` and `OPENSSL_ROOT_DIR` build
environment (or fixed tool names resolved on the caller PATH), and recorded;
reuse checks their fingerprints rather than silently
selecting another installation. The Linux fault build adds
`-fsanitize=address,undefined -fno-sanitize-recover=all`.

`native-manifest.json`, schema `wotex.coap.native@1`, records source URL/commit/
archive hash, first-party native source hashes, platform, compiler/CMake/OpenSSL
versions, exact options, static-library and executable hashes, dynamic library
dependencies, feature probe and sanitizer configuration. A ready manifest is
atomic and follows successful probes of exact libcoap version and OSCORE support.
The source package includes first-party C source, build tasks and license
notices; generated helpers, SDK downloads, credentials and caches remain outside.
Runtime content binding reads `schema`, `backend` and `executables` from this
manifest. `schema` is exactly `wotex.coap.native@1`; `backend` names `libcoap`,
version `4.3.5` and revision `7cf7465b784baded4de183290c547d582becfd28`;
`executables.wotex-coap-oscore.sha256` is the lowercase SHA-256 of the selected
file. Other manifest members retain the build evidence listed above.

## WCO-N02 — Persistent Port ownership

The additive `native_backend:` connection/Transport option is exactly
`%{executable: absolute_binary_path, manifest: absolute_binary_path}`. Each path
is nonempty, NUL-free and at most 4,096 bytes; the manifest is at most 1 MiB.
Require it for `Security.mode == :oscore`, reject it for UDP/DTLS modes, and
reject duplicate/unknown keys before process creation. Runtime transport config
carries this non-secret selection; credentials never carry executable paths.
Validation checks an ordinary executable file and the exact manifest/binary
hash, without changing permissions or discovering a helper from PATH. No
application environment fallback exists. The native owner preserves the existing
opaque session/Subscription API and .11 helper signatures.

`Wotex.CoAP.NativeBackend.verify/1` implements this bounded manifest and file
identity check. Its tests include links, directories, permission modes, size,
strict JSON, source identity and post-manifest executable changes. Direct
verifier success does not admit an OSCORE session.

`Wotex.CoAP.Native.Connection` implements the BEAM startup and close-control
slice. It validates the exact options and executable identity before process
creation, launches the selected executable with only `--custody` and the
absolute context directory, accepts the pinned ready identity and correlates
the monotonic `open` and `close` commands. Its bounded byte accumulator accepts
arbitrary Port splits and rejects extra lines, incomplete EOF and frames beyond
128 KiB. The retained process state contains no credential or command line.
The worker ends its own generation after a terminal exchange failure, so a close
command can race that exit. A helper exit with status 0 and no partial frame
completes an active close with `:ok` and ends an active request with
`connection_closed` under the ordinary effect rules; any other exit during an
active operation is `native_protocol_error`. This keeps graceful disconnect
idempotent under WCO-C03.
Sixty-four contract-injection tests cover exact argv and envelopes, invalid options,
malformed/truncated/oversized input, wrong and duplicate response identities,
finite waits, status redaction, admission-owned close control and owner-death
cleanup within C03. The injected test executable is not the production OSCORE
worker. Its unary fixture covers owner-side inline responses and a correlated
32,769-byte body stream across split/coalesced Port data. Exact hash, request ID,
single-body and one-time body-reference rules prevent partial delivery. Outbound
explicit payloads execute begin, 32,768-byte chunks and end before the request,
all under the original deadline. Upload error, timeout, close and identity
exhaustion precede the native request submission marker and preserve effect
`none`. The public root API selects this owner only for an explicit `coap`
OSCORE credential plus verified backend, preserves the two-field session value,
normalizes `send/2` and method-helper inputs, and dispatches unary requests and
disconnect. Public `discover/2` applies its 64 KiB ceiling to the native request;
an oversized streamed `body_begin` fails before body assembly and closes the
generation. Public native Observe validates admission before Port traffic,
opens the initial zero-credit window, delivers a complete initial report before
returning its handle and owns exact cancellation/cleanup. Inline and 32,769-byte
streamed reports execute through contiguous frame accounting and cumulative
credit. Cancellation takes over while credit is in flight, joins concurrent
callers and validates intervening reports without delivering them. Receiver
death releases the generation. `profile(:oscore)` and `Wotex.CoAP.Transport`
select this owner for Runtime unary calls and observations. The relay validates
non-secret route and subscription-generation markers before accepting either
resource, preserves the one interaction deadline and aborts only the exact
owned adapter during bounded cleanup. The injected Runtime fixture proves this
dispatch contract; it is not the production worker or a protected exchange.

`native/oscore/main.c`, `worker.c` and `exchange.c` implement the corresponding
same-binary lifecycle plus unary and inline Observe exchange slices. The public entry accepts
only `--custody ABS_DIRECTORY`; the
guardian executes that same absolute file with only `--worker`. The internal
worker emits the pinned ready frame, accepts split or coalesced C07 commands,
decodes and erases credentials, derives the fixed-suite identity, consumes and
locks the exact working-directory store at boundary 32, assembles one outbound
body, and writes correlated close before releasing its store. A production
`WCO_WITH_LIBCOAP` build verifies the exact SDK package version, creates one
OSCORE context/session, binds sequence reservation to that store, dispatches one
active unary request and emits complete authenticated responses inline at or
below the threshold or as correlated begin/chunk/end frames above it. libcoap owns
tokens, retransmission and whole-body
Block1/Block2. Its nonblocking 512 KiB queue tracks each frame's original
deadline. The macOS lifecycle test retains lock, consumed-identity, escaped-ID
and malformed teardown coverage. A same-stack peer additionally executes
protected GET, a 32,769-byte Block2 stream and Block1 POST through public custody
on macOS and Linux. The same peer then registers a protected Observe, proves the
initial report stays silent at zero credit, acknowledges each completely written
report, receives a fresh 32,769-byte notification through five credited frames
and renews after its zero Max-Age using the same token and a new Message ID. A
second worker emits its initial zero-Max-Age report before disabled-renewal stale
cleanup and best-effort cancellation. Cancellation of the renewed observation
also uses the original token. The Linux static build uses ASan/UBSan and leak
detection. This evidence accepts inline and streamed reports plus the two
Max-Age expiry policies. The peer also executes negative status, missing Observe,
changed Content-Format and deadline renewal faults with exact terminal codes,
then exhausts report credit to prove latest-Property coalescing and terminal
Event overlap. The native freshness primitive executes equal, older, half-range,
128-second escape and representation-identity ordering cases, while a protected
peer starts at Observe FFFFFF and delivers zero next. The software run relays a
captured authenticated notification after a newer one through the Mix-built
helper and receives no value. A further
protected run cancels while renewal is in flight: when tracked cancellation is
unavailable, the exchange submits an original-route/token public-API fallback,
the peer receives it once with a new Message ID, and the peer's response
confirms the cancellation with `result: null` inside the 1,000 ms command
deadline. In further runs the peer sends a notification after the worker sends
a cancellation and before the peer answers it. That notification produces
neither a report nor success; the confirmation then returns `result: null`, or
`timeout` when the peer never answers. A notification in flight across a
Max-Age renewal is discarded and the renewal response delivers the next report.
Replay, independent OSCORE interoperability and the final Mix-built helper
remain unaccepted. Another protected run closes the public custody owner's
input after establishment. The worker sends one original-route/token
cancellation during exit cleanup, the peer removes its observer, and custody
reaps the worker with exact owner-loss status within C03. Receiver death
through the production BEAM owner executes in the
same-stack software run described in N05. Owner EOF while a registration or
renewal awaits the peer produces exactly one original-token cancellation during
exit cleanup; owner EOF while a cancellation awaits the peer produces none. Each
case reaps the worker with exact owner-loss status within C03. A saturated
variant fills the actual owner output pipe to `EAGAIN`, stops owner reads and
dispatches fourteen protected 16 KiB notifications across two credit intervals.
Their base64 payload bytes exceed custody's 262,144-byte output capacity. Network
progress and the same cancellation/cleanup bound hold under that backpressure.
The software run suspends the actual native owner and samples its mailbox while
a protected peer sends notifications: at most eight report frames and one
in-flight credit reply wait there, a Property terminal still arrives through its
reserved control slot with the window full, and killing the suspended owner
cancels the observation and reaps the helper within C03. That lane does not also
fill the OS pipe, because the runtime keeps draining the Port. The event loop waits on libcoap network
readiness and its next timer together with the owner pipes, so no fixed owner
poll interval paces a protected exchange; the harness bounds 32 sequential
protected GET exchanges below one second. Each session seeds libcoap's token
counter with 8 random bytes. A response whose token has no request association
(`COAP_EVENT_OSCORE_NO_SECURITY`) or a datagram libcoap discards as malformed
(`COAP_EVENT_BAD_PACKET`) is ignored without ending the active exchange. Exit
cleanup services its best-effort cancellation for at most 20 ms,
inside custody's 25 ms termination signal, so a peer's separate confirmable
response is acknowledged rather than retransmitted toward a reused endpoint.
The worker handles that SIGTERM by ending its event loop with status 143: a
worker the scheduler has not run before the signal still sends the exit
cancellation and then exits without servicing its response. Custody's SIGKILL
at half its cleanup budget remains the bound.
While an observation exists, including while its renewal or cancellation is
pending, a message that fails decryption, lacks protection or fails OSCORE
decoding is discarded and the observation continues, as RFC 8613 section 8.4.2
requires for notifications. A pending renewal or cancellation then completes on
its own response or deadline. The worker reports `remote_response` with the
numeric status only for a class 4 or 5 response code (128..191), whether the
response answers a unary request, an Observe registration or a renewal. Any
other code outside 2.00–2.30 (64..94) ends that operation with
`invalid_response`.

`Wotex.CoAP.Native.Admission` implements the pre-mailbox capacity primitive for
this owner. One generation-bound ETS table admits exactly 64 ordinary calls and
one separate close-control record. Atomic reservation and submission markers
retain caller/deadline ownership across timeout races, reject foreign generation
capabilities and make closing terminal for later admission. Four tests exercise
the exact concurrent limit, singular close control, caller death, timeout and
table-owner termination. The startup owner does not yet publish or consume this
table outside its internal request boundary. It owns the table, consumes
ordinary leases in FIFO order and consumes the singular close record: a full
64-call reservation set cannot prevent close, concurrent close callers wait for
the same process termination, and abandoned close control ends the generation.
Queue time spends the original deadline; queued timeout or caller death prevents
Port submission, while active mutation uncertainty is retained after submission.
This request boundary accepts normalized parameters with an absent or explicit
binary payload and inline or streamed responses. The root connection API exposes
that boundary for explicitly selected OSCORE unary sessions and passes a bounded
per-call response limit for discovery. The fixture does not accept the production
helper or an actual protected exchange.

Arguments contain no secrets. `Port.open({:spawn_executable, path}, ...)` starts
one helper for one native session. No shell, daemon discovery, global registry,
NIF or second BEAM retransmission engine participates. Its stdout carries only
C07 protocol-version-1 JSON lines. Secrets enter only the bounded open envelope
over stdin. Native logging is disabled; diagnostics contain finite codes and
counters. Raw stderr never becomes an Error or telemetry field.

Ready must arrive within the lesser of the caller budget and 5,000 ms and name
`backend: "libcoap"` plus the exact revision. Unsupported version/revision,
wrong/duplicate result ID, malformed/truncated/oversize frame and EOF terminate
the generation. The BEAM owner monitors the caller and the exact native process.
An independent owner-death mechanism must release a helper even while a callback
or Port writer is blocked. Cancellation closes subscriptions, releases the
libcoap session/context and closes the store lock. The total C03 cleanup grace
is at most 1,000 ms, including graceful close and forced process termination.
Blocking reads on stdin cannot prevent libcoap timers or owner EOF handling.

The helper owns one libcoap context/session, at most 64 admitted unary calls
including one active exchange, and at most one Observe registration. An active
observation dedicates that session; unary calls or a second registration return
`observation_active` as required by .10. Deadlines
include IPC queue time. Setup/control capacity is separate so saturated unary
work cannot prevent cancel/close. libcoap alone owns retransmission, tokens,
Observe and Block1/Block2 exchanges. Use `COAP_BLOCK_USE_LIBCOAP` and the whole-body
callback policy; do not emit a report until complete authenticated assembly.
Preserve .10 report freshness, cancellation, Property coalescing and Event-loss
rules. OSCORE interoperability against libcoap is labelled same-stack.

## WCO-N03 — IPC values and bounded body transfer

C07 retains its 128 KiB line, depth-eight, 1,024-entry/container and
4,096-node limits. IDs are 1..64 printable ASCII bytes and never reused in a
generation. The BEAM sender allocates monotonically increasing unsigned 64-bit
identities scoped to that generation and fails before exhaustion or reuse. The
helper retains only the bounded outstanding request/control identities, not an
unbounded historical-ID set. Duplicate outstanding IDs fail admission. Late SDK
callbacks retain their original exchange identity and cannot attach to a later
request. Operations are `open`, `body_begin`, `body_chunk`, `body_end`,
`request`, `observe`, `credit`, `cancel` and `close`. Each uses the C07 request/reply
envelope and a finite `timeout_ms`; unknown fields and operations fail closed.
The operation-specific parameter fields are:

| Operation | Parameters |
| --- | --- |
| open | `host`, `port`, positive unsigned 64-bit `generation`, `security` (.10's exact OSCORE fields); one per generation |
| body_begin | `body_id`, `length` (0..1,048,576), lowercase hex `sha256` |
| body_chunk | `body_id`, zero-based byte `offset`, C07 bytes envelope `data` |
| body_end | `body_id` |
| request | `method` (GET/POST/PUT/DELETE), `path`, `confirmable`, optional `accept`, `content_format`, `body_id` |
| observe | `path`, `confirmable`, `observation_kind` (`property` or `event`), Boolean `renew`, optional `accept`; GET with Observe=0 |
| credit | `generation`, `ack_seq` (unsigned 64-bit cumulative report-frame acknowledgment); fixed eight-frame window |
| cancel | `subscription_id`, `generation`; original route/token only |
| close | empty object |

Every request envelope contains exactly its five C07 fields. `timeout_ms` is an
integer in 1..60000; no operation receives an infinite or renewed wire deadline.
The native `open.security` object has all seven canonical fields: `mode` is
`"oscore"`; `master_secret`, `master_salt`, `sender_id` and `recipient_id` use
C07 bytes; `id_context` is explicit null or C07 bytes; `context_store` is a
NUL-free absolute UTF-8 path of at most 4096 bytes. The BEAM sender normalizes an
omitted public ID Context to null. Native host values are numeric IPv4/IPv6
text, ports are 1..65535, and generations are nonzero unsigned 64-bit integers.
Optional request `accept`, `content_format` and `body_id` fields are omitted
when absent, never replaced by null. Observe requires its explicit kind and Boolean `renew`; omission, null, numeric
or textual truth values fail admission. `renew` retains the .10 freshness policy,
including the one-second minimum interval for a zero Max-Age.

The [native command receipt](../provenance/native-command-v1.json) accepts only
structural command admission: exact field allowlists, scalar/byte/path bounds
and erased failed outputs. The decoder performs no file/socket/SDK acquisition.
Its parameter object borrows the parser pool until reset; queued work must copy
validated values into its own bounded storage before releasing that pool.
Admission does not prove a valid body reference, remaining deadline, free queue
slot, native session state or wire-size budget; the worker checks those before
SDK dispatch. Live worker/Port tests remain separate.

`Wotex.CoAP.Native.Command` implements the matching BEAM transmit boundary. It
validates normalized atom-keyed parameters, emits exact five-field JSON lines,
omits absent optional request values, encodes all byte fields canonically and
allocates monotonically increasing decimal uint64 identities once per generation.
Its six tests cover every operation, input and line bounds, credential
projection and fail-before-wrap exhaustion. The allocator retains no secret or
command bytes. `Native.Connection` now writes admitted body/request commands
through this boundary, resolves correlated inbound body streams before reply and
does not mark a mutation submitted while its body alone is being uploaded. It
also writes observe/credit/cancel commands for the dedicated native observation
lifecycle. Live production helper admission remains an owner obligation.

`Wotex.CoAP.Native.Wire` implements the pure BEAM receive boundary for complete
lines, ready identity and request/control response envelopes. It enforces the
same frame limits, native integer domain, printable correlation IDs, canonical
bytes, inline threshold and Message option/header rules. A streamed-body result
requires a previously completed binary from the owner, and the resulting
Message contains that binary rather than its native body ID. A `remote_response`
failure requires a status in 0..255 and exposes it as `details.code`, so native
and datagram sessions return the same .11 negative-response shape. Its ExUnit tests
cover the receiver-side outcomes corresponding to F01, F02, F08 and F10–F13.
`Wotex.CoAP.Native.Body` admits exact begin/chunk/end event objects, retains at
most the declared 1 MiB body, poisons and drops its body reference after failure,
and releases bytes only after exact length and SHA-256 verification. Its tests
execute F03, F04 and the failed-body sequence in F14. These pure components do
not run the native helper, correlate common event envelopes, close a process
generation or accept the complete native corpus.

`Wotex.CoAP.Native.Report` implements exact common envelopes for unary body
events, subscription body events, complete reports and reserved terminal errors.
It binds subscription generation and report sequence, validates the five report
metadata fields against the reconstructed Message options, and requires a
terminal control shape without a report sequence. Its tests cover the
inline/streamed threshold component of F15. `Native.Connection` supplies sequence
continuity, acknowledgment and protocol-fixture execution; live production
helper execution remains an acceptance obligation.

`Wotex.CoAP.Native.ReportLedger` implements the BEAM-side immutable credit state
for one established subscription generation. It admits only contiguous report
sequences, retains at most eight frames and 1 MiB of newline-terminated wire
data, holds one complete report behind an exact delivery token, and proposes
only a consumed contiguous prefix. A proposal remains in flight until its exact
successful credit response is recorded. Its tests execute the owner-side
accounting component of F15. `Native.Connection` adds process-level receiver
admission, inline/streamed report delivery and in-flight-credit cancellation;
live native replay remains an acceptance obligation.

Paths and content-format numbers obey .10/.11. Body chunks decode to at most
32,768 bytes; offsets must exactly equal the next expected offset. The byte
envelope admits only its exact `type` and `base64` fields. Its base64 uses the
standard alphabet, required final padding and zero unused pad bits; whitespace,
URL-safe characters, embedded NUL and noncanonical encodings fail admission.
This is the library's strict decoder policy using the standard alphabet and
canonical encoding rules in [RFC 4648 §§3–4, October 2006](https://www.rfc-editor.org/rfc/rfc4648.html#section-3).
Validate the entire encoded input and decoded length before writing output. Only one
unfinished inbound body and one unfinished outbound body exist at a time.
`body_end` verifies declared length/hash; a body is consumed once by the next
associated operation or freed at deadline/close. Uploading a body sends no CoAP
traffic. Empty payload and absent payload remain distinct input choices.

Responses and stream reports carry a complete payload inline when it decodes to
at most 32,768 bytes, or use `body_begin`/`body_chunk`/`body_end` events for a larger
body. The two choices are mutually exclusive. Body events on stdout use `id`
naming their originating call or subscription and
`generation` for subscriptions. The begin event carries `body_id`, `length`
and `sha256`; chunk carries `body_id`, `offset`, `data`; end carries `body_id`.
A unary `request` success `result` or report `value` is an exact message object with `type`
(`con`, `non`, `ack` or `rst`), `code` (0..255), `message_id` (0..65535), `token`
(C07 bytes, 0..8 bytes), and `options` (at most 64 ordered objects with exact
`number` and C07-byte `value` fields). Option numbers are 0..65535 and each value
is at most 1152 bytes; the existing stricter known-option length, repeatability,
critical-option and aggregate header limits apply. The message has exactly one
of `payload` (C07 bytes, at most 32768 decoded bytes) or `body_id` (a previously
completed body for this originating request/subscription). Empty payload is an
explicit empty bytes envelope. Both fields, or neither field, fail admission.
A failed body never permits a final success or public partial delivery. A body
reference is resolved once before public construction; caller-visible Messages
contain complete binary payloads, never native body IDs.

Successful `open`, `body_begin`, `body_chunk`, `body_end`, `credit`, `cancel`
and `close` replies have `result: null`. Successful `observe` establishment has
exactly `result: {subscription_id: original_observe_request_id, generation}`.
Establishment follows the first complete, authenticated, successful response
containing a valid Observe option. This control reply precedes that first report
on stdout and consumes no report credit. The first report remains retained until
credit permits delivery. A report has `event: "report"`, `subscription_id`,
`generation`, `report_seq`, a Message `value`, and exactly five `metadata` fields:
`code` (64..94), `observe` (0..16777215), `etag` (null or C07 bytes of length
1..8), `content_format` (null or 0..65535) and `max_age` (0..4294967295).
Metadata equals the corresponding validated Message options; absent Max-Age
means 60. The wire envelope carries no caller PID or native address.

A `cancel` request retains its own command ID and the original subscription
identity. An intervening response with Observe is neither cancellation success
nor a post-cancellation report. Only a correlated successful response without
Observe completes `cancel` with null. Failure or deadline releases the local
session without a successful cancellation result. No report follows a successful
cancel reply. Registration failure produces no establishment or report. The
exact schema and ordering vectors remain specified until a real helper/owner
runner executes them. An established subscription failure emits at most one
terminal envelope with exactly `version: 1`, `subscription_id`, `generation`,
`event: "error"`, `value: {code: finite_library_code, status?: numeric_status}`
and `metadata: {}` before local close. It has no `report_seq`, uses a reserved
control slot and consumes no report credit. A failure before establishment uses
only the original command failure envelope. A blocked terminal channel cannot
delay local cleanup.

An inline report consumes one report-frame credit. Each begin, chunk, end and
final envelope of a streamed report consumes its own credit in order. A 32769-byte
report using 32768-byte chunks consumes five credits. Frame/depth limits are
checked independently of decoded body size. No partial chunk reaches the public API. A mismatched
hash, missing chunk, interleaved body, extra bytes or late generation is a
terminal protocol failure. Chunk framing changes no public .10 body limit.
The body limit is enforced before allocation and before base64 decoding.
The native JSON reader rejects duplicate decoded keys and Unicode/number
violations before field lookup. Its parser uses one fixed 2 MiB yyjson pool,
without allocator fallback. It retains numeric tokens, capped at 128 bytes, so
64-bit generations, sizes and offsets never pass through a floating-point
conversion. Integer fields reject Boolean, fractional and exponent tokens;
mathematical negative zero is zero. A separate C-locale range check rejects
non-finite values and underflow to zero while permitting representable subnormals.
The eight-level depth count includes the root container; the 4,096-node count
includes containers and values, excluding object keys.

One fixed 131,072-byte ingress buffer accepts arbitrary byte splits and multiple
lines per read. It never stores an extra byte past this bound. Each complete
line is parsed synchronously before the next line; malformed input, callback
failure or truncated EOF permanently closes this generation. A clean EOF also
closes input and cannot be followed by another request. Parser pools and consumed
line bytes are erased after use or failure. Native parser/framer tests assert
these primitives. Native body and credit tests assert complete length/hash
admission, canonical byte decoding, cumulative acknowledgments and exhaustion.
The complete helper process, deadlines and mailbox/queue fault tests remain
separate acceptance obligations.

Report flow begins with zero credit. The first `credit` with `ack_seq: 0`
opens an eight-frame window exactly once per generation. Every body event or
final report has a strictly increasing unsigned 64-bit `report_seq`, starting
at one; assigning its sequence consumes credit before native queue admission.
The helper tracks the highest assigned, fully written and acknowledged sequence.
A subsequent `ack_seq` advances the contiguous acknowledgment only when it is
greater than the last acknowledged value and no greater than the highest fully
written value. New allowance is exactly `8 - (assigned - acknowledged)`.
Duplicate or older acknowledgments succeed without changing allowance, including
when their C07 request IDs differ. An acknowledgment beyond the fully written
sequence or from a different generation is a terminal protocol error. Sequence
exhaustion terminates the generation; no wrapping or resetting is permitted.
Only one unacknowledged credit command may be sent by the BEAM owner at a time.

The BEAM owner acknowledges a frame only after validating and accounting for it
within bounded assembly/delivery state. At most one complete report is queued
per subscription and one body per direction is assembled. The consumer queue
bound in C05 also applies before public delivery; draining the Port cannot bypass
it. Suspending the BEAM owner therefore stops acknowledgment. At most eight
unacknowledged frames, each at most 131,072 wire bytes including newline, can
occupy native output, the pipe and the Port mailbox together: 1,048,576 report
wire bytes. Decoded body buffers and the single queued complete report each
retain their separate 1 MiB bounds; control reservations below are additional.
Tests replay old and duplicate credit using distinct request IDs and require
unchanged outstanding allowance and no extra report frames.

The helper uses nonblocking stdout with a 512 KiB output queue. Two separate
control-frame slots, each at most 4 KiB, are reserved for terminal/cancel/close
results and require no report credit. It never blocks the libcoap event loop on
stdout or waits for report credit to process cancel/close. Property overload may
retain only the latest complete representation; Event overload emits a terminal
loss and releases the subscription. A blocked control channel invokes bounded
local termination; emitting a terminal envelope is not a prerequisite for cleanup.
Tests suspend the actual BEAM owner, sustain native report production, sample
the Port mailbox/output queue and verify exact bounds, then cancel or kill the
owner and prove cleanup within C03 even with both report and OS pipe saturation.

## WCO-N04 — Durable context and sequence admission

The .10 single-generation context policy is mandatory. The store is an absolute
caller-owned local directory with exclusive lock; symlinks and nonlocal/network
filesystems are outside this profile. A versioned registry binds records to
the complete RFC 8613 KDF input identity, using a SHA-256 fingerprint without
persisting raw secrets. Records contain the consumed-context marker and next
reserved sequence boundary. Limit the registry to 4,096 contexts and 1 MiB;
full capacity returns `context_store_full`, never deletes used identities.

Full-input identity alone is insufficient: changing only a recipient ID leaves
the sender's key/nonce space intact. In addition to the full-input fingerprint,
retain two role-independent protection-space fingerprints. Each hashes a
domain separator, the derived 16-byte key and the first eight bytes of the
RFC 8613 zero-Partial-IV nonce for that directional ID. The remaining five
nonce bytes range over the complete 40-bit sequence space. Reject overlap with
either stored direction, including swapped roles and equivalent HKDF salt
encodings. This is the library's strict single-generation admission policy.
OpenSSL's public HKDF/SHA-256 API derives these identifiers; libcoap remains
the only packet protection and exchange engine. Exact C.1–C.3 key/IV vectors
and directional-overlap cases assert the derivation.

The full fingerprint is SHA-256 of ASCII `wotex.oscore.context@1` followed by
the shortest definite-length CBOR array `[master_secret, master_salt,
sender_id, recipient_id, id_context, 10, -10]`; absent ID Context is CBOR null,
distinct from an empty byte string. Each directional fingerprint is SHA-256
of ASCII `wotex.oscore.space@1`, the 16 key bytes and the eight nonce-prefix
bytes, concatenated in that order. Domains contain no trailing NUL byte.

The concrete store requires an existing mode-0700 directory owned by the
effective user, with no symlink path components or unrelated entries. The
directory contains mode-0600 `context.lock`, `contexts.v1` and at most one
`contexts.pending` file; regular files have exactly one hard link. A missing
registry beside an existing lock, or an existing registry beside a missing
lock, is corrupt state. Do not recreate either as an empty store. The lock is
nonblocking `flock`, held by its open descriptor until native session release.
macOS requires a filesystem marked local. The Linux local profile admits
ext2/3/4, XFS, Btrfs, ZFS, overlayfs and tmpfs; unknown and network filesystems
fail admission. Persistence follows the backing store: disposable tmpfs/test
volumes do not preserve a registry after that storage is destroyed. The
consumer's registry-preservation obligation below applies to every medium.

The registry format is `WCOREG01` (eight ASCII bytes), a big-endian 32-bit
record count, that many 104-byte records, and SHA-256 of all preceding bytes.
Each record contains the full-input, sender-space and recipient-space hashes
(32 bytes each), then an exclusive big-endian 64-bit reservation boundary in
`1..2^40`. Its presence is the consumed marker. Exact length, checksum, count,
file kind and permissions are validated before admission. The checksum detects
corruption; it is not an authentication or rollback mechanism. No record is
removed, and no caller label or raw key is persisted.

Before inbound traffic or the first encryption, atomically record consumption
and a future sequence reservation: write a mode-0600 sibling temporary file,
fsync the file, rename over the registry, then fsync its directory. An exclusive
lock spans validation through final session release. The consumer must preserve
the entire registry and provision fresh keying material when it is lost;
deletion/rollback cannot be detected cryptographically by this local store.
Existing missing, corrupt or mismatched records never authorize reuse.

Use `coap_new_oscore_conf`'s public sequence-save callback. It acknowledges
success only after the requested future boundary is durable. Native source
tests at the pinned revision with the N01 sequence patch prove callback failure
prevents encryption and transmission, including repeated attempts after failure.
The adapter must also stop the failed session. No unchecked upstream example using
only `fflush` satisfies this requirement. Exhaustion of the 40-bit Partial IV
space terminates the context. A helper exit permanently consumes that identity;
reopen returns `fresh_context_required` even after graceful close. This policy
avoids claiming persisted receiver replay state absent from the public SDK.
The live replay window is 32; replays and concurrent duplicate ciphertexts
produce no second public value.

Error codes include `unsupported_native_backend`, `native_protocol_error`,
`native_unavailable`, `context_store_locked`, `context_store_corrupt`,
`context_store_full`, `context_store_unavailable`, `invalid_context_store`,
`fresh_context_required` and `sequence_exhausted`.
Map to the finite C04/I04 class table. Pre-transmission failures have effect
`none`; an uncertain transmitted mutation has effect `unknown`, retryable false
and class permanent. No automatic bridge restart or security downgrade occurs.

## WCO-N05 — Software run and proof

`mix wotex.software.run --workspace ABS` verifies the manifest, owns disposable
native peers/ports/stores and runs ExUnit with `--include interop --include software
--exclude hardware`. Required setup cannot become an ExUnit skip. Ready timeout
is 15 seconds, suite timeout 300 seconds, combined log bound 16 MiB and total
harness cleanup five seconds. These harness limits do not extend C03 library
deadlines. EOF, owner death and test failure stop only manifest-owned processes.
Each peer process, `coap-server` and the Java runtime of the independent peer,
runs under an owner-liveness guardian that terminates the peer's process group
when the pipe from its owning test BEAM closes. An abrupt exit of that BEAM or
an interrupted run therefore leaves no peer process after the harness cleanup.
The guardian is the workspace's native command guardian with output bound 0:
the peer writes its combined output to the owning BEAM's pipe directly, without
the 16 MiB relay bound of build steps, because a debug-level libcoap peer logs
every PDU and exceeds that bound on a 1 MiB OSCORE body.
The implemented cohort runs `test/interop/libcoap_test.exs`,
`test/interop/dtls_test.exs`, `test/interop/dtls_pki_test.exs`,
`test/interop/oscore_test.exs`, `test/software/independent_oscore_test.exs`,
`test/software/lifecycle_stress_test.exs`, `test/software/native_corpus_test.exs`,
`test/software/native_saturation_test.exs` and
`test/software/peer_guardian_test.exs` with seed zero. Fifteen tests cover independent
libcoap UDP, PSK and PKI unary, Block1/Block2, Observe, Runtime and
certificate/record-fault paths. Twelve same-stack tests drive the manifest-bound
helper through the public native owner against the software-build `coap-server`
configured with a matching OSCORE context: protected methods, negative status,
bodies above the inline threshold, discovery, a 1 MiB Block1 upload and Block2
download, an authentication failure, Observe changes from a second UDP client,
receiver and owner death, context consumption after close, a real ConsumedThing
read, uncorrelated and malformed relayed responses, replayed, stale, tampered and
unprotected notifications, and acknowledgment of the peer's
confirmable response to exit cancellation. Eight stress tests run each of UDP,
DTLS PSK, DTLS PKI and OSCORE through 1,000 sequential operations, 32 correlated
concurrent callers, the exact 64-call admission bound, 100 open/close, 100
Observe/cancel and 100 receiver-termination cycles, receiver overflow, and forced
deadline, malformed-response and peer-close failures. Every completed cycle
returns owner ports and processes to baseline within 1,000 ms. Two guardian
tests start a libcoap peer and the independent peer from a child BEAM through
the same peer helpers, kill that BEAM with SIGKILL and require every process
that names the peer's executable to end within five seconds. The run retains its result
directory on success or failure, so another run requires a fresh disposable
software-build workspace.

`result.json`, schema `wotex.coap.software@1`, records subject/dependency/fixture/
native hashes, exact commands, seed, toolchain, native features, all scenario
IDs, exit codes, outcomes, log hashes and final process/socket/session/context/
subscription/store-lock counts. `cleanup.peer_processes_retained` is the number
of live processes whose executable or arguments name a file in the run
workspace, measured after the suite and its cleanup. A nonzero count fails the
run, and the field is never written without that measurement. Failure evidence
is retained; secrets and machine-specific source paths are excluded from
publishable records.
UDP and DTLS peers are independent-stack; OSCORE libcoap peers are same-stack;
the Eclipse Californium plugtest peer is independent upstream-stack for OSCORE;
fault peers and contract injections are labelled separately.

The independent OSCORE peer is `org.eclipse.californium:cf-plugtest-server`
3.14.0, admitted by exact SHA-256
`0bf82d45791eeebbf9d781d0e66f47ddafe67ba36984a432771127f1ee6dd7d5` after an
explicit build-time download, and executed by a caller-selected Java runtime
recorded by path, content digest and version. Its CoAP engine, OSCORE
implementation, replay window and observation model are upstream of this
repository, so its results are cross-stack evidence rather than same-stack
evidence. Its fixed server context is AES-CCM-16-64-128 with HKDF-SHA-256,
master secret `0102030405060708090a0b0c0d0e0f10`, master salt
`9e7ca92223786340`, server sender ID `02`, recipient ID `01` and ID Context
`37cbf3210017a2d3`, so the client uses sender ID `01` and recipient ID `02` with
that ID Context. The peer admits one client sender identity and keeps a replay
window across its lifetime, so each case owns one peer instance, one loopback
port pair and one fresh client context. `test/software/independent_oscore_test.exs`
asserts protected GET/POST/PUT/DELETE codes, the exact Location-Path of the
protected POST, protected discovery containing `</oscore>;osc`, a 1,280-byte
Block2 body and a Block1 upload read back exactly, three ordered notifications
with distinct Observe values and Max-Age 5 whose delivery stops after
cancellation, a relayed duplicate protected response that yields one result and
no client retransmission, and a relayed one-bit ciphertext change in a
notification that is discarded while the observation continues.

Required executable vectors include RFC 8613 Appendix C KDF/protected-message
answers; changed ciphertext/AAD/KID; replay/duplicate; 40-bit exhaustion;
crash after reservation/before transmission; fsync/rename/directory-sync failure;
locked/corrupt/lost/full store; second-generation reuse; every frame split and
truncated EOF; 128 KiB+1 line; 32 KiB+1 chunk; wrong offset/hash/generation;
credit replay/future acknowledgment; blocked stdout; owner/helper death during each operation; and exact cleanup.
Native tests assert outputs and counters, not identifier presence.

The final suite includes all .10/.11/.12 corpora, plain/PSK/PKI/OSCORE unary,
Observe and Block1/Block2 interactions, 1,000 sequential operations, 100
open/close cycles, 100 Observe/cancel cycles, 100 receiver-termination cycles,
32 concurrent callers and sustained
Property/Event overload. Run Elixir 1.18.4/OTP 27.3.4.15 and
Elixir 1.20.2/OTP 29.0.4 with isolated builds, PLTs and temporary directories
per invocation/lane, Linux ASan/UBSan and clean
committed-source/package gates. The current software-run receipt accepts only its
15-test independent UDP/PSK/PKI cohort, 12-test same-stack OSCORE cohort, 8-test
stress cohort, 2-test saturation cohort and 13-test native corpus cohort. The
50-test run passes on macOS arm64; the 47-test run of the preceding commit passes
inside Linux arm64 containers on both required runtimes, whose builds compile the
native vectors with ASan/UBSan. From fresh clones of committed sources, `mix check`
passes on both required runtimes as an unprivileged user, including the Hex archive
and out-of-tree compilation gate, and both runtimes produce the byte-identical
archive. The independent upstream-stack OSCORE cohort executes its five cases
against Californium 3.14.0 on macOS arm64 through the manifest-bound helper;
its renewed full-run receipt and its Linux lanes remain open, and Group OSCORE,
context re-derivation and a second independent stack remain unaccepted. Earlier Python-run results validate their historical cohort only. Hardware and publication are separate.

The [native corpus](../../../../packages/wotex-coap/priv/fixtures/native-v1.json) contains exact decoder/body/control
inputs and deterministic lifecycle traces. F01-F04, F08 and F10-F15 execute
against the BEAM decoders. F06 and F16-F20 execute through the manifest-bound
helper in `test/software/native_corpus_test.exs`, whose UDP socket stands in for
the peer and counts datagrams. F05, F09, F15 and F21-F24 run through the same helper against an
ExUnit-owned RFC 8613 endpoint that is independent of libcoap and verified
against the RFC 8613 Appendix C vectors. Because helper tokens are random, those
traces name the answered request and substitute its wire Message ID and token.
F05 and F24 now name the native terminal codes, because `session_lost` is a
Runtime transport status. F07 executes in the native store-send vector, because a
helper context opens at sequence zero and cannot reach 2^40. The
ExUnit runner expands `repeat_ascii` to its declared byte count, adds the
matching generation/id envelope to body events, and compares actual native
outcomes with `expected`. For the credit traces, `grant_report_credit` means the first `ack_seq: 0`
command opening the fixed window; further steps supply cumulative `ack_seq`
and distinct C07 request IDs. Each report fits one frame and
the test owns a writable drained control channel while the BEAM owner is
suspended; the ninth report occupies the single pending Event slot and the
tenth triggers terminal loss. No production adapter receives expected values.
`repeat_byte` objects in corpus byte values are runner directives: expand the
specified octet/count to bytes and base64-encode before serializing the actual
C07 envelope. The directive object itself never reaches the native decoder.
Cases F10–F15 assert inline threshold/plus-one, ambiguous or missing payload
fields, failed-body terminality and inline/streamed report credit accounting.
These representative cases supplement, rather than replace, the N05 matrix.
