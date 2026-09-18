# Build command guardian

The POSIX command guardian of the explicit native build (`priv/native/build_command.c`), through which `Wotex.OPCUA.Native.Command` runs every recipe step. It is compiled with its `main` renamed and run in a forked child with an owner-liveness pipe as standard input and a pipe to the driver as standard output, as the Mix owner runs the executable (the guardian's own `exec` is not measured). The guarded command is the driver re-executed in a child mode that exits at once or writes 1 MiB; each row collects the output to EOF and checks both exit statuses and the byte count, and the rows without the guardian spawn the same command directly as the baseline. The unit is one command.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/build_command.cpp`

## Results

|          ns/command |           command/s |    err% |     total | command |
|--------------------:|--------------------:|--------:|----------:|:-------- |
|        1,591,121.78 |              628.49 |    0.8% |      0.54 | `command that exits, without the guardian` |
|        1,889,108.01 |              529.35 |    0.7% |      0.63 | `command that exits, guarded` |
|        1,763,571.60 |              567.03 |    1.3% |      0.58 | `command writing 1 MiB, without the guardian` |
|        2,110,026.19 |              473.93 |    0.7% |      0.72 | `command writing 1 MiB, guarded` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
