# Native source boundary

`main.c` is the first-party open62541 executable source. Its dependency self-test
checks the pinned OpenSSL SHA-256 implementation and the SDK's one-tick DateTime
binary conversion without a network request. `--self-test` is an explicit build
check, not an OPC UA service or interoperability result. Executable ready is a
process protocol event; successful Session activation requires the complete
native service owner.
`patch-sdk.cmake` checks original and modified file SHA-256 before applying the
reviewed Session revision and secure discovery patch to the isolated SDK source. The patch preserves
upstream MPL-2.0 notices. `sdk_revision_check.c` opens three loopback-only SDK
Sessions to verify the actual server revision, fractional milliseconds, copy
lifetime and cleanup. Its Security None endpoint is a test fixture only; the
production executable now opens and closes one pinned secure Session and reads
one Value attribute asynchronously; the other services remain unimplemented.
`session_config.c` configures only the requested secure policy and user token,
installs the exact peer verifier and rejects interactive private-key prompts.
The uninstalled `session_probe.c` exercises that configuration against an
independent asyncua secure peer, including its revised timeout and explicit
NamespaceArray. The production owner independently exercises open/read/close
through the same SDK configuration.
`security.c` adds explicit credential preflight before any network attempt.
It owns bounded DER/PKCS#8 inputs, validates key pairs, direct-CA trust,
certificate identities/usages/validity and the issuer CRL, and provides a
complete-DER peer-pin verifier. `security_check.c` generates disposable C-only
credentials and tests valid, invalid and boundary cases. See [security.md](security.md)
for the exact boundary and remaining SDK/Session work.

`ipc.c` assembles input lines within the 131072-byte ceiling and checks the
closed outer request envelope after `json_codec.c` parses the complete line.
The executable rejects malformed or expired input with one terminal frame,
admits secure `open`, one-at-a-time `read`, and `close`, and rejects other service
requests as `unsupported_protocol`. A read accepts a concrete NodeId and null
index range, resolves the server URI to the SDK-local namespace index, and
serializes a bounded DataValue. NodeId-bearing result values remain unsupported
until inverse namespace translation is implemented. Bad StatusCodes return a
finite `remote_error` with the numeric status. `ipc_check.c` covers
every split of a request line, coalescing, bounds and malformed envelopes;
the pinned build test also exercises the real process input and terminal output.
The `open` parameter map is now checked for its exact keys, policy/mode literals,
bounded identity strings, canonical base64 envelopes, user-token form and
session timeout. This shape gate precedes the `security.c` credential checks;
Session activation uses `session_open.c` after this shape gate.
`ipc.c` also validates a closed initial credit frame. `main.c` binds it to the
process generation and requires it before a request. Terminal output uses its
control allowance; open/read/close responses spend credit and the BEAM owner
replenishes validated consumption. Queued notifications are not implemented.

`build_command.c` is the reviewed POSIX command guardian from the Wotex Modbus
source at commit `018f419b0644cfecc83891551d10b5c8d771d7c6`,
`test/interop/native/command.c`. It is Apache-2.0 source and retains its original
notice. It belongs to explicit build tooling, independently of the production
OPC UA service process.

The guardian takes separate arguments:

```text
command TIMEOUT_MS OUTPUT_BYTES CLEANUP_MS ABSOLUTE_CWD ABSOLUTE_EXECUTABLE ARG...
```

Its stdin is an owner-liveness pipe. The child has `/dev/null` stdin, bounded
combined stdout/stderr and its own process group. Owner EOF, signals, timeout,
output overflow and blocked forwarding initiate group TERM/KILL cleanup. The
direct child remains unreaped until cleanup to reserve its process-group identity.
A successful command exit also closes remaining group members.

Limits are 1–600000 ms command time, 1–16777216 output bytes, 1–5000 ms cleanup,
and a separate 65536-byte forwarding buffer. Child statuses 0–123 are preserved;
124 is deadline, 125 output limit, 126 setup/unexpected owner input, 127 owner/
signal/output receiver loss, 128 child termination, and 129 incomplete cleanup.
This boundary covers ordinary tools remaining in the owned process group. It is
not a sandbox for descendants that deliberately escape with setsid/setpgid.
The explicit trusted compiler bootstrap precedes guardian availability; its
failure cannot imply verified whole-process-tree cleanup.

The CMake build consumes already verified static open62541/OpenSSL prefixes. It
never downloads SDKs or selects an ambient shared OpenSSL installation. Source,
compiler/options and resulting executable hashes remain separate build identities.

`custody.c` supplies the separate production bidirectional process guardian.
Its [runtime contract](runtime-guardian.md) defines exact CLI values, bounded
queues, independent owner-loss cleanup and output-drain semantics. The build
installs `wotex_opcua_custody` alongside `wotex_opcua_native`; both hashes belong
to the completion receipt. The SDK process's frame and credit protocol remains
responsible for bounded notification delivery to BEAM.

`custody_check.c` is a packaged build-time fault driver, excluded from installed
executables. CTest runs its WOP-G01..G09 cases against actual pipes and processes.
It deliberately stops SDK workers, suspends output consumption, checks binary
transfers and audits direct-child reaping. Linux builds with
`WOTEX_SANITIZERS=ON` run both strict ASan/UBSan timing tests and the separately
labeled LeakSanitizer tests described in the runtime contract. A successful
custody test is independent of OPC UA Session or interoperability acceptance.

`json_codec.c` applies the [strict native JSON contract](json-codec.md) to the
unmodified, MIT-licensed yyjson source under `vendor/yyjson`. A fixed allocator
pool, decoded-key duplicate validation and finite structural limits precede SDK
value construction. Explicit signed/unsigned conversion preserves all 64 bits;
floating conversion preserves negative zero and rejects overflow. The build
checks the vendor source and license digests before compiling and installs the
license beside its native artifacts. `json_check.c` supplies parser and numeric
projections for executable corpus checks. It is not installed as a runtime
program. Typed SDK value conversion exists separately; complete service
serialization and admission remain required implementation.

`native_contract_check.c` binds the first sixteen native contract vectors to
the typed codec, strict parser and pure NamespaceArray translation helper. It is
a build-time test driver and is not installed. These cases perform no protocol
service or network operation; the persistent owner must exercise the overlapping
parser and namespace cells again in WOP-P02.

The build supplies explicit static OpenSSL paths and disables pkg-config
executable discovery through an empty, typed CMake cache entry. FindPkgConfig's
command definitions remain available to CMake versions whose FindOpenSSL module
calls them unconditionally. The recipe clears pkg-config executable, search-path,
system-root and library-directory environment inputs before every command.
