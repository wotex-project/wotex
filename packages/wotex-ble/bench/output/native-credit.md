# Cumulative report credit

Cumulative report credit (`priv/bluez/native/credit.hpp`): reservation of 320-byte reports and the validated `report_ack` frame that returns their credit, for one stream filling its 16-report window and for 64 streams with one report each, and the credit lifecycle of one stream (open, reserve, retire, acknowledge). The unit is one report, or one stream.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/credit.cpp`

## Results

|           ns/report |            report/s |    err% |     total | report credit |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|               14.66 |       68,195,855.96 |    2.3% |      0.20 | `reserve 16 on 1 stream, acknowledge once` |
|               10.30 |       97,059,648.67 |    1.0% |      0.24 | `reserve 1 on each of 64 streams, acknowledge once` |

|           ns/stream |            stream/s |    err% |     total | stream credit lifecycle |
|--------------------:|--------------------:|--------:|----------:|:------------------------ |
|              183.45 |        5,451,213.06 |    0.4% |      0.24 | `open, reserve, retire and acknowledge` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
