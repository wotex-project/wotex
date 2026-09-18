# Output lanes

Admission of 64 report frames into the lane reservations of the Thread host's output (`priv/openthread/output.hpp`), and admission followed by a flush through `write(2)` to a non-blocking `/dev/null` of 64 report frames and of 256 control frames (each lane's frame limit), of 192 reply, control and report frames interleaved in one output order, and of 8 report frames of 128 KiB (the report lane's byte budget). The other frames are 212 bytes, newline included. The unit is one frame.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/output_lanes.cpp`

## Results

|            ns/frame |             frame/s |    err% |     total | output lanes |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|               23.57 |       42,432,718.36 |   10.8% |      0.20 | :wavy_dash: `admit 64 x 212 B report` (Unstable with ~11,747.6 iters. Increase `minEpochIterations` to e.g. 117476) |
|              356.45 |        2,805,450.84 |    0.8% |      0.24 | `admit and flush 64 x 212 B report` |
|              356.24 |        2,807,098.23 |    0.4% |      0.24 | `admit and flush 256 x 212 B control` |
|              355.38 |        2,813,917.30 |    0.7% |      0.24 | `admit and flush 192 x 212 B, reply, control and report interleaved` |
|            5,722.80 |          174,739.61 |    2.4% |      0.24 | `admit and flush 8 x 128 KiB report` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
