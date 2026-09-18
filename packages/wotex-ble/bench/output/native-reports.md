# Native report path

The native report path (`priv/bluez/native/reports.hpp` over the credit, queue, output, byte-envelope and error-value components): publication of value callbacks, a flush through `write(2)` to `/dev/null` and the owner's cumulative acknowledgement, for 16 reports of 20 or 512 bytes that fit one stream's credit window and for 64 reports of 20 bytes that exceed it, so that 48 wait in the queue and drain as four acknowledgements return credit; and opening and retiring a subscription, with or without a terminal error control. The unit is one report, or one subscription.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/reports.cpp`

## Results

|           ns/report |            report/s |    err% |     total | native report path |
|--------------------:|--------------------:|--------:|----------:|:------------------- |
|            4,387.20 |          227,935.78 |    3.6% |      0.20 | `publish, flush and acknowledge 16 x 20 B` |
|            7,255.64 |          137,823.82 |    0.6% |      0.24 | `publish, flush and acknowledge 16 x 512 B` |
|            7,217.99 |          138,542.76 |    0.6% |      0.24 | `publish 64 x 20 B beyond the 16-report window, drain by acknowledgement` |

|     ns/subscription |      subscription/s |    err% |     total | native report subscriptions |
|--------------------:|--------------------:|--------:|----------:|:---------------------------- |
|           10,059.41 |           99,409.43 |    0.4% |      0.24 | `open and retire` |
|           12,271.66 |           81,488.54 |    0.3% |      0.24 | `open and retire with a terminal error` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
