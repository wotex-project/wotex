# Bridge frame parsing and encoding

Bounded parsing of the owner's lines by the Thread host (`priv/openthread/protocol.hpp`): `parse_line` followed by the exact envelope checks of `request` for `inspect`, `subscribe_state` and `management_active_set` requests (the last carrying the 80-byte active Dataset of the contract fixture) and of `flow_control` for `flow_open` and `report_ack` frames; the rejection of a request with a duplicate key; and lines at the parser's limits, 4096 JSON values in 8 KiB and a 128 KiB string. The host parses each inbound line twice, in its guardian and in its worker. Encoding of the host's `ready`, `success` (with a State snapshot) and `failure` frames. The unit is one frame; each row names the line's size.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/protocol_frames.cpp`

## Results

|            ns/frame |             frame/s |    err% |     total | inbound frames |
|--------------------:|--------------------:|--------:|----------:|:--------------- |
|            1,043.04 |          958,735.18 |    4.8% |      0.19 | `inspect request, 80 B` |
|            1,165.40 |          858,074.91 |    0.6% |      0.24 | `subscribe_state request, 104 B` |
|            1,927.32 |          518,854.30 |    0.5% |      0.24 | `management_active_set request, 240 B` |
|              791.74 |        1,263,047.52 |    0.6% |      0.24 | `flow_open control, 90 B` |
|            1,243.53 |          804,161.55 |    0.5% |      0.24 | `report_ack control, 139 B` |
|            8,599.82 |          116,281.44 |    0.6% |      0.24 | `duplicate key rejected, 87 B` |
|          100,810.23 |            9,919.63 |    0.2% |      0.24 | `4096 values, node limit, 8192 B` |
|          339,286.31 |            2,947.36 |    0.4% |      0.24 | `string, line limit, 131072 B` |

|            ns/frame |             frame/s |    err% |     total | outbound frames |
|--------------------:|--------------------:|--------:|----------:|:---------------- |
|              701.33 |        1,425,860.02 |    0.5% |      0.24 | `ready, 106 B` |
|              934.58 |        1,070,000.30 |    0.5% |      0.24 | `success with a State snapshot, 156 B` |
|              680.72 |        1,469,043.46 |    0.6% |      0.24 | `failure with an error code, 58 B` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
