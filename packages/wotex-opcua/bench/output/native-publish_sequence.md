# Notification sequence state

The per-subscription notification sequence state of the OPC UA host (`priv/native/publish_sequence.c`): classification and recording of the next data-change notification once the cache holds its 1024 sequence/digest pairs, duplicate detection of the latest and of the oldest cached notification, recovery of a 100-message gap by ordered Republish followed by delivery of the held notification, and the first 16 notifications of a new subscription. The unit is one notification.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/publish_sequence.cpp`

## Results

|     ns/notification |      notification/s |    err% |     total | publish sequence |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|              304.81 |        3,280,759.82 |    5.0% |      0.19 | `in order, full 1024-entry cache` |
|                2.07 |      481,943,354.58 |    0.4% |      0.24 | `duplicate of the latest notification` |
|              283.84 |        3,523,159.09 |    0.1% |      0.24 | `duplicate of the oldest cached notification` |
|                5.47 |      182,766,742.44 |    0.4% |      0.24 | `gap of 100 recovered by Republish` |
|               16.33 |       61,227,646.24 |    4.3% |      0.26 | `first 16 notifications of a subscription` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
