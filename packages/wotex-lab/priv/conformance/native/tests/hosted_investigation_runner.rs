#![cfg(feature = "test-probes")]

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, Instant},
};

static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Temporary(PathBuf);

impl Temporary {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "wotex-hosted-runner-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        Self(path)
    }
}

impl Drop for Temporary {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

fn run(root: &Path, wall_ms: u64, output_bytes: u64, command: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_wotex-hosted-investigation-runner"))
        .args([
            "--wall-ms",
            &wall_ms.to_string(),
            "--output-bytes",
            &output_bytes.to_string(),
            "--work-dir",
            root.to_str().unwrap(),
            "--temp-dir",
            root.to_str().unwrap(),
            "--",
        ])
        .args(command)
        .output()
        .unwrap()
}

fn raw(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_wotex-hosted-investigation-runner"))
        .args(args)
        .output()
        .unwrap()
}

fn assert_stopped(pid: i32) {
    let deadline = Instant::now() + Duration::from_secs(1);

    loop {
        if unsafe { libc::kill(pid, 0) } == -1 {
            assert_eq!(
                std::io::Error::last_os_error().raw_os_error(),
                Some(libc::ESRCH)
            );
            return;
        }

        assert!(
            Instant::now() < deadline,
            "owned descendant survived cleanup"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn configuration_is_exact_and_requires_private_equal_work_directories() {
    let root = Temporary::new();
    let other = Temporary::new();

    for output in [
        raw(&[]),
        raw(&[
            "--wall-ms",
            "1000",
            "--output-bytes",
            "64",
            "--work-dir",
            root.0.to_str().unwrap(),
            "--temp-dir",
            other.0.to_str().unwrap(),
            "--",
            env!("CARGO_BIN_EXE_containment-probe"),
        ]),
        raw(&[
            "--wall-ms",
            "1000",
            "--wall-ms",
            "64",
            "--work-dir",
            root.0.to_str().unwrap(),
            "--temp-dir",
            root.0.to_str().unwrap(),
            "--",
            env!("CARGO_BIN_EXE_containment-probe"),
        ]),
        raw(&[
            "--wall-ms",
            "1000",
            "--output-bytes",
            "64",
            "--work-dir",
            root.0.to_str().unwrap(),
            "--temp-dir",
            root.0.to_str().unwrap(),
            "--",
            "relative-command",
        ]),
    ] {
        assert_eq!(output.status.code(), Some(125));
        assert_eq!(
            String::from_utf8(output.stderr).unwrap(),
            "hosted investigation runner failed: native runner operation failed\n"
        );
    }

    fs::set_permissions(&root.0, fs::Permissions::from_mode(0o755)).unwrap();
    let output = run(
        &root.0,
        1_000,
        64,
        &[env!("CARGO_BIN_EXE_containment-probe")],
    );
    assert_eq!(output.status.code(), Some(125));
    fs::set_permissions(&root.0, fs::Permissions::from_mode(0o700)).unwrap();
}

#[test]
fn worker_uses_a_disposable_private_workspace_larger_than_its_output_budget() {
    let root = Temporary::new();
    let output = run(
        &root.0,
        1_000,
        64,
        &[
            env!("CARGO_BIN_EXE_containment-probe"),
            "hosted-private-workspace",
            root.0.to_str().unwrap(),
        ],
    );

    assert!(output.status.success());
    assert_eq!(fs::read_dir(&root.0).unwrap().count(), 0);
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        "WOTEX_HOSTED_RUNNER cleanup=ok outcome=exit status=0 output_bytes=3\nok\n"
    );
}

#[test]
fn output_and_wall_limits_are_distinct_and_cleanup_is_complete() {
    let root = Temporary::new();
    let oversized = run(
        &root.0,
        1_000,
        64,
        &[
            env!("CARGO_BIN_EXE_containment-probe"),
            "hosted-oversized-exit",
        ],
    );
    assert_eq!(oversized.status.code(), Some(121));
    assert!(String::from_utf8(oversized.stdout).unwrap().starts_with(
        "WOTEX_HOSTED_RUNNER cleanup=ok outcome=output_limit status=121 output_bytes="
    ));

    let pid_path = root.0.join("descendant.pid");
    let timed_out = run(
        &root.0,
        500,
        64,
        &[
            env!("CARGO_BIN_EXE_containment-probe"),
            "hosted-descendant",
            pid_path.to_str().unwrap(),
        ],
    );
    assert_eq!(timed_out.status.code(), Some(124));
    assert!(String::from_utf8(timed_out.stdout)
        .unwrap()
        .starts_with("WOTEX_HOSTED_RUNNER cleanup=ok outcome=timeout status=124 output_bytes=0\n"));
    let recorded = fs::read_to_string(pid_path).unwrap();
    let pid = recorded.split('@').next().unwrap().parse().unwrap();
    assert_stopped(pid);
}
