# Native containment executable

Decision date: 2026-09-08. Status: accepted. Owners: WLB.06 and WLB.08.

Replace the Python resource supervisor with an external Rust executable, not
a NIF. Elixir continues to own admission, explicit process composition and
public evidence. This follows the ecosystem's use of native code behind
Elixir APIs without confusing an in-VM numerical backend with an OS isolation
boundary. The earlier claim that keeping Python was necessary is withdrawn.

[MuonTrap](https://github.com/fhunleth/muontrap) is the established Elixir
reference for supervised external programs and Linux cgroup-v2 lifecycle and
resource control. Its documentation explicitly separates that from network/
filesystem sandboxing and points to Bubblewrap. It remains a suitable Linux
host integration, not a drop-in implementation of Lab's current Darwin
resource/protocol contract. An [Elixir Forum process-lifecycle discussion](https://elixirforum.com/t/getting-zombies-with-erlexec/63818)
also illustrates why an ordinary Port is not a complete descendant supervisor.
These sources inform the ownership boundary, not a claim of community consensus
for this particular helper.

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

The replacement preserves inherited CPU/open-file/output/core limits, a private
run directory, bounded output, wall timeout and sampled process-tree RSS/count
accounting on macOS and Linux. Cleanup now runs on successful target exits too.
The root remains unreaped until group cleanup completes (`waitid`/`WNOWAIT`),
preventing reuse of its group-leader PID. Observed detached descendants retain
start identities; stale PIDs are not blindly signalled. Accounting and retained
identities have explicit ceilings, and observation/cleanup failure cannot be
reported as a successful target response.
Transient root-accounting gaps during `exec` get two one-millisecond retries,
not an unbounded grace period or an invented zero-usage sample. A 30-launch
BEAM regression reproduced the original failure and passed 300 launches after
the correction; deterministic native tests cover retry exhaustion too.

This review also narrows earlier overclaims. Polling is not a kernel memory or
PID controller: peaks between samples and an unobserved daemonization race are
not proven contained. Darwin's `sandbox-exec` is deprecated; changing languages
does not resolve that platform lifecycle. The current filesystem policy limits
writes but is not a hostile-code read-isolation boundary. Therefore WLB.06's
whole-tree hostile-target obligation is not closed by this cohort; its catalogue
status is partial. Untrusted hosted submissions require a separately admitted
kernel-isolated worker/VM profile, not this reviewed-local-target profile.
The requirement is retained, not waived or presented as completed.

The source cohort exercises both core corpora through the actual Darwin
sandbox and Rust helper, malformed/oversized/crashed targets, resource failures,
concurrent outputs and cleanup. Native lifecycle tests separately exercise
normal exit, observed session escape and termination signals on macOS and Linux.
Linux native tests do not prove Bubblewrap integration or cgroup enforcement.
