# Build command guardian

The build and fixture command guardian (`priv/bluez/native/build_command.c`) with the native build's limits (600 s, 16 MiB of output, 5,000 ms cleanup): running `/usr/bin/true` in its own process group, and forwarding the 1 MiB output of `/bin/cat` through the guardian's bounded queue to the owner. The driver forks and runs the guardian's `main` in the child, so the guardian's own `exec` is not measured; the command's is. The guardian polls at most 10 ms at a time and observes the command's exit only after a poll: when it reads the output's end before the exit is observable, it waits out one poll interval, so the time per command is bimodal and its median varies between runs.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/command_guardian.cpp`

## Results

|          ns/command |           command/s |    err% |     total | command guardian |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|        1,500,406.25 |              666.49 |    1.0% |      0.36 | `run /usr/bin/true` |

|             ns/byte |              byte/s |    err% |     total | command guardian output |
|--------------------:|--------------------:|--------:|----------:|:------------------------ |
|                1.71 |      585,861,425.55 |    2.7% |      0.45 | `forward 1 MiB from /bin/cat` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
