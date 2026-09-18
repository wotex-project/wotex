# Bounded output queue

Admission of normal envelopes into the bounded output queue of the OPC UA host (`priv/native/output.c`), and admission followed by a credited flush through `write(2)` to `/dev/null`, for 256-byte and 4 KiB envelopes. The unit is one envelope.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/output_queue.cpp`

## Results

|         ns/envelope |          envelope/s |    err% |     total | output queue |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|               17.67 |       56,587,258.99 |    3.7% |      0.19 | `admit 64 x 256 B` |
|              352.62 |        2,835,916.46 |    0.3% |      0.24 | `admit and flush 16 x 256 B` |
|              135.62 |        7,373,470.83 |    0.3% |      0.24 | `admit 64 x 4096 B` |
|              463.90 |        2,155,632.69 |    0.3% |      0.24 | `admit and flush 16 x 4096 B` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
