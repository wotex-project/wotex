# Wotex Thread qualification runbook

This runbook qualifies a completed source revision in environments that are not
part of implementation. It does not define package behavior and does not decide
`implementation_status` in the specification catalogue.

## Boundary

Implementation consists of the Elixir and C++ contracts, source pins, build and
fixture tasks, finite error behavior, and executable tests owned by WTH.01–WTH.07.
A dependency vulnerability that applies to the selected build is an
implementation defect and must be fixed by a pin update or an exact reviewed
source patch.

Qualification establishes claims about a particular operating system,
architecture, toolchain, archive, physical device, or published artifact.
Unavailable runners and devices leave those claims unqualified; they do not
turn implemented source back into planned source.

## Inputs

Qualify one clean commit. Record the commit, package path, lockfile digest,
OpenThread and Mbed TLS pins, source archive digests, compiler and linker
identities, operating system, architecture, BEAM versions, command lines, case
counts, and result-artifact digests. Use a new absolute disposable workspace
for every build or software run.

Transient logs and receipts belong under
`docs/tasks/local/wotex-thread/`. A reviewed, reproducible result may be added
to `provenance/`; an older record is never relabelled for changed source.

## Native and software matrix

On each selected Linux architecture:

1. Run `mix pkg wotex-thread wotex.native.build --workspace ABS`.
2. Run the ordinary native component tests and the selected ASan/UBSan lane.
3. Run `mix pkg wotex-thread wotex.software.build --workspace ABS`.
4. Run `mix pkg wotex-thread wotex.software.run --workspace ABS` for the
   declared Elixir/OTP cohorts.
5. Require every mandatory case to execute. A missing compiler, simulator,
   kernel facility, peer, or response is `not_run` or failed, never passed.
6. Confirm that owned processes, ports, sockets, timers, SDK contexts, storage
   directories, and simulated radios return to their recorded baselines.

Architecture results are not interchangeable. Native execution and binary
translation are recorded separately.

## Security review

Run the networked advisory check from `packages/wotex-thread`:

```sh
mix run --no-start bin/check_native_advisories.exs
```

The check queries the exact source commits and verifies that every
`fixed_in_pin` commit is an ancestor of the selected pin. Review a newly
reported advisory against its primary vendor record and upstream source. Do not
record a waiver as a pass. A documented risk exception requires a maintainer
security decision outside this runbook.

## Archive and consumer qualification

Build the package from the same clean commit, inspect its exact contents, and
run the archive consumer without a source checkout or Git dependency. Record
whether dependencies came from verified candidate archives or published
packages. Candidate-archive evidence is not published-artifact adoption.

## Physical devices

The hardware-tagged daemon test requires a consumer-supplied OpenThread daemon
socket and a named device configuration. Record radio, firmware, topology,
dataset handling, reconnect behavior, and cleanup. Software simulation does not
claim radio-frequency behavior, and absence of hardware does not block source
implementation.
