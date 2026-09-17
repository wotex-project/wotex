# Native fixture command ownership

`priv/bluez/native/build_command.c` is the first-party POSIX C11 command
guardian shared with Wotex Modbus at source commit `018f419`. It executes
explicit argument vectors for the native build task and native component tests.
It is build and test tooling, not a BLE transport, runtime guardian or SDK.
The files in this directory are its fault-injection and signal-state probes.

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
`WOTEX_BLE_DBUS_BUILD` directories from the pinned libdbus source/build. A
`mix wotex.native.build` workspace supplies them as
`sources/libdbus/dbus-1.16.2` and `build/libdbus`. Missing inputs fail the
selected test. Invoke `mix test --only interop test/interop/native_bus_test.exs`.
This component lane does not establish native GATT.

`native_host_test.exs` requires an absolute `WOTEX_BLE_NATIVE_WORKSPACE`
containing a completed native build manifest. It admits the built host and
runtime guardian through their manifest digests and drives the actual process
pair with the production guardian arguments. It needs no D-Bus daemon.

`WOTEX_BLE_NATIVE_LANE` selects the WBL-G10 lane for component executables
compiled by `native_frame_test.exs`, `native_credit_test.exs`,
`native_bytes_test.exs`, `native_output_test.exs`, `native_pages_test.exs`,
`native_reports_test.exs`, `native_custody_test.exs`,
`native_guardian_startup_test.exs`, `native_command_test.exs` and
`native_bus_test.exs`. Unset is the ordinary lane. `sanitizers` adds
`-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined
-fno-sanitize-recover=all` and runs with exit-time leak scanning disabled for
the strict timing lane. `leak_audit` is Linux-only, enables LeakSanitizer and
passes `--leak-audit` to the custody driver and the private-bus fixture for their
named post-main allowances.
Sanitizer lanes scale harness waits by 8 or 20; library deadlines and the
custody assertions are unchanged. Executed fixtures receive a cleared
environment, so on macOS the lanes pass the harness-resolved `atos` as
`ASAN_SYMBOLIZER_PATH`; the guardian under test in `native_command_test.exs` is
compiled in the selected lane by a separate bootstrap guardian. The leak-audit lane runs the 1,000-launch
guardian startup case and the 1,000 sequential command case with 32 launches
because every instrumented exit is leak-scanned, and grants the failed command
admission bound the same named 1,000 ms instrumentation allowance as the custody
cases; the ordinary and sanitizer lanes run all 1,000 without it. Sanitizer output changes a compared result or
exit status and therefore fails the test.

