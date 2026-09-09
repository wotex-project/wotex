# Native source boundary

`main.c` is the first-party open62541 executable source. Its dependency self-test
checks the pinned OpenSSL SHA-256 implementation and the SDK's one-tick DateTime
binary conversion without a network request. `--self-test` is an explicit build
check, not an OPC UA service or interoperability result. Executable ready is a
process protocol event; successful Session activation requires the complete
native service owner.

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
