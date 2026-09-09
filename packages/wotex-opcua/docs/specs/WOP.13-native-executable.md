---
spec:
  id: WOP.13
  title: "Native OPC UA executable and software acceptance"
  status: accepted
  version: 1.0.1
  owner: wotex-opcua
  updated: 2026-09-09
---

# WOP.13 Native OPC UA executable and software acceptance

This accepted target is **planned implementation**. WOP.02 describes the current
code. Runtime uses an Elixir API and an explicitly owned open62541 C executable.
Python is confined to the independent test peer and upstream build generators.
A native executable, a protocol service, a WoT binding and an interoperability
result are distinct deliverables. All requirements below are mandatory.

## WOP-X01 — SDK and reuse boundary

`Wotex.OPCUA.Open62541` implements the Client port. `connect/1` accepts an explicit
`executable` absolute path, its SHA-256 `executable_digest`, the endpoint and
security options from S03 (explicit keys defined below), `lifecycle: :persistent | :oneshot` (default
`:persistent`), `timeout: 1..60000` (default 5000), and
`session_timeout_ms: 1000..3600000` (default 60000). Unknown or duplicate keys fail
before process creation. These options remain consumer-owned; no application
configuration, PATH search, automatic installation or runtime download occurs.
The executable is `wotex_opcua_native`; the package supplies its C source, build
task, protocol schema, attribution and tests. Successful persistent connect
requires authenticated Session activation and NamespaceArray initialization.
One-shot configuration admits no network activity until a request; each request
owns a temporary native Session and retains the existing compatibility result
projection. The native typed helpers use persistent mode.

The Elixir configuration is a keyword list with exactly `executable`,
`executable_digest`, `endpoint`, `security_policy`, `security_mode`, `client_uri`,
`server_uri`, `certificate`, `private_key`, `server_certificate`,
`trust_certificate`, `crl`, `authentication`, `lifecycle`, `timeout` and
`session_timeout_ms`. Only the last three have the defaults above. All other
keys are required. Executable digest is lowercase 64-digit hexadecimal;
certificate/key/CRL values are explicit absolute file paths. Authentication is
`%{type: :anonymous}`, `%{type: :username, username: utf8, password: binary}` or
`%{type: :certificate, certificate: absolute_path, private_key: absolute_path}`.
Policy atoms are `:basic256sha256`, `:aes128_sha256_rsaoaep` and
`:aes256_sha256_rsapss`; their exact URI mapping is S03. Mode is
`:sign_and_encrypt`. Paths and credential file sizes are validated before spawn;
file bytes are converted to X03's closed DER/bytes IPC schema. One-shot
configuration validates names/types at connect but reads credentials and creates
its temporary native owner only when an operation uses its one deadline.

The source authority is [native-sources-v1.json](fixtures/native-sources-v1.json).
open62541 1.5.7 is commit `d1173ccc31560ffc60c29e24ce8adb19f8c3c686`;
OpenSSL 3.5.8 is commit `f4dc4d58b48d346a8270183f89acf826d459b0ca`.
Neither a mutable branch nor a host-installed SDK satisfies the reference build.
Source archive hashes are checked before extraction; tar traversal, symlinks
outside the workspace and unexpected roots fail. Native assets have separate
source, toolchain/options and executable digests. Build identity includes any
reviewed SDK patch; patches require exact source assertions and regression tests.

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

The declared root-project alias is `mix wotex.native.build --workspace ABS`.
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
Archive reuse requires a fresh digest check.

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

The final archive includes C sources, reviewed patches, the source manifest,
Mix tasks and protocol schemas. It excludes built executables, downloads,
credentials, PLTs and fixture state. An isolated archive consumer builds the
helper explicitly, removes Python from the runtime PATH, and performs the
native secure workflow. The test records all child executable identities and
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

Ready is exactly `{version: 1, event: "ready", backend: "open62541",
revision: "d1173ccc31560ffc60c29e24ce8adb19f8c3c686", clock_ms: native_monotonic_ms}`.
The caller verifies the executable digest before spawn and the revision before
network admission. `clock_ms` is an integer in 0..2^63-1. Generation is a BEAM-owner allocated integer in 1..2^64-1,
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
No native process forks descendants. Stderr is separate from protocol stdout and
contains only library-owned diagnostic codes; raw SDK logging is disabled.

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
all UA allocations, then exits. No acknowledgment within the one 1000 ms grace
causes owner termination of its executable. A paused peer cannot extend grace.
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

## WOP-X06 — Executable acceptance and evidence

[native-contract-v1.json](fixtures/native-contract-v1.json) fixes independent
inputs and exact observations. Its status is specified_unexecuted. Each case is
bound to the actual IPC parser/owner/SDK adapter, or an explicitly labelled
injected service boundary, before acceptance. The asserting runner owns the
expectation. Pure framing cases run every split and coalescing of the given line;
semantic cases serialize through the production encoder, never a fixture echo.
Native traces use a deterministic service/clock boundary; peer lanes separately
prove real bytes, certificates and callbacks. The full S/N/I scenario matrices
remain required in addition to the concrete corpus.

Required fixture tasks are `mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS`. They use X02's workspace admission and
manifest rules. Build includes the production helper, the independent asyncua
peer and same-stack C precision/fault peer. Python packages are pinned from the
fixture lock with downloaded wheel/sdist hashes recorded and checked; the test
peer environment is not a runtime package asset. Run selects
`mix test --include interop --include software --exclude hardware`, CTest,
ASan/UBSan and dependency audits. `WOTEX_REQUIRE_SOFTWARE=1` makes missing tools,
configuration, responses and cleanup evidence failures, never skips. Native
audit inputs include SDK/OpenSSL source and shim/patch hashes, not just Mix.lock.

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
