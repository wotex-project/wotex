# Subscription parameter rules

`priv/native/subscription_rules.c` of the OPC UA host: `wop_subscription_read` on the closed seven-key parameter map of a parsed subscribe request, accepted and rejected for a lifetime below three keepalives, and `wop_subscription_revision_valid` on server-revised parameters. The unit is one check.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/subscription_rules.cpp`

## Results

|            ns/check |             check/s |    err% |     total | subscription rules |
|--------------------:|--------------------:|--------:|----------:|:------------------- |
|               33.61 |       29,753,495.67 |    6.6% |      0.19 | :wavy_dash: `wop_subscription_read, accepted parameters` (Unstable with ~492,592.5 iters. Increase `minEpochIterations` to e.g. 4925925) |
|               31.22 |       32,030,482.89 |    0.6% |      0.24 | `wop_subscription_read, lifetime below three keepalives` |
|                1.13 |      888,888,032.06 |    0.4% |      0.24 | `wop_subscription_revision_valid, server revision` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
