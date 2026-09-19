---
spec:
  id: WOP.07
  title: "Native OPC UA executable and software acceptance"
  status: accepted
  version: 1.1.49
  owner: wotex-opcua
  updated: 2026-09-19
---

# WOP.07 Native OPC UA executable and software acceptance

This accepted target is **partially implemented**. WOP-P00 accepts the pinned
source/build/bootstrap and portable process-custody boundary, and WOP-P01 accepts
pure typed values plus production SDK value projection, for the exact cohorts
in executable evidence. P02 now connects bounded input framing and
outer-envelope validation to the executable and admits one secure open/read/write/call/browse/close path.
The pure owner-side encoder now maps the ready clock sample and emits closed
outer request frames. The internal owner handles one bounded terminal control
for an explicit request and now validates correlated open/read/write/call/browse/close successes and
replenishes consumed output credit.
The C ingress checks the `open` parameter shape and rejects malformed or
downgraded values before a network attempt. Native credential preflight now
verifies DER/PKCS#8 inputs, keys, direct-CA trust, exact SAN/URI, usage, validity,
signatures and the current issuer CRL. Invalid credentials end with
`certificate_invalid`. The complete-DER pin verifier is installed by the
native configuration adapter and exercised by the production executable and
the separate C probe against the same-stack Basic256Sha256 C peer. The executable
checks the server's timeout revision and NamespaceArray before reporting open.
The C process owner now admits up to 64 application operations through an
injectable service boundary, dispatches queued work in admission order on a
later loop tick and answers each operation with one success or request-scoped
failure. `cancel` and `close` use separate control admission; `cancel` retires
queued work without I/O and sends the SDK Cancel service asynchronously for sent
work, preserving unknown effect for a sent Write or Call. `health` uses the Read
service path. Session loss, malformed input, credit violations and duplicate
outstanding IDs remain terminal. The production owner binds WOP-X-F17 through
F20, F49, F50 and F52 through F55 with an explicitly injected service.
`Native.Host` now admits 64 outstanding requests from monitored callers,
splits arbitrary Port chunks into complete lines, replenishes credit for each
validated line and keeps request-scoped failures non-terminal. A caller timeout
or death sends one bounded `cancel` control whose missing acknowledgement ends
the generation. Terminal controls, invalid output and responses for another
generation fail each unanswered request once: sent Write/Call keep unknown
effect, other requests and calls never emitted report none. Lines and a
terminal control that the native process wrote before exiting are handled in
order: credit for them is not sent to an exited process, and its exit status
ends the generation only after them. Owner death fails each unanswered request
with `native_owner_lost` and its effect, and sends that error once to each live
subscription receiver. Each pending request and control owes one native output
line; the host admits a request only while fewer than 64 are owed and sends a
timeout or caller-death `cancel` only while fewer than 80 are owed, so bursts
stay within the 16-message credit window plus the 64-envelope queue. ExUnit binds
WOP-X-F17, F20, F22, F51, F56 and F57 through the host with a process fixture
that runs the production owner and an injected service, or a deterministic
response probe. The public `Open62541` persistent client admits Read, Write and
Call from any process and keeps Browse and disconnect owner-only. A same-stack
secure peer with server Session/channel counters shows that close deletes the
server Session before its timeout and that owner death at measured fractions of
one activation releases the guardian, SDK process and channel within 1,000 ms,
with any created Session removed by cooperative close or server timeout.
Opening failures now carry the SDK connection status: user access, identity
token and user signature rejections map to `authentication_failed`; certificate,
security-check, policy and mode rejections map to `certificate_invalid`; other
statuses are `connection_failed`. The compiled same-stack C peer executes the
nine policy/token Session cells with Read, Write/readback, Call, Browse and close,
and the X-F39..F47 rejection cells. The independent async-opcua Rust peer now
executes the complete X-F30..F47 matrix. Both peers also subscribe,
receive a report and cancel the subscription: their subscription and
MonitoredItem counts after cancellation, live continuation counts and host and
native processes alive after close are all zero. Each independent X-F39..F47
attempt uses an isolated Rust peer variant, fails before Session activation,
leaves no local native process and records zero application requests in the peer.
Against that independent peer, the public subscription path also delivers the
initial and two fresh Values exactly once with sequence, client-handle,
timestamp-resolution and overflow metadata. Double cancellation is idempotent;
receiver death deletes only its subscription; and receiver-queue overflow emits
one terminal error. Peer subscription and MonitoredItem counts return to zero
and the Session remains usable after each lifecycle path. Suspending the native
SDK beyond a six-cycle lifetime also expires the independent server
subscription; resumption delivers one `subscription_lost`, both peer counters
remain zero and the Session serves a subsequent Read. An isolated `server_loss`
variant can then terminate beneath a live subscription: the receiver gets one
BadCommunicationError-backed `connection_failed`, the Session and native
helpers end without reconnect/replay, and a newly started peer serves only a
fresh explicit Session.
The same independent peer also executes scalar Double read/write through both
production Runtime profiles and Property observation through a real
ConsumedThing child. Explicit stop and Runtime-owner death each return its
subscription, MonitoredItem and additional native-process counts to zero.
It also exposes writable Int32 and Double arrays and a writable 2 × 3 Int16
matrix. Public Runtime read/write/readback preserves their type, flat values,
dimensions, extreme integers and negative zero, restores the original values
and leaves only the test's baseline Session helpers.
Normal native output now waits in the X04 64-envelope/1 MiB queue on a
nonblocking pipe and spends message/byte credit only when its first byte is
written; ready and terminal controls use the separate allowance and never split
a partially written envelope. The owner and C ingress now exchange one initial credit control before the
request. It binds the process generation; requests without it and later credit
before consumption fail. Open/read/write/call/browse/close responses spend credit; the BEAM owner
replenishes validated consumption. The read path translates one concrete input
NodeId through the server URI and SDK-local namespace map and returns a typed
DataValue, retaining a Bad result's numeric StatusCode. Decoded identity values
are projected back to server namespace indexes (below). The Write path
validates one typed Variant, holds an SDK-owned copy through the callback and
returns one numeric result status. A transmitted Write failure retains unknown
effect without retry. The Call path translates concrete object/method NodeIds,
copies up to 64 typed input Variants into SDK-owned memory, and returns the
method status, ordered input argument statuses and typed outputs. Bad method
status or uncertain post-submission failure retains unknown effect without
retry. The first service-level Browse slice requests one bounded page, copies
complete ReferenceDescriptions, and validates them at the BEAM frame boundary.
The public native client projects a complete page of local child NodeIds. An
oversized page closes the Session; child-list compatibility now follows bounded
continuations on that same Session.
The C owner now also admits an internal `allow_continuation: true` Browse shape:
it retains up to 64 server continuations in C memory, each chain with its own
cumulative bounds and a fresh local token per page,
and sends service-level BrowseNext or release on that Session. A secure
same-stack C peer forces one reference per page and exercises both wire calls.
The BEAM owner exposes a generation-bound public handle with the original
browse deadline and cumulative bounds, releases an unconsumed continuation with a
bounded control when that deadline passes and ends the generation when that
release fails. A duplicate live token from the native process ends the
generation. The independent Rust peer proves BrowseNext, release and automatic
deadline release with its server-side continuation count. Output buffering and
other lifecycle operations remain required. The owner now samples the
SDK's client-local namespace table when the Session is ready and projects every
decoded NodeId, ExpandedNodeId without a URI, encoded ExtensionObject type
identity and Browse ReferenceDescription identity from that table to the server
NamespaceArray through exact URI equality; identity-bearing Write and Call
inputs are localized the same way. Indexes outside the server table use the
SDK's reversible out-of-table rule and fail when they would collide with a local
table entry. QualifiedName is not remapped by the pinned SDK codec and passes
unchanged. A URI identity the SDK resolves locally arrives normalized to its
index, and server indexes from 65536 minus the SDK table size to 65535 cannot
be distinguished after SDK decoding. A projection failure is `invalid_response`;
it ends the Session only when a live Browse continuation would otherwise be lost.
The BEAM response frame validates only canonical local `c` plus uint64 tokens
for Browse/BrowseNext and an exact null Browse release. Its host now binds one
live token to a generation-bound reference for persistent typed Browse,
preserves the original absolute deadline and cumulative limits, and consumes
the old reference on next or release. Generic raw Browse still closes on a
returned token. Independent-peer wire pagination and the target 64 live
continuations remain unaccepted.
The child-list compatibility call now uses the same owner-bound page path to
collect at most 256 local NodeIds on one persistent or temporary Session.
Later invalid identity and Uncertain status release a live cursor; fixture
tests pass for both lifecycle modes. The secure same-stack C peer confirms
multi-page child collection over the wire in both modes. The second independent
peer (async-opcua Rust) confirms BrowseNext, release and expiry release with the
server's live continuation-point count, and that a timed-out or abandoned Call
reaches the server's Cancel service.
The native runtime uses an Elixir API and an explicitly owned open62541 C
executable. Python is confined to upstream build generators and the audit
environment; the former public Python compatibility adapter and peer have been removed.
`Native.Config.new/1` now validates the exact public native option shape without
file I/O; `open_parameters/2` snapshots explicitly named regular credential
files under one caller deadline, bounds each to 64 KiB, and projects the closed
bytes-envelope `open` map. Anonymous, binary username/password and certificate
token shapes are covered. The explicitly selected public `Open62541` client now
uses this layer to open a caller-owned persistent Session or to defer all file
and process I/O until a one-shot request. Persistent Read, Write and Call retain
typed native maps; one-shot success preserves the recorded Read envelope,
`"written"` Write acknowledgment and zero/one/many Call output shapes, including
ByteString envelopes. Bounded child Browse works in both modes. These paths pass
against the secure same-stack C peer. Complete compatibility projection, typed Browse
pagination/release, cancellation and concurrency remain open;
this does not accept P02/P03.
The same-stack peer also confirms typed ByteString array Write/readback through
the public native client, preserving binary elements. This adds no full S01/S02
or P02 acceptance claim.
The facade now preserves the native client's finite pre-I/O Write/Call rejection
codes as no-effect errors; other mutation failures retain unknown effect. This
does not yet discharge the full cancellation and effect matrix.
A native executable, a protocol service, a WoT binding and an interoperability
result are distinct deliverables. All requirements below are mandatory.

## WOP-X01 — SDK and reuse boundary

`Wotex.OPCUA.Open62541` implements the Client port. `connect/1` accepts an explicit
`executable` absolute path, its SHA-256 `executable_digest`, an absolute
`guardian` path and its SHA-256 `guardian_digest`, the endpoint and
security options from S03 (explicit keys defined below), `lifecycle: :persistent | :oneshot` (default
`:persistent`), `timeout: 1..60000` (default 5000), and
`session_timeout_ms: 1000..3600000` (default 60000). Unknown or duplicate keys fail
before process creation. These options remain consumer-owned; no application
configuration, PATH search, automatic installation or runtime download occurs.
The SDK executable is `wotex_opcua_native`; its separate custody executable is
`wotex_opcua_custody`. The package supplies both C sources, build task, protocol
schema, attribution and tests. Successful persistent connect
requires authenticated Session activation and NamespaceArray initialization.
One-shot configuration admits no network activity until a request; each request
owns a temporary native Session and retains the existing compatibility result
projection. The native typed helpers use persistent mode.

The internal `Native.Host.start_link/1` bootstrap accepts exactly the four
executable identity options above plus `timeout` (default 5000, range 1..60000).
Its caller owns the linked host; a supervising native Session starts this child
itself before waiting for protocol activation. It is a temporary child, with no
automatic restart or reconnect. The return is `{:ok, pid, %{ready: ready,
received_at_ms: integer}}` after exact process readiness, or a library Error.
Bootstrap itself does not implement `Client.connect/1` or send credentials;
its explicit internal request path can activate the currently supported Session.
An invalid or failed startup must leave its caller alive and no owned Port.
Initialization is unlinked while the caller is monitored. Only its original
caller can claim a one-use readiness token; the host establishes the link after
successful readiness and a final owner/deadline check. A failed or timed-out
claim tears down the unclaimed host. The host enforces that same deadline even
when a live caller is suspended before submitting its claim. Linking during fallible initialization is
not an equivalent caller-safe startup mechanism.
Malformed options fail before file or process I/O. File hashing, native spawn and
readiness share the API-entry deadline; owner loss remains observable during each
phase. Native paths are absolute UTF-8 strings of at most 4096 bytes without NUL.
Files are regular, executable, nonempty, at most 512 MiB and SHA-256 checked;
the consumer keeps these deployment artifacts immutable. Path-based process
spawn does not claim atomic execution of a hashed inode under adversarial file
replacement. Neither native executable is selected through PATH.

`Native.Ready.decode/1` is the pure bootstrap decoder for one LF-terminated
control frame, at most 4096 bytes including LF. It accepts only the exact five
ready fields below, without duplicate keys, embedded unescaped LF, unknown
fields, trailing data or invalid UTF-8. `clock_ms` is an integer in 0..2^63-1;
booleans and floating-point lookalikes fail. The decoder returns
`{:ok, %Native.Ready{clock_ms: integer}}` or a payload-free `invalid_native_ready`
Error. The host captures the BEAM monotonic receive time separately, before
decoding, for X03's conservative clock mapping. The 4096-byte bootstrap control
limit is separate from the 131072-byte service frame limit. A second ready or
unsolicited data after bootstrap closes this process generation with one bounded
error; native Session/credit ownership remains a separate implementation layer.
`invalid_native_configuration`, `invalid_native_executable`,
`invalid_native_ready`, `native_startup_failed`, `native_owner_lost`,
`native_process_terminated`, `invalid_native_handle`, `invalid_native_frame` and
`deadline_exceeded` are finite bootstrap Error codes. Only a native exit status
may appear in their bounded details; native output and filesystem exception text
are never exposed. The readiness corpus
[native-ready-v1.json](../../../../packages/wotex-opcua/priv/fixtures/native-ready-v1.json) contains exact byte frames;
its runner decodes `frame_base64` and compares either the complete clock value
or the exact Error code. These cases establish no service acceptance.

The Elixir configuration is a keyword list with exactly `executable`,
`executable_digest`, `guardian`, `guardian_digest`, `endpoint`, `security_policy`, `security_mode`, `client_uri`,
`server_uri`, `certificate`, `private_key`, `server_certificate`,
`trust_certificate`, `crl`, `authentication`, `lifecycle`, `timeout` and
`session_timeout_ms`. Only the last three have the defaults above. All other
keys are required. Both executable digests are lowercase 64-digit hexadecimal;
certificate/key/CRL values are explicit absolute file paths. Authentication is
`%{type: :anonymous}`, `%{type: :username, username: utf8, password: binary}` or
`%{type: :certificate, certificate: absolute_path, private_key: absolute_path}`.
Policy atoms are `:basic256sha256`, `:aes128_sha256_rsaoaep` and
`:aes256_sha256_rsapss`; their exact URI mapping is S03. Mode is
`:sign_and_encrypt`. Paths and credential file sizes are validated before spawn;
file bytes are converted to X03's closed DER/bytes IPC schema. One-shot
configuration validates names/types at connect but reads credentials and creates
its temporary native owner only when an operation uses its one deadline.
The `Native.Config` layer performs the option and bounded file projection and
is wired into the partial public native client. One same-stack Basic256Sha256
anonymous peer passes persistent and one-shot paths; the complete cross-stack token/policy
matrix and compatibility projection remain open.

The source authority is [native-sources-v1.json](../../../../packages/wotex-opcua/priv/fixtures/native-sources-v1.json).
open62541 1.5.7 is commit `d1173ccc31560ffc60c29e24ce8adb19f8c3c686`;
OpenSSL 3.5.8 is commit `f4dc4d58b48d346a8270183f89acf826d459b0ca`.
Neither a mutable branch nor a host-installed SDK satisfies the reference build.
Source archive hashes are checked before extraction; tar traversal, symlinks
outside the workspace and unexpected roots fail. Native assets have separate
source, toolchain/options and executable digests. Build identity includes any
reviewed SDK patch; patches require exact source assertions and regression tests.

The source manifest admits `open62541-secure-discovery-v2`, implemented by
`priv/native/patch-sdk.cmake`. Upstream 1.5.7 discards `revisedSessionTimeout`
after CreateSession. This patch retains that exact Double and exposes the
`0:revisedSessionTimeout` connection attribute only while the Session is active;
cleanup clears it. The patch also keeps initial discovery on a caller-pinned
SignAndEncrypt channel and rejects URL/certificate substitution and ambiguous
matching token policies before CreateSession. It does not validate the revision
or activate a native owner. The adapter still must enforce X03's finite
positive configured bound before reporting successful open. Every original and
patched file SHA-256 is fixed before any mutation. The build receipt includes
all three modified SDK files and the bounded patch log. A C-only isolated
loopback regression verifies actual revised values and cleanup using Security
None; it cannot establish any S03 secure channel claim. The upstream MPL-2.0
notices remain intact and apply to the modified SDK files.

The [Opex62541 source](https://github.com/valiot/opex62541/tree/c45cb4d532615078fd7e03039ccb8eef5e629f76)
is a reviewed reuse candidate, not an admitted runtime dependency. Its native
client callback passes only `UA_DataValue.value`; its subscription constructor
returns only the subscription ID. The WOP contract requires timestamps/status,
server-revised parameters, strict bounds and generation/deadline ownership.
Unmodified Opex62541 cannot satisfy these requirements. The fixed architecture
is a narrow first-party service adapter over open62541. Compatible Opex62541
framing/ownership code may be reused with attribution and license review only
when it meets the same tests; no implementation depends on a speculative fork.

The [native Erlang implementation](https://github.com/stritzinger/opcua) is also
source evidence, not the selected backend: its documented service matrix leaves
BrowseNext, Call and monitored/subscription services unsupported. The native
client delegates protocol cryptography to open62541/OpenSSL rather than owning
a separate BEAM secure-channel implementation.

## WOP-X02 — Reproducible build and package boundary

The declared package alias is `mix wotex.native.build --workspace ABS`.
Its implementation task is `mix wotex.opcua.native.build --workspace ABS`
(`Mix.Tasks.Wotex.Opcua.Native.Build`). Protocol archives use distinct task modules
so a consumer can compile several protocol dependencies without module conflicts.
An archive consumer invokes the qualified task or defines its own root alias.
`ABS` is one
absolute, empty disposable directory or a workspace with a matching verified
manifest. Unknown options, relative paths, a nonempty unrelated directory and
manifest/hash mismatch fail without changing that directory. No Git remote is
configured. The source archives are the literal URLs/hashes in X01's manifest.
Downloads use finite time and byte limits (120 seconds and 100 MiB per archive).
Archive reuse requires a fresh digest check. The download tool is curl 8.4.0 or
later: its [size limit](https://curl.se/docs/manpage.html#--max-filesize) also
bounds transfers whose initial size is unknown. Curl configuration and inherited
proxy/credential environment are disabled; explicit HTTPS verification remains
required. Download options use HTTPS-only redirects and no automatic retry.

OpenSSL is configured with `no-shared no-tests no-apps no-module` and an explicit
workspace prefix. The build uses the default provider compiled into libcrypto;
no ambient OpenSSL configuration, provider search path or engine is consulted
at runtime. Required cryptographic algorithms must pass native known-answer
checks. The exact Configure target follows the selected CPU/OS tuple and is
recorded. Shared host libcrypto does not satisfy the reference build.

open62541 CMake options are explicit:

```text
CMAKE_BUILD_TYPE=RelWithDebInfo
BUILD_SHARED_LIBS=OFF
UA_ENABLE_ENCRYPTION=OPENSSL
UA_ENABLE_SUBSCRIPTIONS=ON
UA_ENABLE_SUBSCRIPTIONS_EVENTS=OFF
UA_ENABLE_PUBSUB=OFF
UA_ENABLE_DISCOVERY=ON
UA_ENABLE_DISCOVERY_MULTICAST=OFF
UA_ENABLE_METHODCALLS=ON
UA_NAMESPACE_ZERO=REDUCED
UA_ENABLE_JSON_ENCODING=ON
UA_MULTITHREADING=0
UA_BUILD_EXAMPLES=OFF
UA_BUILD_UNIT_TESTS=OFF
OPENSSL_USE_STATIC_LIBS=TRUE
OPENSSL_ROOT_DIR=<workspace OpenSSL prefix>
```

The pinned SDK gates its client source files on UA_ENABLE_DISCOVERY in
[CMakeLists.txt](https://github.com/open62541/open62541/blob/d1173ccc31560ffc60c29e24ce8adb19f8c3c686/CMakeLists.txt#L944).
That build option enables client symbols; multicast remains disabled and no
automatic discovery operation is admitted. Explicit method-service support is
required for Call. The build clears ambient compiler/linker/include/pkg-config
flags and records its own flags and absolute OpenSSL include/static-library
paths. A successful SDK archive build without linkable client symbols fails
the native executable/self-test lane.

The first-party native tests have their own CMake/CTest target. Upstream SDK
unit/security tests run in a separately recorded audit build, not by silently
changing the production build. The Linux fault build instruments the shim and
SDK with `-fsanitize=address,undefined -fno-omit-frame-pointer`; the normal build
uses `-Wall -Wextra -Werror` for first-party C. Sanitizer output fails the lane.
Every tool invocation uses executable plus argument vector, never shell text.
CMake, C compiler, linker, libc, Perl, Python generator and OS/architecture
versions are mandatory manifest fields. Their executable hashes and flags bind
reuse; a changed toolchain requires a fresh build. Build prerequisites fail
explicitly when missing. Upstream Python generation is build-time only.

Required software cohorts are Linux x86_64 and aarch64, plus macOS aarch64 for
Port ownership/build compatibility. ExUnit minimum/current cohorts remain
Elixir 1.18/OTP 27 and Elixir 1.20/OTP 29 with exact patch versions recorded.
The full secure/fault/sanitizer lane runs on Linux; macOS runs native open,
read/write/subscription/cancel/EOF and package smoke tests. No hardware is needed.

The final archive includes SDK-host and runtime-guardian C sources, reviewed patches, the source manifest,
Mix tasks and protocol schemas. It excludes built executables, downloads,
credentials, PLTs and fixture state. An isolated archive consumer, with the
exact dependency archives of WOP.06 I06, builds the helper explicitly, removes
Python from the runtime PATH, and performs the native secure workflow. The test records all child executable identities and
proves no runtime Python process, shell or compiler is invoked. The SDK and
OpenSSL notices accompany the build output. No ABI-stable binary is inferred
from the Hex package version.

## WOP-X03 — Framing, typed values and exact clocks

C07 version 1 JSON lines are the only runtime IPC. They are not OPC UA's JSON
wire encoding. Both ends enforce the 131072-byte line limit including newline,
depth eight, 1024 entries per container and 4096 total nodes before materializing
untrusted structures. Integer tokens are parsed as checked signed/unsigned
integers, never through double. Finite Float/Double tokens preserve signed zero;
the serializer emits `-0.0` for negative zero. Duplicate keys, exponent overflow,
trailing JSON, unknown keys, malformed UTF-8/base64 and incomplete EOF fail closed.
C parsing has bounded tokens/stack and no input-proportional unchecked VLA.
The pinned parser, strict flags, exact integer conversion and fixed allocation
pools are defined in the [native JSON codec contract](../../../../packages/wotex-opcua/priv/native/json-codec.md).
Its source and MIT notice identities are part of the native source manifest.
Parser syntax acceptance alone does not admit an operation or allocate SDK values.

Ready is exactly `{version: 1, event: "ready", backend: "open62541",
revision: "d1173ccc31560ffc60c29e24ce8adb19f8c3c686", clock_ms: native_monotonic_ms}`.
The caller verifies both executable digests before spawning the guardian and
verifies the SDK revision before network admission. The guardian forwards the SDK
stream and owns the SDK process group under WOP-X07. `clock_ms` is an integer in 0..2^63-1. Generation is a BEAM-owner allocated integer in 1..2^64-1,
constant for that native process. IPC IDs are nonempty ASCII strings of at most
64 bytes, unique within that generation. Generation/ID never derives from a TD.
Only one ready frame is valid. Unsolicited responses and duplicate IDs are fatal.

The owner captures its monotonic receive time `r` for ready sample `n`. For an
owner deadline `d`, the native admission deadline is `n + (d - r)` milliseconds.
The request carries that value as top-level `deadline_ms`, a required JSON
integer in 0..2^63-1 on the native monotonic clock. Missing, fractional, negative
or overflowing values fail `invalid_request` in phase validation with effect
none and no I/O. The owner rejects an already elapsed deadline or conversion
overflow before emission. `timeout_ms` is a required integer in 1..60000; it is
an additional cap starting at native receipt, never a new budget at dequeue.
Admission uses the earlier deadline and rejects native clock >= deadline with
`deadline_exceeded`, phase admission, effect none. X-F17 checks equality.
This conservative same-host monotonic mapping includes ready-delivery delay;
it does not extend the owner deadline. Native `timeout_ms` is additionally
bounded by the remaining owner budget. Equality is expired. Clock-rate and
rounding tests cover both supported OS clocks. Clock samples never cross a
machine boundary. Queue time, native startup, security, services and decoding
share the original deadline; no hop restarts it. Cleanup uses C03's separate
grace. Native admission checks deadline and input-pipe EOF immediately before
emitting a service request. An Elixir result received after `d` is rejected.

Operations and parameter maps are closed:

| Operation | Parameters | Result |
| --- | --- | --- |
| open | endpoint, security policy/mode, application and user credential configuration, session_timeout_ms | session_timeout_ms, namespace_array, session_generation; no opaque SDK handles |
| read / health | node_id, index_range (null only) | full S01 DataValue |
| write | node_id, index_range (null only), value (typed Variant) | `{status: uint32}`; exactly one result |
| call | object_id, method_id, arguments (0..64 typed Variants) | `{status, input_argument_statuses, outputs}` in server order |
| browse | node_id and N03 options | `{status, references, continuation}`; continuation is a local opaque token or null |
| browse_next / browse_release | continuation local token | N03 page / null after successful release |
| subscribe | node_id and S04 parameters except BEAM receiver/queue pid | local subscription token, numeric UA IDs, all revised parameters and item status |
| unsubscribe | local subscription token | null after deletion acknowledgment |
| cancel | target_id | `{target_id, canceled: Boolean}`; true retires unfinished local delivery/admission, never physical rollback |
| close | empty map | null only after native cleanup |

The `open` parameter map contains exactly `endpoint`, `security_policy`,
`security_mode`, `client_uri`, `server_uri`, `certificate`, `private_key`,
`server_certificate`, `trust_certificate`, `crl`, `authentication` and
`session_timeout_ms`. Endpoint/ApplicationUri strings are nonempty UTF-8, at most
4096 bytes. Policy is one of S03's three exact URI strings; mode is the literal
`"SignAndEncrypt"`. Certificate/key/trust/CRL values are C07 bytes envelopes,
not paths; their aggregate encoded size must fit the IPC limit. The Elixir owner
reads only explicitly supplied absolute files within the original deadline,
rejects changed digest/oversize input, and never exposes their contents in
Inspect, errors or telemetry. Each credential input is at most 64 KiB; a valid
set exceeding the aggregate frame limit returns `:request_too_large` before
spawn. The direct issuer trust profile has exactly one trust certificate and
one current issuer CRL; intermediate chains are outside S03's accepted scope.

Authentication is exactly `{"type":"anonymous"}`,
`{"type":"username","username":utf8,"password":bytes_envelope}`, or
`{"type":"certificate","certificate":bytes_envelope,"private_key":bytes_envelope}`.
Username is nonempty and at most 1024 bytes; password is at most 4096 bytes.
Empty password is distinct from absent. Keys are unencrypted PKCS#8 DER; encrypted
key containers and interactive passphrase callbacks are unsupported. Certificates
and CRLs are DER. Missing/unknown keys and duplicate selected token policies fail
before application service I/O. `open` returns exactly `session_timeout_ms`
(finite positive server-revised number within the accepted configured bound),
`namespace_array` (X04) and `session_generation` (the matching IPC generation).
A server-revised Session timeout above the configured bound fails and closes
that Session; the caller never assumes the requested timeout was accepted.

Native tokens are generation-scoped ASCII strings, at most 64 bytes. Server
continuation bytes remain private C-owned bounded memory. The owner validates
all NodeIds and typed values again at native ingress; a forged BEAM struct or
handcrafted IPC cannot bypass the contract. Success envelopes have only C07
fields. Error maps contain exactly `code`, `phase`, `effect`, and optional uint32
`status`. Code/phase/effect use finite string tables, not native exception text.
Required code classes include invalid_request/invalid_value, invalid_response, unsupported_type,
unsupported_protocol, backend_mismatch, busy, deadline_exceeded,
authentication_failed, certificate_invalid, connection_failed, remote_error,
response_mismatch, response_limit, sequence_gap, subscription_lost,
receiver_overflow and cleanup_failed. Phase is validation, opening, admission,
exchange, decode or cleanup. Effect is none or unknown; an uncertain transmitted
Write/Call has unknown effect. Elixir constructs Error.class/retryable using I04,
never a peer-supplied arbitrary class. Every unknown native code is a protocol
failure. Credential/endpoint/key/certificate bytes never appear in failures.

## WOP-X04 — Native service ownership

One native process owns one `UA_Client` and one Session. It admits at most 64
application operations, 32 subscriptions and 64 continuations. A separate two-slot
control reserve admits cancel/close while application capacity is full. At most
64 IPC output envelopes and 1 MiB aggregate encoded output await delivery;
exceeding either bound terminates the association with bounded cleanup. Native
SDK message/chunk limits are 1 MiB and 16; application value limits remain S01.
The SDK host never forks descendants. Its separate runtime guardian forks
exactly one SDK child and retains process-group custody under WOP-X07. Stderr is
separate from protocol stdout; any SDK stderr bytes are contained as a fixed
guardian failure. Raw SDK logging is disabled.

IPC uses explicit credit flow control, independent of mailbox sampling. After
ready, normal responses/reports consume both message and encoded-byte credits.
The owner grants at most 16 messages and 262144 bytes with a control envelope
`{version: 1, generation, event: "credit", sequence, messages, bytes}`. Sequence
is uint64, starts at one and increases by exactly one; wrap or replay terminates
the generation. Both credit quantities are positive integers. Grants replenish
only bytes/messages already consumed and validated by the owner; outstanding
credits cannot exceed those maxima. The native owner rejects duplicate/overflowing
credit grants. Credit envelopes require no response. Initial credit is explicit;
transmitting normal output with zero credit is a protocol failure; generated
output waits only in the bounded native queue. Ready and one terminal
failure may use a separate aggregate 4096-byte control allowance per generation.
The terminal control is exactly `{version: 1, generation, event: "terminal",
error: {code, phase, effect}}`, with optional uint32 `error.status`. It has no
request ID and uses null generation only before the first valid generation-bearing
input. Once a generation is admitted it must match. Only one terminal control
is permitted; no normal output follows it. An unexpected/duplicate terminal or
generation mismatch is a local protocol failure. Native death without this frame
still fails all unfinished work. Association failure gives unfinished reads
effect none and potentially transmitted mutations effect unknown; a global
terminal frame cannot assert rollback for an individual write. Locally queued
work never emitted to the native process retains effect none.

A suspended BEAM owner therefore receives at most the credited output plus that
finite control allowance. Native notification buffering remains at most 64
messages/1 MiB; excess causes receiver_overflow and cleanup, never an unbounded
stdout write. Stdout is nonblocking, partial writes retain only the bounded
buffer, and a blocked pipe cannot stop EOF/cancel/deadline processing. After
forwarding a report, the relay also enforces the final receiver's C05 queue bound;
it cannot replenish native credits merely because an unbounded intermediary
accepted a send. Tests suspend the owning BEAM process while a software peer
produces continuous reports, assert credit and buffer ceilings, then prove
cleanup. Counts/RSS are observed independently of Process.info queue sampling.

The process event loop polls stdin and iterates SDK work with at most 10 ms
blocking slices. Network work uses typed asynchronous service APIs; blocking
synchronous Cancel is not allowed on the owner loop. Callback context binds
SDK requestId, expected response type, generation and IPC ID. `noReconnect` and
`noNewSession` are true. Channel renewal is SDK-owned; Session loss terminates
the generation. Each application request has exactly one final success/failure response.
Cancellation produces a separate acknowledgment for its control request and one
`canceled` failure for an unfinished target; completed targets return
`{target_id, canceled: false}` without changing the delivered result. Native
`canceled` is a finite error code with the target operation's original effect.
Completion and cancellation cannot race into two replies for that target.
Cancel disables local delivery immediately, cancels queued work without I/O,
and issues bounded asynchronous protocol Cancel for transmitted services where
applicable. Unknown remote effect survives all cancellation outcomes. Callback
storage remains alive until SDK completion or client deletion; it is never
freed while the SDK can still reference it.

EOF, invalid framing, owner death and deadline initiate cleanup. Partial open
tracks acquisitions in order: process, SDK client, socket/channel, Session,
namespace map, operation/subscription/continuation. Cleanup deletes owned server
resources, closes Session with deletion enabled, closes channel/socket, clears
all UA allocations, then exits. At most the first 500 ms of the one absolute
1000 ms grace is available for cooperative SDK cleanup. Failure or expiry closes
the guardian Port; its independently executing teardown has the reserved 500 ms.
Owner EOF begins guardian teardown immediately. No second 1000 ms grace or BEAM
`kill(os_pid)` fallback is allowed. A paused peer cannot extend the deadline.
Local process exit is not proof of instantaneous remote deletion: server state
is verified against revised Session timeout when explicit cleanup cannot reach
the server. Reports distinguish local release from remote expiry evidence.

Concrete NodeId namespace indexes in the public API identify the current
server NamespaceArray. open62541 1.5 has a distinct client-local namespace map.
The adapter resolves server index -> URI -> SDK-local index on input and the
inverse on output, including NodeId-valued Variants, references and QualifiedName.
URI input resolves exactly once against that activated Session; missing or
ambiguous entries fail. NamespaceArray has at most 1024 unique nonempty UTF-8
URIs of at most 4096 bytes and aggregate 128 KiB. Ns0 is the standard URI. No
server/local index equality is assumed, and local mapping changes never alter
consumer-visible identity. SDK custom-type loading is disabled; unsupported
ExtensionObjects retain their explicit encoded body rather than dynamic classes.

## WOP-X05 — Publish, revisions and cancellation

The native owner issues raw CreateSubscription, CreateMonitoredItems, Publish,
Republish, DeleteMonitoredItems and DeleteSubscriptions through SDK service
codecs. It does not use a convenience callback that exposes only UA_Variant. High-level
SDK subscription registration and automatic Publish management remain disabled
for these raw-service subscriptions; two Publish engines must not compete.
CreateSubscription retains revised publishing interval, lifetime and keepalive;
CreateMonitoredItems retains revised sampling interval, queue size and item
status. The returned handle is valid only after both service/item checks pass.
All integer revisions satisfy S04 limits; finite noninteger interval revisions
are preserved without rounding and must remain within the accepted interval
range. An invalid revision causes server cleanup, not silent clamping.

At most four Publish requests are outstanding per Session while subscriptions
exist. The native owner maps each complete notification to its known numeric
subscription/item identity. It retains DataValue value-presence, StatusCode,
both exact timestamps, picoseconds, sequence and overflow bit. S04's 1024-entry
sequence/digest cache and 100-message Republish gap bound apply per subscription.
Notification digest covers the full normalized ordered notification payload;
keepalive messages do not enter this cache or advance the last delivered
notification sequence. Acknowledgments name only validated notifications.
Duplicate notifications can be acknowledged without repeated delivery. Fresh
equal values remain deliverable. Server acknowledgment statuses are validated.
A subscription's failed gap recovery terminates that subscription; a Session-wide
security/correlation fault terminates the entire Session.

Native receiver death cancels only its subscription. A failed server delete
requires closing the shared Session and reporting loss to its other dependants;
that explicit failure policy is distinct from stopping a borrowed consumer
process. Runtime's final supplied subscription-owner pid owns partial startup,
not the temporary callback worker. Successful handoff survives worker exit;
final-owner death during open cannot leave an admitted native request behind.
Public tests cover both native consumers and real Runtime supervision.

`publish_sequence.c` implements the per-subscription sequence state used by
this owner: 1..2^32-1 with wrap to one, a 1,024-entry sequence/digest cache,
duplicate acknowledgement without delivery, conflicting duplicates, ordered
Republish recovery of at most 100 missing messages and terminal larger gaps,
unavailable or mismatched Republish results and unverifiable older sequences.
WOP-X-F24 through F26 execute through that state.

`session_subscription.c` connects that state to raw SDK services. `subscribe`
validates the closed S04 map, reserves a never-reused serial that is also the
MonitoredItem client handle, sends CreateSubscription with at most 64
notifications per Publish and then CreateMonitoredItems for the Value attribute
with both timestamps. Only a Good item status and a revision inside the S04
ranges (lifetime at least three keepalives) returns the local token `s<serial>`,
the server subscription and item IDs, the client handle, all revised values and
the item status; otherwise the server subscription is deleted. While
subscriptions exist, the Session sends at most one outstanding Publish per
active subscription and four in total, and only when both its ready-report queue
and the owner's output queue are empty. Each Publish carries acknowledgements
for notifications already validated and queued. Publish acknowledgement statuses
other than Good, BadSequenceNumberUnknown and BadSubscriptionIdInvalid are a
Session-wide `invalid_response`. Keepalives refresh activity without consuming
a sequence. Notifications must be decoded DataChangeNotifications for the
subscription's client handle; a StatusChangeNotification is `subscription_lost`
with its status. The digest is SHA-256 over the binary notification payloads.
Gaps are recovered with one Republish at a time, holding at most four later
messages. A subscription whose activity exceeds its revised publishing interval
times lifetime count is `subscription_lost`. Each accepted MonitoredItem value
becomes one `data` report with the projected DataValue and metadata `sequence`,
`publish_time`, `client_handle`, `overflow` (DataValue info bits),
`datetime_resolution_ns: 100` and `raw_datetime_ticks_available: true`.
A terminal subscription failure emits exactly one `error` report with a finite
code, drops that subscription's unemitted reports and sends best-effort
deletion. `unsubscribe` marks the subscription closing so no later report is
delivered, sends DeleteMonitoredItems then DeleteSubscriptions and returns null
only when both results are Good; any other result ends the generation with
`cleanup_failed`. A retired CreateSubscription or delete whose result was not
confirmed also ends the generation because server state could be unowned.
The owner emits reports after operation replies in each tick and flushes each
credited envelope before producing the next, so a suspended owner receives its
credited reports plus at most 64 queued envelopes before `receiver_overflow`.

`Native.Host` validates each subscribe result as exactly the ten documented keys,
with a token matching its client handle, nonzero identities, a non-Bad item
status and S04 revision ranges. It then monitors the receiver and returns an
opaque generation-bound handle. A report line is admitted only for a live or
closing token of the current generation and must be exactly a `data` report with
a valid DataValue and six-key metadata or an `error` report with an empty metadata
map; a malformed report or an unknown token ends the generation with
`invalid_native_frame`. Before each delivery the host checks the receiver's
message queue against `max_queue_length`; overflow delivers one
`receiver_overflow`. Overflow or receiver death sends one native `unsubscribe`
control and removes the handle after its null result; an `error` report removes
the handle at once. A subscribe response that arrives after its caller stopped waiting is
cancelled at once; reports for that token are discarded. Concurrent cancellation
of one handle waits for the single native `unsubscribe`. Closed references are
kept in a bounded 1,024-entry set so repeated cancellation returns `:ok`; a
stopped owner returns `:ok` without I/O. Session or owner loss sends one terminal
error to each live receiver.

## WOP-X06 — Executable acceptance and evidence

[native-contract-v1.json](../../../../packages/wotex-opcua/priv/fixtures/native-contract-v1.json) fixes independent
inputs and exact observations. Its status is partially_bound: WOP-X-F01 through
WOP-X-F16 execute through the production bounded JSON parser, SDK value codec
and pure namespace translator in `wotex_opcua_native_contract_check`. The runner
does not create a Client or Session and records zero service requests. Remaining
cases must be bound to the actual IPC parser/owner/SDK adapter, or an explicitly
labelled injected service boundary, before acceptance. The asserting runner owns
the expectation. Pure framing cases run every split and coalescing of the given line;
semantic cases serialize through the production encoder, never a fixture echo.
The separate initial P02 input tests exercise the real executable's strict
line parser, closed outer request keys, expired-deadline rejection and one
generation-matched initial credit, terminal-only owner exchange and the `open` parameter
shape. They do not bind any additional `native-contract-v1.json` case, validate
service parameters or credentials cryptographically, activate a Session or send
a service request.
Native traces use a deterministic service/clock boundary; peer lanes separately
prove real bytes, certificates and callbacks. The Session adapter additionally
accepts explicitly labelled SDK send hooks (`WopSessionSdk`), NULL in
production, so a trace can record the exact Browse, BrowseNext and cancellation
requests it builds and answer them from a script without a socket. The full S/N/I scenario matrices
remain required in addition to the concrete corpus.

Required fixture tasks are `mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS --core-archive ABS --runtime-archive ABS`,
whose two archives are the exact `wotex` and `wotex_runtime` packages of WOP.06
I06. They use X02's workspace admission and
manifest rules. Build includes the production helper, the compiled C secure
fixture peer and the second independent peer of WOP.04. Python packages are
used only by the hash-pinned audit environment; the peer is a content-bound
native artifact. Run selects
`mix test --include interop --include software --exclude hardware`, CTest,
ASan/UBSan and dependency audits. `WOTEX_REQUIRE_SOFTWARE=1` makes missing tools,
configuration, responses and cleanup evidence failures, never skips. The audits
are the Mix dependency and Hex audits, `pip-audit` from a hash-pinned
installation over `test/interop/audit-requirements.lock`, and a native audit whose
inputs include SDK/OpenSSL source and shim/patch hashes, not just Mix.lock. Each
audit is a recorded lane whose failure fails the run. The Rust peer lock also
runs through `cargo audit`; its sole exception is RUSTSEC-2023-0071 under the
advisory's local-only workaround because the disposable fixture binds only
loopback. Any other RustSec vulnerability fails the lane.
`Wotex.OPCUA.Native.Software` implements both tasks
(`mix wotex.opcua.software.build` and `mix wotex.opcua.software.run`, with the
package aliases above) for a source checkout. Build runs the native workspace
build and its CTest step, including `wotex_opcua_secure_peer`, builds a Debug
ASan/UBSan tree from that workspace's prefixes, and installs
`test/interop/audit-requirements.lock` (pip-audit and its dependencies) into a
separate audit environment with `--require-hashes --no-deps`. It builds the
second independent peer from `test/interop/rust_peer` on the async-opcua 0.19.0
Rust stack. Cargo fetches the exact lock into the workspace, then performs an
offline release build with warnings denied. The two patched upstream crates are
vendored, and the manifest records every project and patch digest, the Cargo
version, the audit lock and installed audit distributions, and seven executable
digests. Run re-verifies that manifest and the peer project. It starts the C
peer and then the Rust peer, which reuses the C peer's CA, CRL and server certificate,
serves a folder of 40 children, scalar/method nodes and three writable array
nodes on all three required
SignAndEncrypt policies with anonymous, username and certificate tokens,
reports the server's live browse continuation points, Cancel count,
subscriptions and MonitoredItems through methods, and stops when its standard
input closes. The run exposes the content-bound Rust executable only to the
interop process so X-F39..F47 can start isolated named variants. Those variants
select the fault leaf, Security None-only endpoint or anonymous-only tokens as
required and persist their accepted application-request count during graceful
shutdown. Each peer has a
finite readiness deadline. The run then executes the ExUnit lane with
`WOTEX_REQUIRE_SOFTWARE=1`, native and sanitizer CTest, the Mix dependency and
Hex audits, `cargo audit` over the Rust lock,
`pip-audit --require-hashes --disable-pip` over the audit lock, and
the native source audit. The native source audit requires the checkout's
`priv/fixtures/native-sources-v1.json` to be the manifest compiled into the
build, asks the OSV database for advisories whose affected git ranges contain
the pinned open62541, OpenSSL and vendored yyjson commits, and records those
sources, the SDK patch digests and every advisory identifier in
`native-audit.json`; any advisory fails its lane. OSV matches only advisories
that record git ranges. The `archive_consumer` lane is X-F48: it builds this
package's archive with `mix hex.build` under Hex requirements, unpacks it with
the two named archives, and writes a consumer project whose only first-party
dependencies are the three unpacked archives. The consumer fetches its Hex
dependencies, builds the helper with the dependency's own
`wotex.opcua.native.build` task and runs its test with a `PATH` of the Elixir
and Erlang directories and a directory of links to a few POSIX utilities, from
which no Python is reachable. The test loads every package from the consumer's build, opens a
secure Session to the running peer, reads, writes, subscribes and receives the
written value, cancels and closes, finds no Python or shell process among its
descendants while the Session runs and no helper process after it closes, and
prints its observation. The lane compares that observation with the X-F48
corpus expectation and records the archive, corpus and consumer lock digests in
`archive-consumer.json`. The run stops both peers and records each lane's
status and log digest; any failed lane fails the task.

The driver owns disposable ports, processes, keys and state; readiness has a
finite deadline and every exit closes only manifest-owned resources. Evidence
records source and archive identity, SDK/compiler/runtime versions, fixture and
binary SHA-256, flags, actual commands/exit statuses, malformed failure samples,
and local/remote cleanup counters. S/V/N/I/X case identifiers have asserting
bindings and current corpus digests. C09 requires 1000 sequential operations,
32 concurrent callers, 100 open/close cycles and 100 receiver-death cycles with
forced deadlines, peer loss, malformed replies and bounded RSS/heap accounting.
Software completion requires all rows on their required cohorts, the unpacked
archive consumer and Python-free runtime execution. No device or certification
result is inferred.

## WOP-X07 — Independent runtime process custody

The [native runtime guardian contract](../../../../packages/wotex-opcua/priv/native/runtime-guardian.md)
is normative for this profile. It defines separate executable identities,
opaque bidirectional forwarding, exact buffer/argument limits, process-group
identity retention, status mapping and WOP-G01..G10 acceptance. Those scenarios
require executable bindings before acceptance. The runtime guardian is distinct
from the build-command guardian and cannot use its `/dev/null` child input mode.

Both executables are consumer-owned deployment inputs. An external executable
is not admitted merely because it prints the right readiness revision. Digest
verification precedes spawn; readiness, secure Session activation and per-service
validation remain separate gates. Guardian exit fails unfinished operations;
mutation effect remains unknown whenever service emission may have occurred.
Guardian cleanup proves local process release only. Remote Session/subscription
cleanup retains the separate acknowledgment or revised-expiry evidence in X04.

`bin/check_native_custody.exs` executes both Linux sanitizer lanes from the
default gate. It compiles the checked-in guardian and independent driver with
`-fsanitize=address,undefined`, verifies the exact fixture projection for every
WOP-G01 through WOP-G09 execution, and treats any sanitizer diagnostic, leak,
status mismatch, count mismatch or deadline excess as failure. The macOS gate
executes the same portable cases through native CTest without claiming a Linux
sanitizer result.
