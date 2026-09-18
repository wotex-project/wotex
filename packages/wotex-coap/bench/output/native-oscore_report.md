# OSCORE helper report credit and freshness

Admission of Observe reports in the native OSCORE helper: the cumulative report credit of one generation (`native/oscore/credit.c`), with eight reports assigned, written and acknowledged per window and the exhausted window checked, and the RFC 7641 freshness decision (`observation.c`) for the next in-order notification, a replay, a 24-bit wraparound and a changed Content-Format. The unit is one report.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/oscore_report.cpp`

## Results

|           ns/report |            report/s |    err% |     total | report |
|--------------------:|--------------------:|--------:|----------:|:------- |
|                1.79 |      557,888,684.11 |    1.1% |      0.23 | `credit: assign, write and acknowledge a window of 8` |
|                1.36 |      736,822,107.20 |    0.7% |      0.23 | `freshness: admit the next notification` |
|                1.03 |      974,036,336.69 |    6.8% |      0.24 | :wavy_dash: `freshness: reject a replayed notification` (Unstable with ~20,836,419.8 iters. Increase `minEpochIterations` to e.g. 208364198) |
|                1.35 |      741,333,495.20 |    0.5% |      0.23 | `freshness: admit across the 24-bit wraparound` |
|                1.20 |      833,903,644.86 |    0.2% |      0.24 | `freshness: detect a changed Content-Format` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
