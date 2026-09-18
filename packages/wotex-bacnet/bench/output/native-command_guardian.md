# Fixture command guardian

The POSIX command guardian of the BACnet software lane (`test/interop/native/command.c`), compiled with its `main` renamed and run in a forked child with an owner-liveness pipe as standard input and a pipe to the driver as standard output, as the Mix owner runs the executable (the guardian's own `exec` is not measured). The guarded command is the driver re-executed in a child mode that exits at once or writes 1 MiB; each row collects the output to EOF and checks both exit statuses and the byte count, and the rows without the guardian spawn the same command directly as the baseline. The unit is one command. The lease row takes and releases the advisory fixture lock (`command --lock`) in the benchmark's scratch directory; its unit is one lease.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/command_guardian.cpp`

## Results

|          ns/command |           command/s |    err% |     total | command |
|--------------------:|--------------------:|--------:|----------:|:-------- |
|        1,612,306.70 |              620.23 |    1.3% |      0.54 | `command that exits, without the guardian` |
|        1,882,111.32 |              531.32 |    0.5% |      0.62 | `command that exits, guarded` |
|        1,768,461.43 |              565.46 |    0.4% |      0.59 | `command writing 1 MiB, without the guardian` |
|        2,108,585.40 |              474.25 |    0.4% |      0.73 | `command writing 1 MiB, guarded` |

|            ns/lease |             lease/s |    err% |     total | fixture lock |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|          444,024.80 |            2,252.13 |    1.5% |      0.49 | `take and release the advisory lock` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
