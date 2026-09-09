---
spec:
  id: WCO.13
  title: "Native OSCORE owner, builds and software evidence"
  status: accepted
  version: 1.2.0
  owner: wotex-coap
  updated: 2026-09-09
---

# WCO.13 Native OSCORE owner, builds and software evidence

UDP exchanges remain BEAM code; DTLS remains OTP `:ssl`. OSCORE uses one
explicitly selected C executable through an Erlang Port and the pinned libcoap
exchange engine. Mix owns build/test orchestration and ExUnit owns assertions.
Python is not a runtime or target orchestration dependency. The OSCORE helper
and Mix tasks are planned contracts; [provenance](../provenance/executable-evidence.md)
identifies executed BEAM/OTP and native peer evidence separately.

## WCO-N01 — Reproducible native builds

The native source is libcoap 4.3.5 at commit
`7cf7465b784baded4de183290c547d582becfd28`, archive SHA-256
`d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd`, from
`https://codeload.github.com/obgm/libcoap/tar.gz/7cf7465b784baded4de183290c547d582becfd28`.
The [public 4.3.5 OSCORE API](https://libcoap.net/doc/reference/4.3.5/man_coap_oscore.html)
owns configuration, exchange context and sender-sequence callbacks. No private
SDK layout or Python bridge is part of the interface.

Apply the ordered patches and verify their resulting source hashes from
[`native/oscore/source.json`](../../native/oscore/source.json). The sequence
patch requires a successful persistence callback before advancing the cached
boundary or encrypting a PDU. The CBOR patch avoids a null-pointer copy for a
valid empty byte string. The native manifest records base archive, patches and
resulting source hashes separately; it cannot describe this build as unmodified
upstream. `test/native/oscore_sequence_test.c` asserts the actual public send
path on macOS and under Linux ASan/UBSan. Its narrow
[receipt](../provenance/native-sequence-v1.json) does not accept the remaining
native owner or durable store.

The native JSON dependency is unmodified yyjson 0.12.0, commit
`8b4a38dc994a110abaec8a400615567bd996105f`. Its
[pin and MIT notice](../../native/oscore/vendor/yyjson/source.json) identify the
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
matching manifest. Reject symlink roots, unrelated contents, archive traversal
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

## WCO-N02 — Persistent Port ownership

The planned additive `native_backend:` connection/Transport option is exactly
`%{executable: absolute_binary_path, manifest: absolute_binary_path}`. Each path
is nonempty, NUL-free and at most 4,096 bytes; the manifest is at most 1 MiB.
Require it for `Security.mode == :oscore`, reject it for UDP/DTLS modes, and
reject duplicate/unknown keys before process creation. Runtime transport config
carries this non-secret selection; credentials never carry executable paths.
Validation checks an ordinary executable file and the exact manifest/binary
hash, without changing permissions or discovering a helper from PATH. No
application environment fallback exists. The native owner preserves the existing
opaque session/Subscription API and .11 helper signatures.

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
| observe | `path`, `confirmable`, `observation_kind` (`property` or `event`), optional `accept`; GET with Observe=0 |
| credit | `generation`, `ack_seq` (unsigned 64-bit cumulative report-frame acknowledgment); fixed eight-frame window |
| cancel | `subscription_id`, `generation`; original route/token only |
| close | empty object |

Paths and content-format numbers obey .10/.11. Body chunks decode to at most
32,768 bytes; offsets must exactly equal the next expected offset. Only one
unfinished inbound body and one unfinished outbound body exist at a time.
`body_end` verifies declared length/hash; a body is consumed once by the next
associated operation or freed at deadline/close. Uploading a body sends no CoAP
traffic. Empty payload and absent payload remain distinct input choices.

Responses and stream reports use the same `body_begin`/`body_chunk`/`body_end`
events on stdout, with `id` naming their originating call or subscription and
`generation` for subscriptions. The begin event carries `body_id`, `length`
and `sha256`; chunk carries `body_id`, `offset`, `data`; end carries `body_id`.
The final success/report envelope references `body_id` and carries the validated
CoAP code/options/metadata. No partial chunk reaches the public API. A mismatched
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
these primitives; base64/body and complete helper fault tests remain separate
acceptance obligations.

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
is 15 seconds, suite timeout 300 seconds, log bound 16 MiB per stream and total
harness cleanup five seconds. These harness limits do not extend C03 library
deadlines. EOF, owner death and test failure stop only manifest-owned processes.

`result.json`, schema `wotex.coap.software@1`, records subject/dependency/fixture/
native hashes, exact commands, seed, toolchain, native features, all scenario
IDs, exit codes, outcomes, log hashes and final process/socket/session/context/
subscription/store-lock counts. Failure evidence is retained; secrets and
machine-specific source paths are excluded from publishable records.
UDP and DTLS peers are independent-stack; OSCORE libcoap peers are same-stack;
fault peers and contract injections are labelled separately.

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
committed-source/package gates. Earlier Python-run results validate their
recorded cohort only; Mix tasks and OSCORE retain planned status until these
assertions execute. Hardware and publication are separate.

The [native corpus](fixtures/native-v1.json) contains exact decoder/body/control
inputs and deterministic lifecycle traces. It is specified and unexecuted. The
ExUnit runner expands `repeat_ascii` to its declared byte count, adds the
matching generation/id envelope to body events, and compares actual native
outcomes with `expected`. For the credit traces, `grant_report_credit` means the first `ack_seq: 0`
command opening the fixed window; further steps supply cumulative `ack_seq`
and distinct C07 request IDs. Each report fits one frame and
the test owns a writable drained control channel while the BEAM owner is
suspended; the ninth report occupies the single pending Event slot and the
tenth triggers terminal loss. No production adapter receives expected values.
These representative cases supplement, rather than replace, the N05 matrix.
