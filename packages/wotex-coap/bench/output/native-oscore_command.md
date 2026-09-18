# OSCORE helper command input

The native OSCORE helper's input path for one command line from its owner, as the worker's `consume` runs it: LF framing (`native/oscore/frame.c`), parsing into the fixed 2 MiB yyjson pool with its duplicate-member, depth and number checks (`json.c`), decoding against the per-operation allowlists (`command.c`, with `body.c` for byte envelopes), then erasure of the command and of the parser pool. One line of each operation, sixteen coalesced lines delivered in 4 KiB reads, a line rejected for a duplicate member, and the pool erasure alone, which runs twice for every line. The unit is one line.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/oscore_command.cpp`

## Results

|             ns/line |              line/s |    err% |     total | command line |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|          118,614.41 |            8,430.68 |    0.6% |      0.22 | `open with OSCORE credentials` |
|          116,209.81 |            8,605.13 |    0.1% |      0.24 | `request GET` |
|          116,264.38 |            8,601.09 |    0.1% |      0.24 | `request PUT with body` |
|          116,070.48 |            8,615.46 |    0.2% |      0.24 | `body_begin` |
|          119,437.04 |            8,372.61 |    0.2% |      0.24 | `body_chunk 1 KiB` |
|          189,481.25 |            5,277.57 |    0.6% |      0.24 | `body_chunk 32 KiB` |
|          116,158.42 |            8,608.93 |    0.1% |      0.24 | `body_end` |
|          116,076.66 |            8,615.00 |    0.3% |      0.24 | `observe` |
|          115,649.25 |            8,646.83 |    0.3% |      0.24 | `credit` |
|          116,190.24 |            8,606.58 |    0.2% |      0.24 | `cancel` |
|          116,250.95 |            8,602.08 |    0.1% |      0.24 | `close` |
|          116,347.22 |            8,594.96 |    0.1% |      0.24 | `16 coalesced lines in 4 KiB reads` |
|          173,880.00 |            5,751.09 |    0.1% |      0.24 | `reject a duplicate member` |
|           57,972.36 |           17,249.60 |    0.1% |      0.24 | `erase the 2 MiB parser pool` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
