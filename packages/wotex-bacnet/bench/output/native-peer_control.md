# C-stack peer control parser

The control-command parser of the independent BACnet C-stack software peer (`test/interop/cstack/control.c`), the part of the peer that compiles without the pinned BACnet stack: `peer_parse` on the control datagrams the software runner sends (`stats`, `fault` and `quit` with a nonce), accepted and rejected. The unit is one command.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/peer_control.cpp`

## Results

|          ns/command |           command/s |    err% |     total | control commands |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|               16.14 |       61,938,919.39 |    5.5% |      0.19 | :wavy_dash: `peer_parse, stats with the largest nonce` (Unstable with ~1,019,361.6 iters. Increase `minEpochIterations` to e.g. 10193616) |
|               31.15 |       32,107,365.43 |    0.8% |      0.24 | `peer_parse, fault cancel_request 255` |
|               25.12 |       39,801,434.99 |    2.0% |      0.24 | `peer_parse, fault count out of range` |
|               11.35 |       88,140,794.67 |    1.3% |      0.24 | `peer_parse, quit` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
