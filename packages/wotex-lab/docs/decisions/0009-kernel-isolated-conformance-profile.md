# Kernel-isolated conformance profile

Decision date: 2026-09-17. Status: accepted. Owners: WLB.06 and WLB.08. This
decision closes the kernel-isolated worker requirement left open by
[ADR 0006](0006-native-containment-executable.md); the reviewed-local Rust
profile remains unchanged.

## Context

ADR 0006 records why the sampled Rust helper cannot contain a hostile target:
polling misses peaks between samples and fast daemonization, and the Darwin
sandbox does not isolate reads. Those limits need enforcement below the target
process: a kernel memory and process controller, a private network and PID
namespace, and a filesystem view that contains only what the run needs.

Linux namespaces and cgroup v2 provide those controls. An OCI container runtime
exposes them through a stable command line on Linux hosts and, through a Linux
virtual machine, on macOS. [MuonTrap](https://github.com/fhunleth/muontrap)
covers cgroup lifecycle for supervised programs but not network or filesystem
isolation. Bubblewrap covers namespaces but not memory or process limits.
Firecracker or gVisor would strengthen the kernel boundary further, but each
adds an operator stack that the Lab cannot provision from a Mix project.

## Decision

`Wotex.Lab.Conformance.KernelContainment` profile 1.0.0 runs an untrusted target
with an operator-provisioned OCI runtime command line and a digest-pinned image.
The runtime file is admitted by SHA-256 after symbolic-link resolution. The
image is never pulled. Every run uses:

- no network (`--network=none`, loopback only);
- a read-only root filesystem and one bounded `tmpfs` at `/tmp`;
- read-only bind mounts of the subject archive and listed code directories only;
- user `65534:65534`, no capabilities and no privilege escalation;
- hard cgroup memory (swap disabled) and process-count limits, a CPU quota and
  CPU-time, open-file, file-size and core resource limits;
- `/usr/bin/timeout --signal=KILL` as PID 1, with an inner deadline three
  seconds before the runner deadline.

When PID 1 exits, the kernel kills every remaining process in the PID
namespace, so detached descendants cannot outlive the run. Each target map
carries a random container label; `residue/3` counts and `release/3`
force-removes any container that still carries it.

The Lab lane pins `hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da`
(Debian 12, Erlang/OTP 29, ERTS 17.0.4) and mounts the compiled code read-only
at its host path. BEAM targets use `+JMsingle true`, because the default
dual-mapped JIT sizes a memory file beyond the file-size limit, and one normal,
dirty and asynchronous scheduler thread each, because threads count toward the
process limit.

## Consequences

The container lane (`WOTEX_LAB_CONTAINER=1`) runs both core corpora through this
profile and executes hostile network, host-read, write, privilege, memory,
process-count, detached-descendant, deadline and concurrency cases.
Evidence names the runtime version, kernel release and image digest.

The runtime daemon, its kernel and the pinned image are trusted infrastructure.
Kernel or runtime escape, side channels and denial of service against the shared
kernel are outside this profile. On macOS the kernel belongs to the runtime's
virtual machine, which separates the target from the host kernel but not from
other containers on that machine. A hosted deployment still owns runtime
hardening, image provenance and worker lifecycle under WLB.08; this source
profile does not admit hosted submissions by itself.
