# Software-lane command guardian

The command guardian of the software lane (`test/interop/native/command.c`, linked with its `main` renamed), which runs one command in its own process group under a deadline, a bound on its combined output and owner liveness on standard input. Eight invalid argument vectors rejected in process (status 126); then, with the benchmark executable as the command, that command spawned directly as the baseline and, with the guardian in a child process, a command that exits at once, relays of 64 KiB and 1 MiB, 1 MiB stopped at a 64 KiB output bound (status 125), a waiting command stopped at a 20 ms deadline (status 124), and the fixture lock acquired and released (`--lock`). Each process row reads the output to its end and checks the exit status and the byte count; it includes the forks and the command's exec, and the guardian polls every 10 ms, which quantizes these rows.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/command_guardian.cpp`

## Results

|           ns/vector |            vector/s |    err% |     total | command guardian |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|               12.37 |       80,863,049.27 |    0.7% |      0.52 | `reject 8 invalid argument vectors` |

|          ns/command |           command/s |    err% |     total | command guardian |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|        1,586,159.53 |              630.45 |    0.2% |      3.02 | `baseline: the same command without the guardian` |
|        1,894,186.62 |              527.93 |    0.8% |      3.02 | `run a command that exits at once` |
|        2,007,219.03 |              498.20 |    1.2% |      3.06 | `relay 64 KiB of output` |
|        2,279,330.39 |              438.73 |    3.2% |      3.06 | `relay 1 MiB of output` |
|        1,935,587.33 |              516.64 |    1.0% |      3.08 | `stop 1 MiB of output at a 64 KiB bound` |
|       36,353,162.00 |               27.51 |    0.9% |      3.27 | `stop a waiting command at a 20 ms deadline` |
|          447,457.17 |            2,234.85 |    0.3% |      3.01 | `acquire and release the fixture lock` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
