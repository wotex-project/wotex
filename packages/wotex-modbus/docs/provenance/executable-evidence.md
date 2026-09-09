# Modbus executable evidence

The [TCP cohort receipt](software-tcp-v1.json) binds source commit
`0c32a64b2c3a6f6813cd0d7976d5359b7585c8d3` to actual independent libmodbus responses,
standalone/Runtime fixture assertions, malformed boundaries and software stress.
Every recorded subject file hash matches that commit. Dependency identities are
source digests; the execution uses explicit path dependencies, not registry or
independent artifact installation.

| Lane | Executed result | Native peer |
| --- | --- | --- |
| Elixir 1.18.4 / OTP 27.3.4.15 | 137 passing checks: 4 properties, 133 tests | pinned libmodbus 3.1.12, Linux ASan/UBSan/leak checks |
| Elixir 1.20.2 / OTP 29.0.4 | 137 passing checks: 4 properties, 133 tests | same pinned peer and native checks |

The suite asserts all eight functions, readback and remote exceptions; 1,000
sequential operations; 100 open/close cycles; 32 concurrent callers; and ten
cycles each of timeout, peer close and malformed response. Final owned sockets,
contexts, mappings and containers are zero. A separate malformed peer exercises
invalid frames; the independent C peer is not presented as an injected simulator.

That cohort executed the Python version of `test/interop/run_software.sh`
and ExUnit. The current shell entry point executes the Mix task. The native protocol peer is C; the
production client is BEAM TCP. These results do not validate the
[WMB.13 Mix tasks](../specs/WMB.13-native-build-and-software-evidence.md).

## Requirement evidence

| Contract | Concrete asserting sources |
| --- | --- |
| S01 / D01–D04 | `boundary_test.exs`, `value_test.exs`, `connection_test.exs`, `compatibility_test.exs` |
| S02 / V03–V05 | `codec_test.exs`, `stream_fault_test.exs` |
| S03 / C03 | `lifecycle_test.exs`, `connection_test.exs` |
| S04 / I01–I06 | `compatibility_test.exs`, `runtime_integration_test.exs`, `mapping_test.exs` |
| C09 / V11–V12 | `test/interop/modbus_test.exs`, `test/software/lifecycle_stress_test.exs` |

Unqualified filenames above are under `test/wotex/modbus/`. The receipt contains
exact source and fixture hashes. The tests compare actual public API/peer
outcomes with expected projections; a fixture ID alone is not acceptance.

## Package and ongoing validation

The mandatory gate is `WOTEX_PATH_DEPS=1 mix check --no-retry`, including complete
static checks, tests/coverage, docs and unpacked out-of-tree package compilation.
The documentation cohort `b214e99` has 132 passing checks (1 doctest, 4 properties,
127 tests), 95.3% coverage and a passing complete latest-toolchain gate. It is a
different cohort from the explicit software run above. Relevant source changes
require fresh software evidence; a prior receipt cannot validate new code or tools.

The eight-function client, standalone and Runtime contracts are implemented.
WMB.13 Mix orchestration has committed-source task results on both toolchains;
whole-VM opening remains unaccepted.
This evidence supplies neither a
published release, stable API decision, hardware result nor certification.

## Native command ownership

`test/software/command_test.exs` asserts real process-group cleanup on timeout,
owner death, TERM, output overflow and successful root exit, plus suspended
consumer output bounds and preservation of a separate owned group. The native
`test/interop/native/check.c` suite supplies eight standalone cases; the current
source passes macOS native and Linux ASan/UBSan execution. The lease cohort `56ac074` passed the complete
latest-toolchain gate with 145 checks. These first-party command fixtures are
not a protocol peer.

The Mix tasks use `test/support/software/` and assert source/manifests, real
reuse, failed commands, bounded output, readiness failure, active owner death,
created-before-start owner death and explicit failed cleanup in
`test/software/fixture_tasks_test.exs`. The software formatter records actual
test-finished names, requirement IDs and outcomes. Full P06 acceptance requires
committed-source task results on both supported toolchains. Whole-VM loss during
container opening and unavailable-daemon removal remain unverified; neither
may be reported as successful cleanup or inferred from a passing active case.

## Mix orchestration cohort

The [Mix software receipt](software-mix-v1.json) binds commit `ab69680` and its
exact tree/file hashes to actual Mix task runs on both supported toolchains.
Each lane executes 169 checks including native command/lease ownership,
independent libmodbus functions, 1,000 sequential requests, 100 connection
cycles, 32 concurrent callers, malformed peers and nested failure/cleanup
controls. Both test and peer processes exit zero; final native socket, context,
mapping and owned-container counters are zero. The receipt retains exact
per-case outcomes, fault log/result digests and dependency source digests.
Source cohorts remain explicit: a receipt does not automatically validate a
later source or wrapper change. Generic Python orchestration is absent from the
current task workflow. Whole-VM opening and unavailable-daemon cleanup have no
passing acceptance claim.
