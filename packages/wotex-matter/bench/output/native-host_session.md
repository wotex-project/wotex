# Matter host session round trips

Request round trips through a complete session of the Matter controller host: `RunHost` (`native/src/protocol.cpp`) reads frames from its input pipe through `BoundedInput` (`native/include/wotex_matter/input.hpp`), dispatches them and hands each reply to its bounded output writer thread, which writes it to the output pipe. A second thread drives the session as the BEAM Port does, one request at a time: it reads the ready frame, opens the controller, sends 256 health checks, OnOff reads or Thermostat setpoint writes, reading each reply before the next request, and closes. A scripted backend answers the interactions. The unit is one request round trip; the session set-up is amortised over its 256 requests.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/host_session.cpp`

## Results

|          ns/request |           request/s |    err% |     total | host session |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|            9,157.52 |          109,199.84 |    0.7% |      0.57 | `256 health round trips` |
|           16,008.27 |           62,467.73 |    0.3% |      0.60 | `256 OnOff read round trips` |
|           16,217.33 |           61,662.45 |    0.2% |      0.60 | `256 setpoint write round trips` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
