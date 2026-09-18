//! Criterion benchmarks of the in-process work of the containment launcher
//! (`priv/conformance/native`, `wotex-contained-exec`): admission of its
//! argument vector and resource budgets (`config.rs`), and the descendant
//! accounting of each supervision tick (`accounting.rs`), both over synthetic
//! process tables and over this host's own table. No contained child is
//! spawned. The launcher has binary targets only, so its modules are compiled
//! into this benchmark by path, unchanged.

use std::{collections::BTreeMap, ffi::OsString, hint::black_box};

use criterion::{criterion_group, criterion_main, BatchSize, BenchmarkId, Criterion, Throughput};

// Items the benchmark does not call stay unused here. `clippy --all-targets`
// checks a bench target with `cfg(test)` but without the test harness, so the
// launcher's test modules compile without their `#[test]` functions and their
// `use super::*` goes unused.
#[allow(dead_code, unused_imports)]
#[path = "../../../../priv/conformance/native/src/accounting.rs"]
mod accounting;
#[allow(dead_code, unused_imports)]
#[path = "../../../../priv/conformance/native/src/config.rs"]
mod config;

use accounting::Row;
use config::Config;

/// The processes of the contained tree `selected` must return.
const OWNED: usize = 16;

/// The argument vector of wotex-lab's default containment profile
/// (`Wotex.Lab.Conformance.Containment`): a 9 s inner wall clock, 8 CPU
/// seconds, 8 GiB, 64 processes, 128 descriptors and 1 MiB of output, then the
/// target command with `extra` arguments of `size` bytes each.
fn arguments(memory_bytes: &str, extra: usize, size: usize) -> Vec<OsString> {
    let temp_dir = std::env::temp_dir();
    let mut args: Vec<OsString> = [
        "--wall-ms",
        "9000",
        "--cpu-seconds",
        "8",
        "--memory-bytes",
        memory_bytes,
        "--processes",
        "64",
        "--open-files",
        "128",
        "--file-size-bytes",
        "1048576",
        "--temp-dir",
    ]
    .map(OsString::from)
    .to_vec();
    args.push(temp_dir.into_os_string());
    args.push("--".into());
    args.push("/usr/local/bin/wot-conformance-target".into());
    args.extend(
        (0..extra)
            .map(|index| "a".repeat(size - 1) + &(index % 10).to_string())
            .map(OsString::from),
    );
    args
}

fn admitted(args: Vec<OsString>) -> Config {
    let config = Config::parse(args).expect("the argument vector is admitted");
    assert!(config.wall_ms == 9_000 && config.cpu_seconds == 8 && config.processes == 64);
    assert!(config.memory_bytes == 8_589_934_592 && config.open_files == 128);
    assert!(config.file_size_bytes == 1_048_576 && config.temp_dir.is_absolute());
    config
}

fn bench_config(c: &mut Criterion) {
    let mut group = c.benchmark_group("config");
    let default = arguments("8589934592", 2, 16);
    let maximal = arguments("8589934592", 28, 4096);
    let over_budget = arguments("34359738369", 2, 16);
    assert_eq!(admitted(default.clone()).command.len(), 3);
    assert_eq!(admitted(maximal.clone()).command.len(), 29);
    assert_eq!(
        Config::parse(over_budget.clone()).err(),
        Some("number outside budget")
    );

    group.bench_function("parse default profile", |b| {
        b.iter_batched(|| default.clone(), admitted, BatchSize::SmallInput)
    });
    group.bench_function("parse maximal 29-element command of 4 KiB arguments", |b| {
        b.iter_batched(|| maximal.clone(), admitted, BatchSize::SmallInput)
    });
    group.bench_function("reject memory budget above the ceiling", |b| {
        b.iter_batched(
            || over_budget.clone(),
            |args| {
                let result = Config::parse(args);
                assert!(result.is_err());
                result
            },
            BatchSize::SmallInput,
        )
    });
    group.finish();
}

/// A deterministic host process table of `size` rows whose last `OWNED + 1`
/// rows are a contained tree rooted at the returned PID, and the identities an
/// earlier tick retained. The tree has the root, 7 members of its process
/// group, 4 descendants that left the group with their 2 children, and 2
/// reparented descendants known only from the earlier tick; one more row
/// reuses the PID of an exited descendant with another birth time and must
/// not be selected.
fn host_table(size: usize) -> (Vec<Row>, i32, BTreeMap<i32, u64>) {
    let row = |pid: i32, parent: i32, group: i32| Row {
        pid,
        parent,
        group,
        birth: 1_000 + pid as u64,
        rss: 4_194_304,
        zombie: false,
    };
    let unrelated = size - OWNED - 1;
    let mut rows = Vec::with_capacity(size);
    let mut state: u64 = 0x2545_f491_4f6c_dd1d;
    for index in 0..unrelated {
        let pid = index as i32 + 1;
        // A linear congruential choice of an earlier, unrelated parent.
        state = state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1);
        let parent = if pid == 1 {
            0
        } else {
            (state >> 33) as i32 % (pid - 1) + 1
        };
        let group = if state & 4 == 0 { pid } else { parent.max(1) };
        rows.push(row(pid, parent, group));
    }
    let root = unrelated as i32 + 1;
    rows.push(row(root, 1, root));
    for member in 1..=7 {
        rows.push(row(root + member, root, root));
    }
    for leader in 8..=11 {
        rows.push(row(root + leader, root + leader - 7, root + leader));
    }
    for child in 12..=13 {
        rows.push(row(root + child, root + child - 4, root + child - 4));
    }
    let mut known: BTreeMap<i32, u64> = rows[unrelated..]
        .iter()
        .map(|row| (row.pid, row.birth))
        .collect();
    for reparented in 14..=15 {
        let pid = root + reparented;
        rows.push(row(pid, 1, pid));
        known.insert(pid, 1_000 + pid as u64);
    }
    let reused = root + 16;
    rows.push(row(reused, 1, reused));
    known.insert(reused, 1);
    assert_eq!(rows.len(), size);
    (rows, root, known)
}

fn bench_selected(c: &mut Criterion) {
    let mut group = c.benchmark_group("accounting/selected");
    for size in [512, 4_096, accounting::MAX_ROWS - 1] {
        let (rows, root, known) = host_table(size);
        let tree = accounting::selected(&rows, root, &known);
        assert_eq!(tree.len(), OWNED);
        assert!(tree
            .iter()
            .all(|row| row.pid >= root && row.pid < root + OWNED as i32));
        group.throughput(Throughput::Elements(size as u64));
        group.bench_with_input(
            BenchmarkId::from_parameter(format!("{size} rows")),
            &size,
            |b, _| {
                b.iter(|| {
                    let tree = accounting::selected(black_box(&rows), root, black_box(&known));
                    assert_eq!(tree.len(), OWNED);
                    tree
                })
            },
        );
    }
    group.finish();
}

fn bench_rows(c: &mut Criterion) {
    let own = std::process::id() as i32;
    let observed = accounting::rows().expect("this host's process table is observable");
    assert!(observed.iter().any(|row| row.pid == own));
    let mut group = c.benchmark_group("accounting/rows");
    group.bench_function("this host", |b| {
        b.iter(|| {
            let rows = accounting::rows().expect("process enumeration");
            assert!(!rows.is_empty() && rows.len() < accounting::MAX_ROWS);
            rows
        })
    });
    group.finish();
}

criterion_group!(benches, bench_config, bench_selected, bench_rows);
criterion_main!(benches);
