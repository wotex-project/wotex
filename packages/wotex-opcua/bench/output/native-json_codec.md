# Strict JSON reader

`wop_json_read` of the OPC UA host (`priv/native/json_codec.c` over the vendored yyjson 0.12.0) on request frames the BEAM host writes: a Read, an `open` carrying 2048-bit RSA credential envelopes, a Write of 1024 Doubles, a Write of a 64 KiB ByteString and a request whose parameters hold 1024 keys, the container limit, at which the duplicate-key check compares every key with each preceding one. Each parse uses one 2 MiB pool and releases its document; the unit is one frame. The exact number readers (`wop_json_double`, `wop_json_float`, `wop_json_int64`, `wop_json_uint64`) run over the 1024 raw tokens of a parsed Double or Int64 array; their unit is one token.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/json_codec.cpp`

## Results

|            ns/frame |             frame/s |    err% |     total | wop_json_read |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|              111.23 |        8,990,579.49 |    3.2% |      0.19 | `read request, 192 B` |
|            1,486.10 |          672,904.08 |    0.1% |      0.24 | `open request, 2048-bit RSA credentials, 6698 B` |
|           15,686.53 |           63,748.96 |    2.1% |      0.24 | `write request, 1024 Doubles, 7802 B` |
|           17,027.95 |           58,726.99 |    0.4% |      0.24 | `write request, 64 KiB ByteString, 87653 B` |
|        1,007,400.35 |              992.65 |    0.8% |      0.24 | `1024-key object, duplicate-key limit, 10362 B` |

|            ns/token |             token/s |    err% |     total | number readers |
|--------------------:|--------------------:|--------:|----------:|:--------------- |
|                6.97 |      143,519,919.46 |    1.1% |      0.23 | `wop_json_double, 1024 Double tokens` |
|                7.59 |      131,719,997.43 |    0.9% |      0.23 | `wop_json_float, 1024 Double tokens` |
|               10.54 |       94,882,023.94 |    0.4% |      0.24 | `wop_json_int64, 1024 Int64 tokens` |
|               10.46 |       95,647,974.68 |    1.9% |      0.24 | `wop_json_uint64, 1024 Int64 tokens` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
