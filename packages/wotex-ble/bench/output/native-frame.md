# Protocol-v1 framing and bounded JSON

Protocol-v1 framing of the native host (`priv/bluez/native/frame.hpp`): the bounded parse of one request line (health, read, a write carrying a 512-byte value, and a line of the 131,072-byte maximum), the rejection of an array beyond the 1,024-entry bound, and the host's admission path for 256 pipelined requests: 8 KiB reads through the incremental line decoder, the bounded parse and the dispatch-sequence check. The unit is one line.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/frame.cpp`

## Results

|             ns/line |              line/s |    err% |     total | protocol-v1 framing |
|--------------------:|--------------------:|--------:|----------:|:-------------------- |
|              534.86 |        1,869,650.25 |    1.9% |      0.20 | `parse health request (78 B)` |
|            1,497.33 |          667,856.50 |    1.7% |      0.23 | `parse read request (295 B)` |
|            3,744.71 |          267,043.43 |    1.6% |      0.24 | `parse write request, 512 B value (1017 B)` |
|          340,031.25 |            2,940.91 |    0.2% |      0.24 | `parse maximal string line (131072 B)` |
|           31,969.12 |           31,280.19 |    1.4% |      0.24 | `reject 1,025-entry array (4017 B)` |
|            1,655.85 |          603,920.34 |    0.8% |      0.24 | `admit 256 pipelined requests from 8 KiB reads` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
