# Settings storage lock

The settings storage of the Thread host (`priv/openthread/storage.hpp`): opening an existing owner-only directory and taking the exclusive `flock(2)` lock of its lock file, the refusal of a second owner while the lock is held, and the creation of a new directory with its lock file, removed again within each operation. The directories are in the benchmark's scratch directory in the native cache, on the file system of the system temporary directory unless `WOTEX_NATIVE_CACHE` names another. The unit is one open.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/settings_storage.cpp`

## Results

|             ns/open |              open/s |    err% |     total | settings storage |
|--------------------:|--------------------:|--------:|----------:|:----------------- |
|           19,215.60 |           52,041.05 |    1.7% |      0.22 | `open existing directory, take the lock, release` |
|           22,065.14 |           45,320.35 |    0.9% |      0.24 | `open refused while another owner holds the lock` |
|          113,827.32 |            8,785.24 |    2.0% |      0.24 | `create directory, take the lock, release, remove` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
