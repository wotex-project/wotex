# State report streams

The State subscriptions of the Thread host (`priv/openthread/streams.hpp` over the report credit of `priv/openthread/flow.hpp`): one coalesced snapshot flush to one stream and to 64 streams (the live-stream limit), each followed by the acknowledgement of its reports; 64 flushes to one stream, of which 48 reports wait in the queue and are drained by four acknowledgements; and the lifecycle of one subscription: opening, its initial report and removal, or opening and five reports under a `queue_limit` of 2, whose overflow ends the stream with a `stream_error` frame and its retirement barrier. Reports carry a six-field State snapshot and are about 300 encoded bytes. The unit is one report, or one subscription for the lifecycle.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/state_streams.cpp`

## Results

|           ns/report |            report/s |    err% |     total | State reports |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|            2,131.33 |          469,190.75 |    3.6% |      0.19 | `1 flush to 1 stream, acknowledged` |
|            1,532.47 |          652,540.71 |    0.5% |      0.24 | `1 flush to 64 streams, acknowledged` |
|            2,857.59 |          349,944.94 |    0.5% |      0.24 | `64 flushes to 1 stream, 48 queued, drained by 4 acknowledgements` |

|     ns/subscription |      subscription/s |    err% |     total | State subscriptions |
|--------------------:|--------------------:|--------:|----------:|:-------------------- |
|            3,176.47 |          314,814.54 |    0.4% |      0.24 | `open, initial report, remove, acknowledged` |
|           12,595.54 |           79,393.15 |    0.7% |      0.24 | `open, 5 reports with queue_limit 2, overflow, acknowledged` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
