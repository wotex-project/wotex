mod accounting;
mod config;

use config::Config;
use std::{
    collections::BTreeMap,
    ffi::{CString, OsString},
    fs::OpenOptions,
    io::{self, Read, Seek, SeekFrom, Write},
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::OpenOptionsExt,
        process::CommandExt,
    },
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::atomic::{AtomicI32, Ordering},
    time::{Duration, Instant},
};

static TERMINATION: AtomicI32 = AtomicI32::new(0);

extern "C" fn signal(number: i32) {
    TERMINATION.store(number, Ordering::Relaxed);
}

fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args == [OsString::from("--version")] {
        println!("wotex-contained-exec {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    let code = match Config::parse(args)
        .and_then(|config| run(config).map_err(|error| failure_reason(&error)))
    {
        Ok(code) => code,
        Err(message) => {
            eprintln!("{message}");
            125
        }
    };
    std::process::exit(code);
}

fn failure_reason(error: &io::Error) -> &'static str {
    // Only static diagnostic classes leave the supervisor; never paths, argv,
    // environment values or target-controlled operating-system text.
    match error.to_string().as_str() {
        "root accounting unavailable" => "root accounting unavailable",
        "descendant cleanup incomplete" => "descendant cleanup incomplete",
        "descendant identity budget exceeded" => "descendant identity budget exceeded",
        "process enumeration unavailable or oversized" => {
            "process enumeration unavailable or oversized"
        }
        _ => "native containment operation failed",
    }
}

struct Directory {
    path: PathBuf,
    live: bool,
}

impl Directory {
    fn new(parent: &std::path::Path) -> io::Result<Self> {
        let template = parent.join("run-XXXXXX");
        let mut bytes = CString::new(template.as_os_str().as_bytes())?.into_bytes_with_nul();
        // SAFETY: mkdtemp mutates a writable NUL-terminated template in place.
        if unsafe { libc::mkdtemp(bytes.as_mut_ptr().cast()) }.is_null() {
            return Err(io::Error::last_os_error());
        }
        bytes.pop();
        Ok(Self {
            path: PathBuf::from(OsString::from_vec(bytes)),
            live: true,
        })
    }

    fn remove(&mut self) -> io::Result<()> {
        std::fs::remove_dir_all(&self.path)?;
        self.live = false;
        Ok(())
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        if self.live {
            let _ = self.remove();
        }
    }
}

fn run(config: Config) -> io::Result<i32> {
    for number in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP] {
        // SAFETY: the handler only stores a lock-free atomic integer; no I/O,
        // allocation, locks or process-tree discovery runs in signal context.
        if unsafe { libc::signal(number, signal as *const () as libc::sighandler_t) }
            == libc::SIG_ERR
        {
            return Err(io::Error::last_os_error());
        }
    }
    let parent = unsafe { libc::getppid() };
    let mut directory = Directory::new(&config.temp_dir)?;
    let output_path = directory.path.join("output");
    let mut output = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&output_path)?;
    // The output file has no pathname in the target's private directory.
    std::fs::remove_file(output_path)?;
    let mut command = Command::new(&config.command[0]);
    command
        .args(&config.command[1..])
        .current_dir(&directory.path)
        .env("HOME", &directory.path)
        .env("TMPDIR", &directory.path)
        .stdin(Stdio::inherit())
        .stdout(output.try_clone()?)
        .stderr(output.try_clone()?);
    let limits = config.clone();
    // SAFETY: pre_exec only invokes async-signal-safe setsid/setrlimit calls,
    // using copied scalar inputs, and returns OS errors without allocation.
    unsafe {
        command.pre_exec(move || {
            if libc::setsid() == -1 {
                return Err(io::Error::last_os_error());
            }
            for (resource, value) in [
                (libc::RLIMIT_CPU, limits.cpu_seconds),
                (libc::RLIMIT_NOFILE, limits.open_files),
                (libc::RLIMIT_FSIZE, limits.file_size_bytes),
                (libc::RLIMIT_CORE, 0),
            ] {
                let bound = libc::rlimit {
                    rlim_cur: value as libc::rlim_t,
                    rlim_max: value as libc::rlim_t,
                };
                if libc::setrlimit(resource, &bound) == -1 {
                    return Err(io::Error::last_os_error());
                }
            }
            Ok(())
        });
    }
    let mut child = command.spawn()?;
    let root = child.id() as i32;
    let mut known = BTreeMap::new();
    let outcome = supervise(&mut child, &config, parent, &mut known);
    // Cleanup is unconditional, including success, target crash and observation
    // failure. The unreaped root reserves its PID while its group is signalled.
    // SAFETY: WNOWAIT leaves the owned child unreaped, so its PID/group number
    // cannot have been reused even if it has exited or observation failed.
    unsafe {
        libc::kill(-root, libc::SIGKILL);
    }
    let _ = child.kill();
    let cleaned = cleanup(root, &mut known);
    let _ = child.wait();
    let removed = directory.remove();
    let code = outcome?;
    cleaned?;
    removed?;
    if code == 0 {
        if output.metadata()?.len() > config.file_size_bytes {
            return Ok(125);
        }
        output.seek(SeekFrom::Start(0))?;
        let mut bounded = output.take(config.file_size_bytes);
        let mut stdout = io::stdout().lock();
        io::copy(&mut bounded, &mut stdout)?;
        stdout.flush()?;
    }
    Ok(code)
}

fn supervise(
    child: &mut Child,
    config: &Config,
    parent: i32,
    known: &mut BTreeMap<i32, u64>,
) -> io::Result<i32> {
    let root = child.id() as i32;
    let deadline = Instant::now() + Duration::from_millis(config.wall_ms);
    loop {
        let (rows, status) = observe_with(root, accounting::rows, || exit_status(root))?;
        let tree = accounting::selected(&rows, root, known);
        remember(&tree, known)?;
        let termination = TERMINATION.load(Ordering::Relaxed);
        if termination != 0 {
            return Ok(128 + termination);
        }
        if unsafe { libc::getppid() } != parent {
            return Ok(125);
        }
        if tree.iter().filter(|row| !row.zombie).count() > config.processes {
            return Ok(123);
        }
        if tree
            .iter()
            .fold(0u64, |sum, row| sum.saturating_add(row.rss))
            > config.memory_bytes
        {
            return Ok(122);
        }
        if let Some(status) = status {
            return Ok(status);
        }
        if Instant::now() >= deadline {
            return Ok(124);
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn observe_with(
    root: i32,
    mut read: impl FnMut() -> io::Result<Vec<accounting::Row>>,
    mut status: impl FnMut() -> io::Result<Option<i32>>,
) -> io::Result<(Vec<accounting::Row>, Option<i32>)> {
    // libproc may omit task accounting during exec. Retry the observation at
    // most twice with a 1 ms pause; never turn absent accounting into zero RSS
    // or retry indefinitely. An exited root remains reserved by WNOWAIT.
    for attempt in 0..3 {
        let rows = read()?;
        let exit = status()?;
        if exit.is_some() || rows.iter().any(|row| row.pid == root) {
            return Ok((rows, exit));
        }
        if attempt < 2 {
            std::thread::sleep(Duration::from_millis(1));
        }
    }
    Err(io::Error::other("root accounting unavailable"))
}

fn exit_status(root: i32) -> io::Result<Option<i32>> {
    // SAFETY: siginfo_t is initialized and the kernel receives its actual type.
    // WNOWAIT is essential: retain the child's PID until group cleanup finishes.
    let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
    let result = unsafe {
        libc::waitid(
            libc::P_PID,
            root as libc::id_t,
            &mut info,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        )
    };
    if result == -1 {
        return Err(io::Error::last_os_error());
    }
    if unsafe { info.si_pid() } == 0 {
        return Ok(None);
    }
    let status = unsafe { info.si_status() };
    Ok(Some(if info.si_code == libc::CLD_EXITED {
        status
    } else {
        128 + status
    }))
}

fn cleanup(root: i32, known: &mut BTreeMap<i32, u64>) -> io::Result<()> {
    let deadline = Instant::now() + Duration::from_millis(150);
    loop {
        let rows = accounting::rows()?;
        let tree = accounting::selected(&rows, root, known);
        remember(&tree, known)?;
        // Signal only observed identities. Never blindly kill a historical PID
        // which could now belong to another process. A live group member pins
        // its group identity even after the group leader has exited.
        if tree.iter().any(|row| row.group == root) {
            unsafe {
                libc::kill(-root, libc::SIGKILL);
            }
        }
        for row in tree.iter().filter(|row| !row.zombie) {
            unsafe {
                libc::kill(row.pid, libc::SIGKILL);
            }
        }
        if tree.iter().all(|row| row.zombie) {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(io::Error::other("descendant cleanup incomplete"));
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn remember(tree: &[accounting::Row], known: &mut BTreeMap<i32, u64>) -> io::Result<()> {
    for row in tree {
        if known.len() == accounting::MAX_ROWS && !known.contains_key(&row.pid) {
            return Err(io::Error::other("descendant identity budget exceeded"));
        }
        known.insert(row.pid, row.birth);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transient_exec_accounting_has_a_finite_retry_not_a_zero_sample() {
        let mut reads = 0;
        let (rows, status) = observe_with(
            42,
            || {
                reads += 1;
                Ok(if reads < 3 {
                    vec![]
                } else {
                    vec![accounting::Row {
                        pid: 42,
                        parent: 1,
                        group: 42,
                        birth: 1,
                        rss: 99,
                        zombie: false,
                    }]
                })
            },
            || Ok(None),
        )
        .unwrap();
        assert_eq!(reads, 3);
        assert_eq!(rows[0].rss, 99);
        assert!(status.is_none());
    }

    #[test]
    fn persistent_missing_accounting_fails_and_exited_roots_do_not_retry() {
        let mut reads = 0;
        assert!(observe_with(
            42,
            || {
                reads += 1;
                Ok(vec![])
            },
            || Ok(None)
        )
        .is_err());
        assert_eq!(reads, 3);
        assert_eq!(
            observe_with(42, || Ok(vec![]), || Ok(Some(0))).unwrap().1,
            Some(0)
        );
    }
}
