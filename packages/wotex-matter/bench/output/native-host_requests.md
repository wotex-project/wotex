# Matter host request dispatch

`HostProtocol::ProcessLine` of the Matter controller host (`native/src/protocol.cpp`) for one request line of each kind: the bounded JSON parse, envelope, request-id and parameter validation, the call into the controller backend and the encoded reply frame. The requests are a health check, a read of OnOff, a batch read of the four Descriptor attributes on four endpoints, writes of a Thermostat setpoint and of a four-entry Access Control List, and an OnOff Toggle invocation. A scripted backend answers as a node would, so the rows measure the host's JSON and TLV handling around the SDK. The unit is one request.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/host_requests.cpp`

## Results

|          ns/request |           request/s |    err% |     total | host request |
|--------------------:|--------------------:|--------:|----------:|:------------- |
|            2,520.42 |          396,758.93 |    4.6% |      0.20 | `health` |
|            5,402.40 |          185,102.76 |    2.2% |      0.24 | `read OnOff` |
|          106,207.70 |            9,415.51 |    1.9% |      0.24 | `read_paths Descriptor 4 endpoints x 4 attributes` |
|            5,256.70 |          190,233.48 |    2.7% |      0.24 | `write Thermostat setpoint` |
|           48,448.24 |           20,640.58 |    1.6% |      0.24 | `write ACL 4 entries x 4 subjects` |
|            4,605.22 |          217,145.08 |    2.4% |      0.24 | `invoke OnOff Toggle` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
