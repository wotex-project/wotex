# Wotex BLE qualification runbook

This runbook qualifies a completed BLE source revision on operating systems,
architectures and devices that are not part of implementation. It does not
define public behavior and does not decide `implementation_status` in the
specification catalogue.

## Boundary

Implementation consists of the Elixir, C and C++ contracts, build and fixture
tasks, bounded ownership behavior, and executable tests owned by WBL.01–WBL.07.
Qualification establishes claims for a particular architecture, compiler,
sanitizer, guest, package archive or physical controller.

An unavailable runner leaves its claim unqualified. It does not turn
implemented source back into planned source. A skipped required case is never a
pass.

## Inputs

Qualify one clean commit. Record the commit, package path, lockfile digest,
BlueZ and libdbus pins, source and binary digests, compiler and linker
identities, operating system, architecture, BEAM versions, command lines, case
counts and result-artifact digests. Use a new absolute disposable workspace for
every native or software build.

Transient logs and receipts belong under `docs/tasks/local/wotex-ble/`. A
reviewed reproducible result may be added to `provenance/`; an older result is
never relabelled for changed source.

## Linux x86_64 matrix

The reference matrix uses Linux x86_64, Debian 12, GCC/G++ 12.2.0, CMake
3.25.1 and Ninja 1.11.1. Record native execution and binary translation as
different lanes.

For Elixir 1.18.4/OTP 27.3.4.15 and Elixir 1.20.2/OTP 29.0.4:

1. Run `mix wotex.native.build --package wotex-ble --workspace ABS`.
2. Run the ordinary native component, private-bus host and custody tests.
3. Run the ASan/UBSan and LeakSanitizer component lanes.
4. Run `mix pkg wotex-ble wotex.software.build --workspace ABS` with x86_64
   images and guest.
5. Run `mix pkg wotex-ble wotex.software.run --workspace ABS` and require the
   public interoperability and lifecycle-stress cases to execute.
6. Confirm that owned processes, containers, ports, D-Bus connections,
   subscriptions, timers and virtual controllers return to baseline.

A missing compiler, sanitizer runtime, Docker/QEMU facility, kernel feature,
peer or response is `not_run` or failed, never passed. ARM64 results may qualify
an additional lane but do not qualify x86_64.

## Archive and consumer qualification

Build the package from the same clean commit, inspect its exact contents and
run the out-of-tree consumer without repository paths. Record whether
dependencies came from verified candidate archives or published packages.
Candidate-archive evidence is not published-artifact adoption.

## Physical controller

The hardware-tagged test requires an explicitly configured BlueZ controller and
characteristic path. Record controller, kernel, BlueZ, peer firmware, RF setup,
pairing policy, reconnect behavior and cleanup. Virtual-controller results do
not claim radio-frequency behavior, and absence of hardware does not block
source implementation.
