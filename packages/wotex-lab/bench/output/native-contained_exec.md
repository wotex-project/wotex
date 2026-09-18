# Containment launcher admission and accounting

The in-process work of the containment launcher (`priv/conformance/native`, `wotex-contained-exec`), without a contained child: parsing and budget admission of the argument vector of the default containment profile, of the largest admitted command (29 elements of 4 KiB) and of a memory budget above the ceiling (`config.rs`); selection of the contained process tree (root, process group, descendants that left the group, reparented descendants retained from an earlier tick, one reused PID) from synthetic host process tables of 512, 4,096 and 65,535 rows, the largest table the launcher admits; and one observation of this host's process table, the enumeration each 10 ms supervision tick performs (`accounting.rs`: libproc on macOS, `/proc` on Linux).

## System

- Operating system: macOS 26.6.2 (Darwin 25.6.0 arm64)
- CPU: Apple M5 Pro, 18 logical processors
- Compiler: rustc 1.97.1 (8bab26f4f 2026-07-14)
- Build: `cargo bench` (bench profile), criterion 0.8.2
- Source: `bench/native/contained_exec/`

## Results

| Benchmark | Mean | Median | Std. dev. | Throughput |
| :-- | --: | --: | --: | --: |
| `accounting/rows/this host` | 569.5 µs | 568.3 µs | 6.390 µs | - |
| `accounting/selected/4096 rows` | 93.46 µs | 93.21 µs | 1.222 µs | 43.83 Melem/s |
| `accounting/selected/512 rows` | 10.29 µs | 10.28 µs | 106.0 ns | 49.75 Melem/s |
| `accounting/selected/65535 rows` | 3.586 ms | 3.585 ms | 28.43 µs | 18.27 Melem/s |
| `config/parse default profile` | 1.349 µs | 1.343 µs | 31.70 ns | - |
| `config/parse maximal 29-element command of 4 KiB arguments` | 6.662 µs | 6.684 µs | 1.183 µs | - |
| `config/reject memory budget above the ceiling` | 278.7 ns | 277.2 ns | 4.380 ns | - |

Mean, median and standard deviation of the time per iteration are criterion's bootstrap point estimates; throughput is the declared throughput per mean iteration time.
