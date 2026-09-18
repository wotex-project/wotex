# Matter subscription report flow

Subscription reports in the Matter controller host, whose session credit is 64 reports and 1 MiB and whose stream credit is 16 reports: `ReportCreditManager` (`native/src/subscription.cpp`) transmitting a full window of 64 reports over four streams and releasing it with one acknowledgement, and 64 reports to one stream, of which 48 wait for credit and are drained by acknowledgements; `SubscriptionBuffer` assembling a subscription's initial report of four paths and 60 single-path changes; and the complete path through `HostProtocol` (`native/src/protocol.cpp`): the controller's report callback, the encoded `subscription_report` frame and credit accounting for 16 reports, then the `report_ack` line that returns their credit. The unit is one report.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/report_flow.cpp`

## Results

|           ns/report |            report/s |    err% |     total | report flow |
|--------------------:|--------------------:|--------:|----------:|:------------ |
|              389.14 |        2,569,798.19 |    5.6% |      0.20 | :wavy_dash: `credit window: 64 reports over 4 streams, one ack` (Unstable with ~708.1 iters. Increase `minEpochIterations` to e.g. 7081) |
|              510.93 |        1,957,203.18 |    4.4% |      0.24 | `stream credit: 64 reports, 48 queued, drained by acks` |
|               59.46 |       16,817,317.87 |    3.9% |      0.24 | `assemble initial report of 4 paths and 60 changes` |
|            7,430.30 |          134,584.00 |    1.9% |      0.23 | `host report: 16 callbacks, frames and one report_ack` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
