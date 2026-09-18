# Process owner request cycle

The process owner of the OPC UA host (`priv/native/owner.c` with the output queue, input framing and JSON reader) on an open Session. A request line is framed, parsed, admitted and prepared; the next tick dispatches it, completes it and emits the reply through the credited output queue to a nonblocking pipe; the driver reads each reply line and returns one credit control for it, as the BEAM host does. Both input lines of a request, the request and its credit, are parsed and the 2 MiB parser pool is erased after each. The SDK is replaced by an in-process service that completes every dispatched operation on the same tick and validates only the parameter object, so the rows measure the owner's own work: a Read, a Write of 1024 Doubles and 16 Reads coalesced in one input read. The unit is one request.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/owner.cpp`

## Results

|          ns/request |           request/s |    err% |     total | owner |
|--------------------:|--------------------:|--------:|----------:|:------ |
|          930,937.50 |            1,074.19 |    0.6% |      0.22 | `Read: request, tick, reply and credit` |
|          946,987.87 |            1,055.98 |    0.2% |      0.24 | `Write of 1024 Doubles (7408 B request)` |
|          928,169.25 |            1,077.39 |    0.1% |      0.24 | `16 pipelined Reads in one input read, one tick` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
