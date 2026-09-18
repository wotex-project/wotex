# Runtime custody relay

The runtime custody guardian of the OPC UA host (`priv/native/custody.c`), which relays opaque bytes between the BEAM host and the SDK executable. It is compiled with its `main` renamed and run in a forked child whose standard input and output are pipes owned by the driver, as the BEAM Port runs the executable, with the OPC UA profile's limits (500 ms cleanup, 131072-byte input and 65536-byte output queues); the guardian's own `exec` is not measured. The guarded child is the driver re-executed as a line echo standing in for the SDK host. The relay rows send a 256-byte or 16 KiB line and read it back on a running Session (unit: one round trip); the lifecycle rows start the guardian and its child, make one round trip, end the child with `quit` and check that custody exits with status 0 after reaping it (unit: one session). The rows without custody talk to the same echo process over plain pipes as the baseline.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/custody.cpp`

## Results

|       ns/round trip |        round trip/s |    err% |     total | relay |
|--------------------:|--------------------:|--------:|----------:|:------ |
|            4,634.80 |          215,758.94 |    1.5% |      0.32 | `256 B line, without custody` |
|           15,498.87 |           64,520.84 |    0.3% |      0.36 | `256 B line through custody` |
|            7,981.98 |          125,282.19 |    1.3% |      0.36 | `16 KiB line, without custody` |
|           20,121.94 |           49,697.00 |    0.2% |      0.36 | `16 KiB line through custody` |

|          ns/session |           session/s |    err% |     total | lifecycle |
|--------------------:|--------------------:|--------:|----------:|:---------- |
|        1,635,447.56 |              611.45 |    0.4% |      0.54 | `start, one 256 B round trip and clean exit, without custody` |
|        1,959,482.36 |              510.34 |    0.2% |      0.65 | `start, one 256 B round trip and clean exit, through custody` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
