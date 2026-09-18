# Native process custody

This source implements the opaque process-custody primitive. The lifecycle
worker and BEAM owner now use its fixed same-binary entry under WCO-N02. The
executable contract requires a fixed `--custody ABS_DIRECTORY` entry and an
internal `--worker` entry. The BEAM owner supplies an absolute executable
path whose bytes match the native manifest. Custody executes that same path with
only `--worker`; it never selects a second executable, consults PATH, or sends
credentials through arguments. Loading the Elixir dependency starts neither mode.

One guardian holds an unreaped direct worker PID while signalling its ordinary
process group. The parent establishes that group before releasing a one-byte
startup barrier. The child verifies the group before inspecting its working
directory or executing the worker. An unsuccessful barrier uses only the
unreleased direct PID and bounded reap polling; no unestablished group receives
a signal. Ignored SIGCHLD, child auto-reaping and inherited blocked signals are
cleared before fork. The lifecycle worker owns the durable store. Its pending
exchange package will own the libcoap context/session; the custody primitive
invokes neither API.
The guardian owns two fixed 262144-byte byte queues and separate nonblocking
pipes. It inspects owner liveness even when either queue is full; stdout has no
banner and remains an opaque protocol stream. Worker stderr terminates custody
with finite status 131 and is never copied into a library error.

The guardian cleanup deadline is 500 ms from owner loss, child exit, child stdout
EOF, or a containment failure. Termination and forced kill share this one
absolute deadline. The BEAM owner's complete C03 shutdown budget remains 1000 ms
including its graceful phase and observation of native exit; the two phases do
not receive separate 1000-ms grace periods. Normal worker exit drains remaining
stdout to EOF within the same native deadline. Incomplete cleanup reports
status 129; it cannot be labelled successful.

Queue capacity alone does not bound an Erlang Port mailbox. The worker's
cumulative report-credit protocol supplies that bound across its own queue,
these pipes/queues and the Port. Cancel/close control reservations are separate
from report credit. No whole-VM crash, detached `setsid` descendant, kernel-stuck
process or inaccessible external service cleanup guarantee is inferred from
ordinary process-group ownership.

`custody.c` derives from `packages/wotex-opcua/priv/native/custody.c` at
commit `64a05c16f63792671343f94f89af5b7ab6b321b5`, source SHA-256
`ba2e2cc2ef7d32ed5e9691fce34a58f1f04e8605b73f3257caee31d619c71e41`.
Its group-identity retention derives from
`packages/wotex-modbus/test/interop/native/command.c` at commit
`c0780c9f753a626f4c88a0a6b61ce782f59637e6`. The first-party Apache-2.0 notice is
retained. The adaptation renames its C entry point for fixed same-binary dispatch
and requires a parent-owned startup barrier. The native test entry exposes the
generic primitive solely to the pipe-level fault driver; it is not a production
backend executable. Evidence from other packages does not accept this package's
exchange worker. The local lifecycle tests accept same-binary BEAM ownership and
durable open/close, while actual CoAP traffic, saturation and exchange deadlines
remain required.

`priv/fixtures/custody-v1.json` binds eleven exact pipe-level cases to
`test/native/oscore_custody_test.c`. They cover byte-preserving duplex transfer,
full input/output pipes, stopped workers, owner EOF/TERM, stderr failure, final
output drain, failed drain, descriptor closure, unrelated group preservation and
200 short child launches with alternating inherited signal state. The test
producer is an actual independent process. It is not a protocol peer. Cleanup
assertions use the fixed 500-ms native deadline without sanitizer allowances;
`Dockerfile.custody` runs the same code with ASan/UBSan. A separate leak-audit
lane enables leak detection and names its additional 1000-ms guardian-exit
instrumentation allowance; direct SDK reap still requires 500 ms. Leak-audit
results do not accept the production guardian-exit deadline.

The startup driver separately executes 1000 short children and 32 forced parent
admission failures. Test-only `-Dsetpgid=wco_fault_setpgid` linkage denies the
parent's group operation while preserving the child's system call, so the old
uncoordinated design executes the probe and fails the expected no-output check.
The production primitive contains no fault override. The leak-audit driver's
aggregate fixture allowance is 300 seconds for 200 independent process-exit
scans, 200 launches times the 500-ms reap deadline plus the named 1000-ms
instrumentation allowance; its per-child cleanup assertions retain the limits above.
