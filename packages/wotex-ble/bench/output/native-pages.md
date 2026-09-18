# Discovery pages

Discovery paging (`priv/bluez/native/pages.hpp`): parsing of the page request and construction of the bounded page reply, which re-encodes the reply after each added characteristic to stay within the frame bound, for a 16-characteristic snapshot in one page, the first 64-entry page of 256 characteristics with a new cursor, and a walk of the 1,024-characteristic maximum in 16 pages. Each snapshot is a new discovery generation; cursor tokens come from a counter instead of the host's OS random source. The unit is one page.

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: Homebrew clang version 23.1.1
- Build: `-O2 -DNDEBUG`, nanobench 4.6.0
- Source: `bench/native/pages.cpp`

## Results

|             ns/page |              page/s |    err% |     total | discovery pages |
|--------------------:|--------------------:|--------:|----------:|:---------------- |
|          192,532.71 |            5,193.92 |    3.2% |      0.20 | `one page of 16 characteristics` |
|        2,377,819.44 |              420.55 |    0.6% |      0.25 | `first page of 256 characteristics, new cursor` |
|        2,380,203.12 |              420.13 |    0.2% |      0.42 | `walk 1,024 characteristics in 16 pages` |

nanobench's columns: the time and the rate per unit, `err%` the median absolute percentage error across epochs, and `total` the seconds the benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable.
