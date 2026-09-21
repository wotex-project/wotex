#[path = "../accounting.rs"]
mod accounting;

use std::{
    collections::BTreeMap,
    ffi::{CString, OsString},
    io::{self, Read, Write},
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::PermissionsExt,
        process::CommandExt,
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicI32, Ordering},
        Arc,
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

const MAX_WALL_MS: u64 = 30_000;
const MAX_OUTPUT_BYTES: u64 = 262_144;
const MAX_MEMORY_BYTES: u64 = 1_073_741_824;
const MAX_PROCESSES: usize = 64;
const MAX_ARGUMENTS: usize = 16;
const CLEANUP_MS: u64 = 2_000;

static TERMINATION: AtomicI32 = AtomicI32::new(0);

extern "C" fn signal(number: i32) {
    TERMINATION.store(number, Ordering::Relaxed);
}

fn main() {
    let result = Config::parse(std::env::args_os().skip(1).collect()).and_then(run);

    let code = match result {
        Ok(code) => code,
        Err(error) => {
            eprintln!("hosted investigation runner failed: {}", classify(&error));
            125
        }
    };

    std::process::exit(code);
}

fn classify(error: &io::Error) -> &'static str {
    match error.to_string().as_str() {
        "descendant cleanup incomplete" => "descendant cleanup incomplete",
        "descendant identity budget exceeded" => "descendant identity budget exceeded",
        "process enumeration unavailable or oversized" => {
            "process enumeration unavailable or oversized"
        }
        "root accounting unavailable" => "root accounting unavailable",
        _ => "native runner operation failed",
    }
}

#[derive(Clone, Debug)]
struct Config {
    wall_ms: u64,
    output_bytes: u64,
    work_dir: PathBuf,
    command: Vec<OsString>,
}

impl Config {
    fn parse(args: Vec<OsString>) -> io::Result<Self> {
        if args.len() > MAX_ARGUMENTS || args.iter().any(|arg| arg.len() > 4096) {
            return invalid();
        }

        let split = args
            .iter()
            .position(|arg| arg == "--")
            .ok_or_else(invalid_error)?;
        if split != 8 || args.len() <= split + 1 {
            return invalid();
        }

        let mut fields = BTreeMap::new();
        for pair in args[..split].chunks_exact(2) {
            let key = pair[0].to_str().ok_or_else(invalid_error)?;
            if fields.insert(key, &pair[1]).is_some() {
                return invalid();
            }
        }

        let wall_ms = number(&fields, "--wall-ms", 1, MAX_WALL_MS)?;
        let output_bytes = number(&fields, "--output-bytes", 1, MAX_OUTPUT_BYTES)?;
        let work_dir = directory(&fields, "--work-dir")?;
        let temp_dir = directory(&fields, "--temp-dir")?;
        let command = args[split + 1..].to_vec();

        if work_dir != temp_dir || !PathBuf::from(&command[0]).is_absolute() {
            return invalid();
        }

        Ok(Self {
            wall_ms,
            output_bytes,
            work_dir,
            command,
        })
    }
}

fn number(
    fields: &BTreeMap<&str, &OsString>,
    key: &str,
    minimum: u64,
    maximum: u64,
) -> io::Result<u64> {
    let text = fields
        .get(key)
        .and_then(|value| value.to_str())
        .ok_or_else(invalid_error)?;

    if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
        return invalid();
    }

    let value = text.parse::<u64>().map_err(|_| invalid_error())?;
    if (minimum..=maximum).contains(&value) {
        Ok(value)
    } else {
        invalid()
    }
}

fn directory(fields: &BTreeMap<&str, &OsString>, key: &str) -> io::Result<PathBuf> {
    let path = PathBuf::from(fields.get(key).ok_or_else(invalid_error)?);
    let metadata = std::fs::symlink_metadata(&path)?;

    if path.is_absolute()
        && metadata.file_type().is_dir()
        && metadata.permissions().mode() & 0o077 == 0
    {
        Ok(path)
    } else {
        invalid()
    }
}

fn invalid<T>() -> io::Result<T> {
    Err(invalid_error())
}

fn invalid_error() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, "invalid arguments")
}

struct PrivateDirectory {
    path: PathBuf,
    live: bool,
}

impl PrivateDirectory {
    fn new(parent: &Path) -> io::Result<Self> {
        let template = parent.join("hosted-investigation-XXXXXX");
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

impl Drop for PrivateDirectory {
    fn drop(&mut self) {
        if self.live {
            let _ = self.remove();
        }
    }
}

#[derive(Clone, Copy, Debug)]
enum Outcome {
    Exit(i32),
    Timeout,
    ParentLost,
    Signalled(i32),
    MemoryLimit,
    ProcessLimit,
    OutputLimit,
}

fn run(config: Config) -> io::Result<i32> {
    for number in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP] {
        // SAFETY: the handler stores one lock-free atomic integer and performs no I/O.
        if unsafe { libc::signal(number, signal as *const () as libc::sighandler_t) }
            == libc::SIG_ERR
        {
            return Err(io::Error::last_os_error());
        }
    }

    let parent = unsafe { libc::getppid() };
    let mut private = PrivateDirectory::new(&config.work_dir)?;
    let mut command = Command::new(&config.command[0]);
    command
        .args(&config.command[1..])
        .current_dir(&private.path)
        .env("HOME", &private.path)
        .env("TMPDIR", &private.path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());

    let cpu_seconds = config.wall_ms.div_ceil(1_000).saturating_add(1);

    // SAFETY: pre_exec calls only async-signal-safe setsid/setrlimit operations.
    unsafe {
        command.pre_exec(move || {
            if libc::setsid() == -1 {
                return Err(io::Error::last_os_error());
            }

            for (resource, value) in [
                (libc::RLIMIT_CORE, 0),
                (libc::RLIMIT_NOFILE, 256),
                (libc::RLIMIT_CPU, cpu_seconds),
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
    let output_exceeded = Arc::new(AtomicBool::new(false));
    let output_reader = read_output(
        child.stdout.take().ok_or_else(invalid_error)?,
        config.output_bytes,
        Arc::clone(&output_exceeded),
    );
    let root = child.id() as i32;
    let mut known = BTreeMap::new();
    let outcome = supervise(&mut child, &config, parent, &mut known, &output_exceeded);

    // Cleanup is unconditional. The root remains unreaped so its process-group
    // identity cannot be reused before every observed descendant is gone.
    unsafe {
        libc::kill(-root, libc::SIGKILL);
    }
    let _ = child.kill();
    let cleaned = cleanup(root, &mut known);
    let _ = child.wait();
    let output = output_reader
        .join()
        .map_err(|_| io::Error::other("output reader failed"))??;
    let removed = private.remove();

    let mut outcome = outcome?;
    if output_exceeded.load(Ordering::Acquire) {
        outcome = Outcome::OutputLimit;
    }
    cleaned?;
    removed?;

    let size = output.len();
    let (kind, status) = match outcome {
        Outcome::Exit(status) => ("exit", status),
        Outcome::Timeout => ("timeout", 124),
        Outcome::ParentLost => ("parent_lost", 125),
        Outcome::Signalled(signal) => ("signal", 128 + signal),
        Outcome::MemoryLimit => ("memory_limit", 122),
        Outcome::ProcessLimit => ("process_limit", 123),
        Outcome::OutputLimit => ("output_limit", 121),
    };

    let mut stdout = io::stdout().lock();
    writeln!(
        stdout,
        "WOTEX_HOSTED_RUNNER cleanup=ok outcome={kind} status={status} output_bytes={size}"
    )?;
    stdout.write_all(&output)?;
    stdout.flush()?;
    Ok(status)
}

fn read_output(
    mut stdout: impl Read + Send + 'static,
    limit: u64,
    exceeded: Arc<AtomicBool>,
) -> JoinHandle<io::Result<Vec<u8>>> {
    std::thread::spawn(move || {
        let mut output = Vec::with_capacity(limit.min(65_536) as usize);
        let mut buffer = [0u8; 8_192];

        loop {
            match stdout.read(&mut buffer) {
                Ok(0) => return Ok(output),
                Ok(read) if output.len().saturating_add(read) <= limit as usize => {
                    output.extend_from_slice(&buffer[..read]);
                }
                Ok(_) => exceeded.store(true, Ordering::Release),
                Err(error) => return Err(error),
            }
        }
    })
}

fn supervise(
    child: &mut Child,
    config: &Config,
    parent: i32,
    known: &mut BTreeMap<i32, u64>,
    output_exceeded: &AtomicBool,
) -> io::Result<Outcome> {
    let root = child.id() as i32;
    let deadline = Instant::now() + Duration::from_millis(config.wall_ms);

    loop {
        let rows = accounting::rows()?;
        let tree = accounting::selected(&rows, root, known);
        remember(&tree, known)?;

        let signal = TERMINATION.load(Ordering::Relaxed);
        if signal != 0 {
            return Ok(Outcome::Signalled(signal));
        }
        if output_exceeded.load(Ordering::Acquire) {
            return Ok(Outcome::OutputLimit);
        }
        if unsafe { libc::getppid() } != parent {
            return Ok(Outcome::ParentLost);
        }
        if tree.iter().filter(|row| !row.zombie).count() > MAX_PROCESSES {
            return Ok(Outcome::ProcessLimit);
        }
        if tree
            .iter()
            .fold(0u64, |sum, row| sum.saturating_add(row.rss))
            > MAX_MEMORY_BYTES
        {
            return Ok(Outcome::MemoryLimit);
        }
        if let Some(status) = exit_status(root)? {
            return Ok(Outcome::Exit(status));
        }
        if Instant::now() >= deadline {
            return Ok(Outcome::Timeout);
        }

        std::thread::sleep(Duration::from_millis(10));
    }
}

fn exit_status(root: i32) -> io::Result<Option<i32>> {
    // SAFETY: siginfo_t is initialized and waitid receives its actual type.
    // WNOWAIT keeps the PID reserved until descendant cleanup is complete.
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
    let deadline = Instant::now() + Duration::from_millis(CLEANUP_MS);

    loop {
        let rows = accounting::rows()?;
        let tree = accounting::selected(&rows, root, known);
        remember(&tree, known)?;

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

        std::thread::sleep(Duration::from_millis(10));
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

    fn args() -> Vec<OsString> {
        [
            "--wall-ms",
            "1000",
            "--output-bytes",
            "1024",
            "--work-dir",
            "/tmp",
            "--temp-dir",
            "/tmp",
            "--",
            "/bin/echo",
            "ok",
        ]
        .map(OsString::from)
        .to_vec()
    }

    #[test]
    fn configuration_is_closed_and_hosted_limits_are_fixed() {
        assert!(Config::parse(args()).is_ok());
        assert_eq!(MAX_MEMORY_BYTES, 1_073_741_824);
        assert_eq!(MAX_PROCESSES, 64);

        for value in ["0", "30001", "-1", "nan"] {
            let mut changed = args();
            changed[1] = value.into();
            assert!(Config::parse(changed).is_err());
        }

        let mut relative = args();
        relative[9] = "echo".into();
        assert!(Config::parse(relative).is_err());

        let mut duplicate = args();
        duplicate[2] = "--wall-ms".into();
        assert!(Config::parse(duplicate).is_err());
    }
}
