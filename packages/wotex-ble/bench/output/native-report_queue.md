# Unsent-report queue

The unsent-report queue (`priv/bluez/native/report_queue.hpp`) holding 20-byte values charged 320 bytes each: admission of 64 reports and a drain that dispatches them all, on one stream and on 8 streams; a drain in which 4 of 8 streams lack credit, whose reports are then discarded; and admission of 64 reports on one stream followed by its discard, the path of a silenced stream. The unit is one report.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/report_queue.cpp`

## Results

|           ns/report |            report/s |    err% |     total | report queue |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|               19.30 |       51,820,602.28 |    0.3% |      0.55 | `admit 64 on 1 stream, drain all` |
|               23.27 |       42,968,874.67 |    0.1% |      0.60 | `admit 64 on 8 streams, drain all` |
|               38.27 |       26,128,724.86 |    0.2% |      0.61 | `admit 64 on 8 streams, drain with 4 credit-blocked, discard them` |
|               19.46 |       51,392,128.43 |    0.9% |      0.60 | `admit 64 on 1 stream, discard` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
