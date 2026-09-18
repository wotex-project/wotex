# Matter value bounds

The SDK-free checks the Matter controller host applies to every value and request: descriptor lookup, conversion of SDK values to TLV elements and their validation (`native/src/value.cpp`) for OnOff, a Thermostat setpoint, a 12-cluster ServerList and a 64-endpoint PartsList; validation of an Access Control List write of four entries with four subjects and two targets each, and of a 64-path Descriptor read with its response (`native/src/interaction.cpp`); and the commissioning request and commissioning-window checks (`native/src/commissioning.cpp`). The unit is one value or one request.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/value_bounds.cpp`

## Results

|            ns/value |             value/s |    err% |     total | value bounds |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|                6.19 |      161,647,515.30 |    5.9% |      0.20 | :wavy_dash: `convert OnOff boolean` (Unstable with ~2,782,520.4 iters. Increase `minEpochIterations` to e.g. 27825204) |
|                6.43 |      155,451,751.01 |    1.6% |      0.24 | `convert and validate setpoint i16` |
|               72.12 |       13,866,668.92 |    0.5% |      0.24 | `convert and validate ServerList 12 clusters` |
|              313.58 |        3,189,024.99 |    0.3% |      0.24 | `convert and validate PartsList 64 endpoints` |

|          ns/request |           request/s |    err% |     total | value bounds |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|               90.84 |       11,007,902.38 |    1.4% |      0.24 | `validate ACL write 4 entries x 4 subjects` |
|            1,215.68 |          822,587.14 |    0.5% |      0.24 | `validate Descriptor read 64 paths and response` |
|                5.84 |      171,261,448.21 |    0.4% |      0.24 | `validate commissioning request and window response` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
