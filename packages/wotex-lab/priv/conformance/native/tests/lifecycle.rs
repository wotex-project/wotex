#![cfg(feature = "test-probes")]

use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, Instant},
};

static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Temporary(PathBuf);

impl Temporary {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "wotex-native-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
}

impl Drop for Temporary {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

fn spawn(home: &Path, mode: &str, extras: &[&str], limits: &[(&str, &str)]) -> Child {
    let mut options = vec![
        ("--wall-ms", "3000"),
        ("--cpu-seconds", "2"),
        ("--memory-bytes", "1073741824"),
        ("--processes", "64"),
        ("--open-files", "128"),
        ("--file-size-bytes", "1048576"),
    ];
    for (key, value) in limits {
        options.iter_mut().find(|(name, _)| name == key).unwrap().1 = value;
    }
    let mut command = Command::new(env!("CARGO_BIN_EXE_wotex-contained-exec"));
    for (key, value) in options {
        command.args([key, value]);
    }
    let mut child = command
        .arg("--temp-dir")
        .arg(home)
        .arg("--")
        .arg(env!("CARGO_BIN_EXE_containment-probe"))
        .arg(mode)
        .args(extras)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"{\"vector\":{\"id\":\"probe\"}}\n")
        .unwrap();
    child
}

fn await_file(path: &Path) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(pid) = fs::read_to_string(path)
            .ok()
            .and_then(|text| text.split('@').next()?.parse().ok())
        {
            return pid;
        }
        assert!(Instant::now() < deadline, "probe did not start");
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn stopped(pid: i32) -> bool {
    if unsafe { libc::kill(pid, 0) } == -1 {
        return true;
    }
    #[cfg(target_os = "linux")]
    if fs::read_to_string(format!("/proc/{pid}/stat")).is_ok_and(|stat| stat.contains(") Z ")) {
        return true;
    }
    false
}

fn assert_stopped(pid: i32) {
    let deadline = Instant::now() + Duration::from_secs(1);
    while !stopped(pid) {
        assert!(
            Instant::now() < deadline,
            "owned descendant survived cleanup"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn normal_exit_reaps_group_and_observed_session_escape() {
    for mode in ["normal-child", "escaped"] {
        let home = Temporary::new();
        let pid_path = home.0.join("child.pid");
        let child = spawn(&home.0, mode, &[pid_path.to_str().unwrap()], &[]);
        let pid = await_file(&pid_path);
        let output = child.wait_with_output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_stopped(pid);
        assert_eq!(fs::read_dir(&home.0).unwrap().count(), 1);
    }
}

#[test]
fn termination_signal_cleans_up_before_returning() {
    let home = Temporary::new();
    let pid_path = home.0.join("child.pid");
    let child = spawn(&home.0, "descendant", &[pid_path.to_str().unwrap()], &[]);
    let pid = await_file(&pid_path);
    // The helper is this test's unreaped child, not a caller-supplied PID.
    assert_eq!(unsafe { libc::kill(child.id() as i32, libc::SIGTERM) }, 0);
    assert_eq!(child.wait_with_output().unwrap().status.code(), Some(143));
    assert_stopped(pid);
    assert_eq!(fs::read_dir(&home.0).unwrap().count(), 1);
}

#[test]
fn wall_memory_and_process_limits_have_distinct_exit_codes() {
    for (mode, key, value, expected) in [
        ("cpu", "--wall-ms", "50", 124),
        ("memory", "--memory-bytes", "33554432", 122),
        ("processes", "--processes", "1", 123),
    ] {
        let home = Temporary::new();
        let output = spawn(&home.0, mode, &[], &[(key, value)])
            .wait_with_output()
            .unwrap();
        assert_eq!(output.status.code(), Some(expected));
        assert!(output.stdout.is_empty());
        assert_eq!(fs::read_dir(&home.0).unwrap().count(), 0);
    }
}

#[test]
fn output_file_limit_and_target_crash_do_not_become_successful_responses() {
    for mode in ["oversized", "crash"] {
        let home = Temporary::new();
        let output = spawn(&home.0, mode, &[], &[]).wait_with_output().unwrap();
        assert!(!output.status.success());
        assert!(output.stdout.is_empty());
        assert_eq!(fs::read_dir(&home.0).unwrap().count(), 0);
    }
}
