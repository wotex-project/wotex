# Attribute byte envelopes

Attribute byte envelopes (`priv/bluez/native/bytes.hpp`): canonical base64 decoding of a byte envelope into attribute bytes within the 512-byte ATT bound, and encoding of attribute bytes into an envelope, for 20-byte (default ATT MTU), 244-byte (LE Data Length Extension) and 512-byte (ATT maximum) values. The unit is one value.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/bytes.cpp`

## Results

|            ns/value |             value/s |    err% |     total | attribute byte envelopes |
|--------------------:|--------------------:|--------:|----------:|:------------------------- |
|               76.71 |       13,036,617.51 |    5.0% |      0.19 | :wavy_dash: `decode 20 B` (Unstable with ~202,989.0 iters. Increase `minEpochIterations` to e.g. 2029890) |
|              262.68 |        3,806,979.46 |    0.5% |      0.24 | `encode 20 B` |
|              317.14 |        3,153,189.88 |    1.6% |      0.24 | `decode 244 B` |
|              910.17 |        1,098,693.41 |    0.3% |      0.24 | `encode 244 B` |
|              642.16 |        1,557,247.09 |    1.6% |      0.24 | `decode 512 B` |
|            1,695.17 |          589,910.51 |    0.4% |      0.24 | `encode 512 B` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
