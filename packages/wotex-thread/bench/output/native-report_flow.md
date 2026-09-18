# State report credit

The report credit of the Thread host (`priv/openthread/flow.hpp`): credited submission of reports and their exact cumulative acknowledgement, for 16 reports on one stream (the per-stream credit) and 64 reports on four streams (the session credit); 64 reports on one stream, of which 48 wait in the queue and are drained by four acknowledgements; and the retirement, with its barrier, of one stream holding 16 outstanding and 16 queued reports and of 64 streams holding one report each, followed by the acknowledgement that releases them. Reports are 212 encoded bytes, newline included, and the writers only count them. The unit is one report, or one stream for retirement.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/report_flow.cpp`

## Results

|           ns/report |            report/s |    err% |     total | report credit |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|               65.64 |       15,234,173.15 |    5.0% |      0.19 | :wavy_dash: `16 reports on 1 stream, acknowledged` (Unstable with ~14,929.5 iters. Increase `minEpochIterations` to e.g. 149295) |
|               81.25 |       12,307,805.44 |    0.8% |      0.24 | `64 reports on 4 streams, acknowledged` |
|              126.49 |        7,906,052.32 |    0.9% |      0.24 | `64 reports on 1 stream, 48 queued, drained by 4 acknowledgements` |

|           ns/stream |            stream/s |    err% |     total | stream retirement |
|--------------------:|--------------------:|--------:|----------:|:------------------ |
|            2,344.64 |          426,504.96 |    0.6% |      0.24 | `16 outstanding and 16 queued reports, retired, acknowledged` |
|              301.67 |        3,314,922.23 |    3.0% |      0.24 | `64 streams of 1 report, retired, acknowledged` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
