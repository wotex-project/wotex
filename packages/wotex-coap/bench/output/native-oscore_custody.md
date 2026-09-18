# OSCORE helper process custody

The process custody of the native OSCORE helper (`native/oscore/custody.c`), started with the arguments `main.c` gives it (500 ms cleanup deadline, 256 KiB queues) and the benchmark executable as an echo worker: one whole lifecycle (guardian and worker start, one 256-byte line echoed, a `close` line, worker exit and reap with exit status 0), the same lifecycle of the worker spawned directly as the baseline, and round trips of 256-byte, 4 KiB and 32 KiB lines from the owner through the guardian to a running worker and back. The lifecycle rows include the forks and the worker's exec, and the guardian's 10 ms poll interval while it waits for the worker's exit.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/oscore_custody.cpp`

## Results

|           ns/worker |            worker/s |    err% |     total | custody |
|--------------------:|--------------------:|--------:|----------:|:-------- |
|        1,970,189.50 |              507.57 |    0.3% |      2.98 | `start, echo one line, close and reap` |
|        1,625,534.59 |              615.18 |    0.2% |      3.03 | `baseline: the same worker without custody` |

|             ns/line |              line/s |    err% |     total | custody |
|--------------------:|--------------------:|--------:|----------:|:-------- |
|           15,256.35 |           65,546.46 |    0.2% |      0.59 | `round trip of a 256 B line` |
|           16,618.19 |           60,175.01 |    0.2% |      0.60 | `round trip of a 4 KiB line` |
|           25,052.89 |           39,915.55 |    0.3% |      0.61 | `round trip of a 32 KiB line` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
