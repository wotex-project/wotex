use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
    time::{SystemTime, UNIX_EPOCH},
};

fn private_directory() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "wotex-reference-runner-test-{}-{nonce}",
        std::process::id()
    ));
    fs::create_dir(&path).unwrap();
    path
}

fn run(root: &Path, wall_ms: u64, output_bytes: u64, command: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_wotex-reference-runner"))
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

#[test]
fn receipt_binds_success_and_exact_output() {
    let root = private_directory();
    let result = run(&root, 1_000, 1_024, &["/bin/sh", "-c", "printf ok"]);

    assert!(result.status.success());
    assert_eq!(
        String::from_utf8(result.stdout).unwrap(),
        "WOTEX_REFERENCE_RUNNER cleanup=ok outcome=exit status=0 output_bytes=2\nok"
    );
    assert!(result.stderr.is_empty());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn timeout_kills_and_reaps_the_child_process_group() {
    let root = private_directory();
    let result = run(
        &root,
        100,
        1_024,
        &[
            "/bin/sh",
            "-c",
            "sleep 60 & child=$!; printf '%s' \"$child\" > child.pid; wait \"$child\"",
        ],
    );

    assert_eq!(result.status.code(), Some(124));
    assert!(String::from_utf8(result.stdout).unwrap().starts_with(
        "WOTEX_REFERENCE_RUNNER cleanup=ok outcome=timeout status=124 output_bytes=0\n"
    ));

    let pid: i32 = fs::read_to_string(root.join("child.pid"))
        .unwrap()
        .parse()
        .unwrap();
    assert_eq!(unsafe { libc::kill(pid, 0) }, -1);
    assert_eq!(
        std::io::Error::last_os_error().raw_os_error(),
        Some(libc::ESRCH)
    );
    fs::remove_dir_all(root).unwrap();
}
