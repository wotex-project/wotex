# Native containment executable

Decision date: 2026-09-08. Status: accepted. Owners: WLB.06 and WLB.08.

An external Rust executable owns native process accounting and termination.
Elixir owns admission, explicit process composition and public evidence. The
helper communicates through an Erlang Port and runs outside the VM. Its runtime
and lifecycle probes require no Python interpreter.

[MuonTrap](https://github.com/fhunleth/muontrap) is the established Elixir
reference for supervised external programs and Linux cgroup-v2 lifecycle and
resource control. Its documentation explicitly separates that from network/
filesystem sandboxing and points to Bubblewrap. It remains a suitable Linux
host integration, not a drop-in implementation of Lab's current Darwin
resource/protocol contract. A Port owns its immediate external process;
descendant accounting and termination remain explicit helper responsibilities.

`priv/conformance/native/` contains the small Rust 2021 executable, Cargo lock,
unit tests and explicitly feature-gated test targets. Production dependencies
contain only `libc` 0.2.189 (MIT/Apache-2.0); serde_json and its closure belong
only to the `test-probes` feature. Native calls use public libc/libproc APIs;
the helper runs outside the BEAM. Its pre-exec callback uses only scalar
resource limits and async-signal-safe calls, respecting Rust's
[CommandExt contract](https://doc.rust-lang.org/std/os/unix/process/trait.CommandExt.html#tymethod.pre_exec).

Provisioning is an operator build step, never an application callback or
first-tensor requirement. The caller supplies an absolute executable and its
reviewed SHA-256. Admission rejects symlinks, missing/non-executable/oversized
files and mismatched digests before running a target. Binary provenance and
signing/distribution remain per-platform WLB.08 obligations; a source build
is not a published precompiled artifact.

The helper enforces inherited CPU/open-file/output/core limits, a private
run directory, bounded output, wall timeout and sampled process-tree RSS/count
accounting on macOS and Linux. Cleanup runs on successful and failed target exits.
The root remains unreaped until group cleanup completes (`waitid`/`WNOWAIT`),
preventing reuse of its group-leader PID. Observed detached descendants retain
start identities; stale PIDs are not blindly signalled. Accounting and retained
identities have explicit ceilings, and observation/cleanup failure cannot be
reported as a successful target response.
Containment profile 2.0.1 reserves one second between the launcher's inner wall
deadline and the outer runner deadline. The helper's 150 ms cleanup ceiling sits
inside that margin, leaving the remainder for sandbox and launcher startup,
scheduler delay and delivery of the port exit status. Deadlines of one second or
less reduce the target wall allowance to one millisecond and report the exact
effective margin; they are prompt-refusal budgets, not useful target-work
budgets. The helper executable is version 2.0.0; the Elixir profile derives and
reports the effective deadline.

Transient root-accounting gaps during `exec` get two one-millisecond retries,
and report unavailable accounting after retry exhaustion. The 30-launch BEAM
regression passed 300 launches in the recorded cohort; deterministic native
tests cover retry exhaustion.

Polling is not a kernel memory or
PID controller: peaks between samples and an unobserved daemonization race are
not proven contained. Darwin's `sandbox-exec` is deprecated. The filesystem policy limits
writes but is not a hostile-code read-isolation boundary. Therefore WLB.06's
whole-tree hostile-target obligation is not closed by this cohort; its catalogue
status is partial. Untrusted hosted submissions require a separately admitted
kernel-isolated worker/VM profile, not this reviewed-local-target profile.
The kernel-isolated profile remains an accepted implementation requirement.

The source cohort exercises both core corpora through the actual Darwin
sandbox and Rust helper, malformed/oversized/crashed targets, resource failures,
concurrent outputs and cleanup. Native lifecycle tests separately exercise
normal exit, observed session escape and termination signals on macOS and Linux.
Linux native tests do not prove Bubblewrap integration or cgroup enforcement.
