# Executable evidence

This document records the accepted software evidence for the BACnet profile.
The subject is implementation commit
`868cca4cb4c1be88410aa6c88ae03f90c26a1053`, tree
`21e24f6f090ed5e17a6e9b879f58e83213835178` and canonical source digest
`e6d379d6885986d62abd410541082aa2a79b317464401ecc1416102d5f855d15`.
These identities describe tested source. They do not identify a published
release or establish hardware, certification or downstream consumer parity.

## Local and package gate

`WOTEX_PATH_DEPS=1 mix check --no-retry` passed on both supported toolchains.
The gate includes warnings-as-errors for project compilation, formatting,
strict Credo, Dialyzer, Doctor, ExDoc, dependency checks, unit/property/doctest
execution, coverage, Hex packaging, archive inspection, out-of-tree archive
compilation and the Application-free structural check.

| Elixir / OTP | Executed | Excluded peer/hardware tags | Coverage | Documentation/spec coverage | Archive SHA-256 |
| --- | ---: | ---: | ---: | ---: | --- |
| 1.20.2 / 29.0.4 | 285 | 35 | 95.1% | 100% | `93c6a13568b6aee868c1307b426accdd4351ae7c8f5fb680e74cbfd04e365c55` |
| 1.18.4 / 27.3.4.15 | 285 | 35 | 95.0% | 100% | `93c6a13568b6aee868c1307b426accdd4351ae7c8f5fb680e74cbfd04e365c55` |

The ordinary package declares Hex dependencies. `WOTEX_PATH_DEPS=1` selects the
sibling Wotex projects explicitly for workspace verification; the generated
archive retains the published dependency declarations.

## Source-bound software cohorts

The explicit build task produced fixture manifest
`94d1dc501dc6d8eb80461c1b38e1c78dc7468a26c1dbd53d9da460b178315144`
and image
`sha256:c83e9599f2cd8677797ae5e39a71b0c67c35f520b112d81e08a275f1c6286809`.
The build verifies the pinned BACstack package, C-stack source archive, fixture
sources, compiler/linker/CMake/libc identities, normal and instrumented build
options and every executable hash before a run can reuse the workspace.

The four-lane run passed independently on both supported toolchains.

| Toolchain | Lane | Cases | Cleanup | Owned containers after | Local cleanup |
| --- | --- | ---: | --- | ---: | ---: |
| Elixir 1.20.2 / OTP 29.0.4 | normal/shared | 320 | passed | 0 | 185 ms |
| Elixir 1.20.2 / OTP 29.0.4 | normal/terminal | 1 | passed | 0 | 51 ms |
| Elixir 1.20.2 / OTP 29.0.4 | sanitizer/shared | 320 | passed | 0 | 723 ms |
| Elixir 1.20.2 / OTP 29.0.4 | sanitizer/terminal | 1 | passed | 0 | 63 ms |
| Elixir 1.18.4 / OTP 27.3.4.15 | normal/shared | 320 | passed | 0 | 211 ms |
| Elixir 1.18.4 / OTP 27.3.4.15 | normal/terminal | 1 | passed | 0 | 62 ms |
| Elixir 1.18.4 / OTP 27.3.4.15 | sanitizer/shared | 320 | passed | 0 | 702 ms |
| Elixir 1.18.4 / OTP 27.3.4.15 | sanitizer/terminal | 1 | passed | 0 | 64 ms |

The aggregate result SHA-256 values are:

- Elixir 1.20.2 / OTP 29.0.4:
  `2873dac6d048f9209d10a9dd7bc540caa53ab3b8a38d7aecc77ab074bafb7331`
- Elixir 1.18.4 / OTP 27.3.4.15:
  `aa3175bc4d656846875c1147e1ff987046061158361f2c6c1d943701fa45541b`

Each aggregate contains the exact command, seed, source file hashes, dependency
source identities, fixture and binary hashes, toolchain, test receipt, protocol
observations, peer cleanup counters, local cleanup time, container absence and
log hashes. The shared receipts contain 95 distinct executed requirement IDs.
An absent or incomplete required case, sanitizer diagnostic, response,
observation or cleanup receipt makes the aggregate fail.

## Protocol and lifecycle coverage

### Typed services and owned ingress

P01 and P02 execute typed value and CharacterString handling, ACK/Error mapping,
segmentation limits, 64-operation admission, caller/deadline checks, reverse
cleanup and borrowed-stack preservation. IG01–IG06 exercise the actual receive
pipeline, including a suspended owner or client under 10,000 datagrams of 1536
bytes. The peak admitted receipt count is eight, exhausted credit leaves zero
armed sockets, and terminal slow-consumer handling releases the owned process
and socket set.

Additional cases cover forged acknowledgments, malformed datagrams, socket
closure, timer cancellation, a 64-session watcher bound, explicit IPv4 interface
selection and saturated counters. Host kernel packet loss is unavailable through
the selected portable inet API and is not represented as zero.

### Independent read, write and discovery

The peer links the pinned BACnet C stack and owns actual UDP transport. CP02
observes Who-Is/I-Am, three sequential Property reads, write/readback and
priority release through a second client. The peer also returns a protocol Error
for an unknown object. Discovery uses an explicit local destination and does not
modify host routes.

CP01 and CP10 execute native control and Property boundary matrices inside both
normal and ASan/UBSan image builds. All linked SDK and fixture diagnostics remain
observable and fail acceptance.

### Object and Property COV

CP03–CP09 execute confirmed and unconfirmed object COV, Status_Flags, renewal,
lost registration/renewal/cancellation ACKs and finite lease expiry. The peer
reports its actual subscription records, ACK counters, cancellation counters,
Invoke IDs and object values.

CP11–CP21 execute confirmed and unconfirmed Property COV, configured increments,
Status_Flags changes, Property-only selection, equal reports after renewal, all
16 capacity slots, rejected selectors, loss paths and public Runtime observation.
Cancellation loss distinguishes completed local cleanup from the peer's finite
server lifetime.

CP17 observes two values through the public Runtime path and stops the original
association even if a different target appears in the stop Form. I-F01 and
I-F02–I-F07 cover exact route, value, error and Retry projection through the
protocol and Runtime boundaries. The expected result is compared after execution
and is not supplied to the implementation under test.

### Ownership and stress

ST01 performs 1000 sequential reads and 32 concurrent reads. ST02 performs 100
complete owned-stack lifecycles. ST03 performs 100 receiver deaths across object
and Property COV in confirmed and unconfirmed modes. A second association stays
live during every ST03 cycle. Every cycle observes the expected server
cancellation, preserves the held association, terminates both captured local
subscription processes, cancels lease/renew timers and returns operation,
control, APDU, COV-reply and assembly tables to baseline.

CP22–CP24 start from an accepted Property registration whose ACK is withheld and
then terminate the Runtime owner, receiver or callback worker. Each case observes
cancellation of the original peer record, zero remaining peer subscriptions and
Invoke IDs, all captured process exits, UDP closure and cancellation of captured
opening/control timers within one cleanup budget.

CP25 establishes object and Property subscriptions and two confirmed Invoke IDs,
then exits the independently owned peer. The subsequent read times out and the
local stack closes within its cleanup budget. The peer's terminal receipt reports
zero sockets, subscriptions, Invoke IDs and disposable Analog Output objects.
The peer exit status and runner stop status are recorded separately because the
terminal test owns peer shutdown.

## Reproduction boundary

Use the Mix tasks described in the
[software implementation plan](../plans/software-implementation.md) with a fresh
absolute workspace. The shell files are thin delegates. The build task rejects a
workspace whose source, tool, option or binary identities do not match. The run
task creates four labelled container cohorts, uses disposable ports and removes
only those exact owned containers.

Re-run the local gate and affected peer cohorts after changing source, fixtures,
pins, build options or supported toolchains. Hardware and conformance-lab results
belong in separate evidence documents and do not alter this software acceptance.
