# OSCORE helper upload body

The upload body of the native OSCORE helper (`native/oscore/body.c`): canonical base64 validation and decoding of one 32 KiB byte envelope, and whole uploads of 1 KiB, 64 KiB and 1 MiB (the limit) as the worker admits them: `wco_body_begin` (allocation), one `wco_body_chunk` per chunk of at most 32 KiB, `wco_body_end` (SHA-256 verification), data access and `wco_body_clear` (erasure). The unit is one decoded byte.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/oscore_body.cpp`

## Results

|                ns/B |                 B/s |    err% |     total | upload body |
|--------------------:|--------------------:|--------:|----------:|:------------ |
|                1.79 |      558,323,851.95 |    6.6% |      0.20 | :wavy_dash: `decode one 32 KiB chunk` (Unstable with ~297.3 iters. Increase `minEpochIterations` to e.g. 2973) |
|                2.47 |      405,237,013.98 |    1.1% |      0.24 | `upload 1 KiB in 1 chunk` |
|                2.18 |      459,085,077.46 |    1.1% |      0.23 | `upload 64 KiB in 2 chunks` |
|                2.13 |      470,070,534.61 |    1.3% |      0.24 | `upload 1 MiB in 32 chunks` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
