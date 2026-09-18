# Native runtime custody contract

This is the required runtime guardian contract. Its implementation and fault
cases are separate from the tooling-only `build_command.c` boundary, which sends
`/dev/null` to the child and cannot carry a native session protocol.

The portable guardian owns one explicitly selected SDK child in one process
group. It forwards opaque bytes in both directions without adding, parsing or
rewriting SDK protocol frames. SDK callbacks and the BEAM protocol owner retain
responsibility for request correlation, frame limits and message/byte credits.
Finite guardian buffers alone do not bound a suspended BEAM owner's mailbox:
Erlang's Port driver can still deliver stdout to that mailbox. The SDK must debit
its accepted credits before emitting bytes, including bytes in guardian/kernel
transit. A guardian cannot turn an uncredited producer into an accepted profile.

## Executables and arguments

Both the guardian and SDK executable have explicitly supplied absolute paths
and SHA-256 identities. The caller verifies both before spawn. The SDK executable
and arguments are separate values; no shell or PATH lookup selects the child.
The guardian executes:

```text
guardian CLEANUP_MS INPUT_BYTES OUTPUT_BYTES ABS_CWD ABS_EXEC [ARG...]
```

`CLEANUP_MS` is a decimal integer in 1..1000. Each byte capacity is a decimal
integer in 1..262144. Paths are nonempty absolute strings of at most 4096 bytes.
At most 256 child arguments are accepted, each at most 8192 bytes and at most
65536 bytes in aggregate. Invalid input returns status 126 without a child.
Native credentials, endpoint configuration and user values travel only through
the SDK protocol; they are not guardian arguments. The explicit caller supplies
a cleared environment with only its reviewed SDK execution values.

The BLE profile fixes input capacity 131072, output capacity 65536 and
`CLEANUP_MS=500`. Its normal SDK close/delete work uses at most the first 500 ms
of one absolute 1000 ms cleanup deadline. The owner closes the guardian Port
when that first portion expires or fails; it does not wait 1000 ms and then start
a fresh guardian grace. Owner death closes the pipe immediately and therefore
does not require a responsive BEAM callback to begin guardian cleanup. A caller
using another cleanup allowance must reserve that allowance in its existing
deadline. Repeated EOF, signals or failed writes never move a started deadline.

## Startup ownership barrier

Before fork, the guardian restores the default SIGCHLD disposition and clears
its signal mask. The direct child waits on a private CLOEXEC pipe. Only the
parent establishes the child's process group and releases one byte after
checking that identity. The child verifies the byte and its own group before
changing directory, duplicating SDK descriptors or executing the SDK. A failed
admission closes the barrier and kills/reaps only the unreleased direct child
within the supplied cleanup budget. Clock or reaping failure is status 129.
No group signal targets a group that admission did not establish. The startup
barrier does not change buffer capacities or extend the caller's cleanup grace.

## Pipe and process ownership

The guardian creates separate SDK stdin, stdout and stderr pipes. Each guardian
pipe end is nonblocking; child ends retain the SDK's chosen I/O policy. Only the
intended standard descriptors reach exec. Before making pipes, the guardian
enumerates actual open descriptors using `/proc/self/fd` on Linux or `/dev/fd`
on macOS, marks each unintended descriptor close-on-exec and closes it. An
unavailable descriptor inventory fails before fork; a lowered descriptor limit
cannot hide an inherited high descriptor. Every subsequently created pipe is
close-on-exec, with only its intended standard-descriptor duplicates retained.
The SDK runs in a process group whose
ID is its direct child PID. Parent and child establish the group. The parent
retains the direct child with `waitid(..., WNOWAIT)` until final teardown, so it
cannot signal a recycled process-group identity. Only CLD_EXITED, CLD_KILLED
and CLD_DUMPED establish exit: a platform returning CLD_STOPPED despite WEXITED
does not authorize reap or successful completion.

Input and output queues have the exact configured capacities. Reads never exceed
remaining capacity and partial writes retain only their unsent bytes. Full
queues pause the corresponding reads while all other pipe directions, child
exit, owner EOF and cleanup timers remain observable. In particular, owner stdin
remains in the liveness probe even when the SDK input queue is full; HUP/ERR triggers
cleanup without waiting to drain buffered requests. Poll waits are at most 10 ms.
On macOS, `poll` omits HUP when the requested event mask is zero. A separate
non-consuming, zero-wait liveness probe requests POLLIN/POLLOUT on the owner
pipes on every loop, while the blocking poll omits a full input queue. Its
10 ms maximum wait bounds EOF observation without spinning on queued requests.
One producer cannot starve the opposite direction or lifecycle checks.

Owner stdin EOF/HUP/ERR, output receiver loss, SIGTERM/SIGINT/SIGHUP, SDK stderr
output, unrecoverable pipe errors, SDK stdout EOF, or SDK exit begins teardown. Pending input is
discarded and the SDK input writer closes before further forwarding. The SDK
receives up to 25 ms, bounded by one quarter of its guardian allowance, to react
to EOF. The guardian then sends group SIGTERM, sends group SIGKILL by the midpoint
of the allowance if needed, observes child exit and reaps its direct child by
the original deadline. A stopped or blocked SDK cannot postpone these actions.
Successful SDK exit also closes remaining ordinary members of its group.

At normal SDK exit, both the existing output queue and all remaining child
stdout bytes are drained in order through EOF while the receiver remains
writable and within the same teardown deadline. Direct-child exit and complete
required stream delivery are checked separately. Undelivered
output cannot be reported as a successful complete byte stream. Owner loss
requires no output delivery. SDK stderr is never merged into protocol stdout or
copied into diagnostics; any bytes produce a fixed guardian failure and cleanup.
The guardian emits no stdout banner, error JSON, child PID or unsolicited frame.

The SDK host in this BLE profile does not fork. The portable custody boundary
covers its direct child and ordinary descendants that remain in that process
group. It does not claim containment of deliberate `setsid`/`setpgid` escapes,
reaping of another parent's children, or successful termination of uninterruptible
kernel state. Linux subreaper profiles have a distinct, stronger contract.
Status 129 reports an unobserved direct exit or incomplete required stream
cleanup; sending a signal alone never establishes direct-child release.

## Status and acceptance

Child statuses 0..123 are retained after verified direct-child teardown and
required output delivery. Status 126 is setup/argument failure, including failure
to execute the selected child. Status 127 is owner, signal or output-receiver
loss. Status 128 is child signal termination or a reserved child exit status.
Status 129 is unverified cleanup or undelivered required output. Status 131 is
contained SDK stderr output. Status values cannot be treated as an SDK success
response, rollback or evidence of remote resource deletion.

Required executable cases are:

| Case | Exact observation |
| --- | --- |
| WBL-G01 | Invalid limit/path/argument cases create no child; setup failure returns 126. |
| WBL-G02 | Fragmented UTF-8, NUL and all-byte payloads survive in both directions byte-for-byte. |
| WBL-G03 | Simultaneous input/output beyond either queue capacity completes in order under a reading consumer. |
| WBL-G04 | A full SDK input queue cannot hide owner EOF; a stopped/TERM-resistant SDK is reaped within its allowance. |
| WBL-G05 | A blocked stdout consumer causes finite buffering; owner EOF still ends the SDK within its allowance. |
| WBL-G06 | Output HUP/EPIPE and SDK stderr cause fixed failures without leaking bytes into protocol stdout. |
| WBL-G07 | SDK exit with a final payload larger than OUTPUT_BYTES drains its complete stream through EOF to a slow reader; a blocked reader returns 129; the direct child is reaped and owned background group members terminate. |
| WBL-G08 | Two guardians remain isolated: ending one does not signal or close the other. |
| WBL-G09 | Repeated stop events and a partly spent caller cleanup budget cannot restart or extend teardown. |
| WBL-G10 | Linux/macOS native fault builds pass; Linux ASan/UBSan output or leaked direct children fail acceptance. |

Tests record configured capacities, exact sent/received byte counts, direct child
exit/reap status and elapsed cleanup time. Standalone native tests suspend pipe
consumption independently of the BEAM Port driver. BEAM suspended-owner tests
also exercise the SDK's actual credit protocol; they cannot claim a mailbox bound
from this transparent relay alone.

The Linux audit has three distinct lanes: ordinary compilation; ASan/UBSan with
exit-time leak scanning disabled for the strict production timing measurement;
and ASan/UBSan with LeakSanitizer enabled. The first two require both SDK reap and
guardian exit within 500 ms. The LeakSanitizer lane still requires SDK exit/reap
within 500 ms, but gives the instrumented guardian's post-main leak scan a named
1000 ms harness-only allowance. It reports actual guardian exit and post-reap
durations separately. This allowance does not apply to a production executable,
does not extend SDK resource ownership and does not satisfy the ordinary timing
lane. LeakSanitizer remains enabled for the required leak audit.

The Linux test driver is an independent child subreaper: an SDK orphaned by the
guardian would become its child and fails the direct-reap assertion. The driver
checks ESRCH and ECHILD while retaining its guardian child identity, so recording
SDK reap does not mean merely sending SIGKILL or observing a missing PID. The
guardian itself has no subreaper guarantee. `custody_check` accepts an explicit
`--leak-audit` final argument only in this separately labeled instrumentation
lane; its normal invocation has no additional exit allowance.

## Source identity

The runtime implementation is the shared Wotex guardian introduced as
`packages/wotex-opcua/priv/native/custody.c` at commit
`64a05c16f63792671343f94f89af5b7ab6b321b5` (`ca2c4afc2fe8d4afa42b7621363c567da89ce288`
in the former per-package history), source SHA-256
`d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2`.
Its Apache-2.0 attribution is retained. The BLE fault driver uses package-specific
case identifiers for the same pipe-level assertions. Source equivalence does not
establish execution evidence for a BLE SDK host or its credit protocol.
