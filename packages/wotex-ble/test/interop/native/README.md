# Native fixture command ownership

`command.c` is the first-party POSIX C11 command guardian shared with Wotex
Modbus at source commit `018f419`. It executes explicit argument vectors for
native component tests. It is test tooling, not a BLE transport or SDK.

```text
command TIMEOUT_MS OUTPUT_BYTES CLEANUP_MS ABSOLUTE_CWD ABSOLUTE_EXECUTABLE ARG...
```

Stdin is an owner-liveness pipe. The direct child has `/dev/null` stdin and a
separate process group. Combined stdout/stderr has a finite aggregate limit and
a 64 KiB forwarding buffer. Owner EOF, timeout, output overflow, TERM, INT and
HUP trigger TERM/KILL cleanup of that exact process group. The direct child stays
unreaped until cleanup to reserve its group identity. Successful root exit also
cleans background members. Descendants that deliberately escape through
`setsid` or `setpgid` are outside this ownership model.

Limits are 1–600,000 ms command time, 1–16,777,216 output bytes and 1–5,000 ms
cleanup. Child statuses 0–123 are retained. Guardian statuses are 124 (deadline),
125 (output limit), 126 (setup or unexpected stdin data), 127 (owner/signal/output
receiver loss), 128 (other child termination) and 129 (incomplete cleanup).

`native_bus_test.exs` compiles and runs `test/native/bus_test.cpp` through the
guardian. The fixture starts its own private daemon and verifies libdbus 1.16.2
connection ownership. It does not touch a system/session bus or require BlueZ.
The explicitly selected fixture requires absolute `WOTEX_BLE_DBUS_SOURCE` and
`WOTEX_BLE_DBUS_BUILD` directories from the pinned libdbus source/build. Missing
inputs fail the selected test. Invoke `mix test --only interop
test/interop/native_bus_test.exs`. This component lane does not establish native
GATT, the complete Port helper, or the planned Mix SDK build task.
