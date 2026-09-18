# Input framing and envelope admission

`priv/native/ipc.c` of the OPC UA host: `wop_ipc_feed` assembling LF-terminated request lines: a Read from one read and from 64-byte reads, 16 Reads coalesced in one read, and a 7.4 KB Write of 1024 Doubles from one read (unit: one line); and the closed shape checks applied to a parsed line: the request envelope, the credit control and the `open` parameters with 2048-bit RSA credential envelopes, whose base64 is checked character by character (unit: one check).

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/ipc.cpp`

## Results

|             ns/line |              line/s |    err% |     total | wop_ipc_feed |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|              100.70 |        9,930,893.64 |    5.9% |      0.19 | :wavy_dash: `read request, 193 B in one read` (Unstable with ~156,911.3 iters. Increase `minEpochIterations` to e.g. 1569113) |
|              115.11 |        8,687,472.95 |    2.9% |      0.24 | `read request in 64-byte reads` |
|               94.44 |       10,588,489.07 |    0.4% |      0.23 | `16 coalesced read requests in one read` |
|            3,344.21 |          299,023.87 |    0.4% |      0.24 | `write request, 1024 Doubles, 7403 B in one read` |

|            ns/check |             check/s |    err% |     total | envelope admission |
|--------------------:|--------------------:|--------:|----------:|:------------------- |
|               27.17 |       36,799,568.05 |    1.3% |      0.24 | `wop_ipc_request, read envelope` |
|               39.61 |       25,248,318.04 |    1.9% |      0.24 | `wop_ipc_credit, credit control` |
|            2,045.59 |          488,856.91 |    1.2% |      0.24 | `wop_ipc_open, 2048-bit RSA credential envelopes` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
