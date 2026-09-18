# Runtime guardian relay and sessions

The runtime guardian (`priv/bluez/native/custody.c`) with the BLE profile's limits (500 ms cleanup, 131,072 input and 65,536 output bytes): the round trip of a 256-byte line and of a 64 KiB burst from the owner through the guardian to an echoing SDK child (`/bin/cat`) and back, and whole sessions: start, SDK exit and reap (`/usr/bin/true`), and start, owner EOF and teardown (`/bin/cat`). The driver forks and runs the guardian's `main` in the child, so the guardian's own `exec` is not measured; the SDK child's is.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/custody.cpp`

## Results

|       ns/round trip |        round trip/s |    err% |     total | custody relay |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|           14,684.82 |           68,097.52 |    0.2% |      0.58 | `256 B line through the guardian and /bin/cat` |

|             ns/byte |              byte/s |    err% |     total | custody relay throughput |
|--------------------:|--------------------:|--------:|----------:|:------------------------- |
|                0.43 |    2,306,260,748.19 |    3.3% |      0.61 | `64 KiB burst through the guardian and /bin/cat` |

|          ns/session |           session/s |    err% |     total | custody sessions |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|        1,507,382.55 |              663.40 |    1.4% |      0.35 | `start, SDK exit and reap (/usr/bin/true)` |
|        1,580,025.00 |              632.90 |    1.2% |      0.40 | `start, owner EOF and teardown (/bin/cat)` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
