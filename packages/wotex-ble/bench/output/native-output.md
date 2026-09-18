# Bounded serialization and native output

Bounded serialization and nonblocking output (`priv/bluez/native/output.hpp`): validation and encoding of a value report envelope carrying a 20-byte or a 512-byte value, and admission followed by a flush through `write(2)` to `/dev/null` of 64 read replies, each into its reserved slot, and of 64 report frames. The unit is one frame.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/output.cpp`

## Results

|            ns/frame |             frame/s |    err% |     total | native output |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|            2,020.58 |          494,907.18 |    7.5% |      0.19 | :wavy_dash: `encode report, 20 B value` (Unstable with ~7,703.7 iters. Increase `minEpochIterations` to e.g. 77037) |
|            2,948.20 |          339,189.53 |    0.8% |      0.24 | `encode report, 512 B value` |
|              385.51 |        2,593,955.86 |    0.2% |      0.24 | `reserve, reply and flush 64 replies` |
|              363.34 |        2,752,267.09 |    0.6% |      0.24 | `admit and flush 64 reports, 20 B value` |
|              381.04 |        2,624,404.20 |    0.3% |      0.24 | `admit and flush 64 reports, 512 B value` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
