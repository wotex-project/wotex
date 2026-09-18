# OSCORE context identity and store

The durable OSCORE context store of the native helper: deriving the storage identity of the RFC 8613 appendix C.1 client context (`native/oscore/identity.c`: three HKDF-SHA-256 derivations and three SHA-256 digests through OpenSSL), consuming that identity in a new private store directory (lock file, first registry write with `fsync(2)`, rename and directory `fsync(2)`), and reserving the next sequence boundary, which rewrites the registry the same way, in a store holding its own context only and in one holding 1,024 contexts (`store.c`). The stores live below the benchmark's scratch directory in the native cache, so the timings include that filesystem's `fsync(2)`.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/oscore_store.cpp`

## Results

|         ns/identity |          identity/s |    err% |     total | context store |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|            6,051.75 |          165,241.56 |    1.0% |      0.56 | `derive the storage identity` |

|            ns/store |             store/s |    err% |     total | context store |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|          279,178.88 |            3,581.93 |    1.2% |      0.60 | `consume an identity in a new store` |

|      ns/reservation |       reservation/s |    err% |     total | context store |
|--------------------:|--------------------:|--------:|----------:|:-------------- |
|          125,565.73 |            7,963.96 |    0.5% |      0.58 | `reserve a sequence boundary, 1 context` |
|          174,748.90 |            5,722.50 |    3.6% |      0.56 | `reserve a sequence boundary, 1,024 contexts` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
