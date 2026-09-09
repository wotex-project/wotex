# Fixture command ownership

`command.c` is a first-party POSIX process guardian for explicit software build
and test commands. It is test/build tooling; the Modbus runtime remains BEAM TCP.
It takes separate arguments:

```text
command TIMEOUT_MS OUTPUT_BYTES CLEANUP_MS ABSOLUTE_CWD ABSOLUTE_EXECUTABLE ARG...
```

The caller owns stdin as a liveness pipe and sends no data. The child receives
`/dev/null` stdin, combined stdout/stderr capture and a separate process group.
The guardian handles stdin EOF, TERM/INT/HUP, timeout, output overflow and blocked
stdout while retaining an unreaped direct child to prevent group-ID reuse during
cleanup. A successful root exit also terminates background group members. The
cleanup argument bounds TERM then KILL escalation. Output is capped at the
specified aggregate byte count, with a separate 64 KiB forwarding buffer.

Limits are 1–600,000 ms command time, 1–16,777,216 combined output bytes and
1–5,000 ms cleanup. Child statuses 0–123 are retained. Guardian statuses are
124 (deadline), 125 (output limit), 126 (setup or unexpected owner input),
127 (owner/signal/output receiver loss), 128 (other child termination), and
129 (incomplete cleanup). The exec setup path also uses status 126.
A failure must remain a failed task result even when cleanup succeeds.

This is process-group ownership for ordinary fixture tools, not containment of
adversarial descendants that escape using `setsid` or `setpgid`. Native peer
containers have separate exact-container ownership. No host PID/name scan is
used by this helper. All supported execution platforms require a POSIX C11
compiler during explicit helper build and native fixture unit tests. No native
SDK or protocol peer is built by the ordinary unit suite.

`probe.c` generates real output, exit, timeout and process-group faults.
`check.c` runs seven standalone cases for native sanitizer execution.
`test/software/command_test.exs` additionally checks actual BEAM-owner death,
suspended output consumers, exact descendant termination and malformed input.
These assertions cover the command guardian; the Mix build/run tasks and full
P06 acceptance remain separate until their tests execute.

`command --lock ABSOLUTE_LOCK_FILE` obtains a nonblocking POSIX advisory write
lock and emits `wotex_fixture_lock` followed by newline. Owner EOF, process exit
or termination releases the kernel lock. Status 130 means an existing live
lease; status 126 rejects malformed paths, symlinks, nonempty files or files
with group/other permissions. The mode-0600 empty sidecar file remains reusable;
its existence alone never means a live lease. The lock inode is not unlinked
during release, which prevents concurrent callers from locking different inodes.
The explicit one-byte `R` command closes the descriptor before emitting
`wotex_fixture_unlocked` followed by newline and exiting zero. The Mix caller
waits for this acknowledgment and exit before reporting normal task completion.
