#[path = "../accounting.rs"]
mod accounting;

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
    path::{Path, PathBuf},
    process::{Child, Command},
    sync::atomic::{AtomicI32, Ordering},
    time::{Duration, Instant},
};

const MAX_WALL_MS: u64 = 1_800_000;
const MAX_OUTPUT_BYTES: u64 = 8_388_608;
const MAX_MEMORY_BYTES: u64 = 34_359_738_368;
const CLEANUP_MS: u64 = 2_000;
const MAX_ARGUMENTS: usize = 128;

static TERMINATION: AtomicI32 = AtomicI32::new(0);

extern "C" fn signal(number: i32) {
    TERMINATION.store(number, Ordering::Relaxed);
}

fn main() {
    let result = Config::parse(std::env::args_os().skip(1).collect()).and_then(run);

    let code = match result {
        Ok(code) => code,
        Err(error) => {
            eprintln!("reference runner failed: {}", classify(&error));
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
    temp_dir: PathBuf,
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

        if !PathBuf::from(&command[0]).is_absolute() {
            return invalid();
        }

        Ok(Self {
            wall_ms,
            output_bytes,
            work_dir,
            temp_dir,
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
    if path.is_absolute() && path.is_dir() {
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
        let template = parent.join("reference-run-XXXXXX");
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
    let mut private = PrivateDirectory::new(&config.temp_dir)?;
    let output_path = private.path.join("output");
    let mut output = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&output_path)?;
    std::fs::remove_file(output_path)?;

    let mut command = Command::new(&config.command[0]);
    command
        .args(&config.command[1..])
        .current_dir(&config.work_dir)
        .stdout(output.try_clone()?)
        .stderr(output.try_clone()?);

    let output_limit = config.output_bytes;
    // SAFETY: pre_exec calls only async-signal-safe setsid/setrlimit operations.
    unsafe {
        command.pre_exec(move || {
            if libc::setsid() == -1 {
                return Err(io::Error::last_os_error());
            }

            for (resource, value) in [
                (libc::RLIMIT_FSIZE, output_limit),
                (libc::RLIMIT_CORE, 0),
                (libc::RLIMIT_NOFILE, 2048),
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

    // Cleanup is unconditional. The root remains unreaped so its process-group
    // identity cannot be reused before every observed descendant is gone.
    unsafe {
        libc::kill(-root, libc::SIGKILL);
    }
    let _ = child.kill();
    let cleaned = cleanup(root, &mut known);
    let _ = child.wait();
    let removed = private.remove();

    let outcome = outcome?;
    cleaned?;
    removed?;

    let size = output.metadata()?.len().min(config.output_bytes);
    let (kind, status) = match outcome {
        Outcome::Exit(status) => ("exit", status),
        Outcome::Timeout => ("timeout", 124),
        Outcome::ParentLost => ("parent_lost", 125),
        Outcome::Signalled(signal) => ("signal", 128 + signal),
    };

    let mut stdout = io::stdout().lock();
    writeln!(
        stdout,
        "WOTEX_REFERENCE_RUNNER cleanup=ok outcome={kind} status={status} output_bytes={size}"
    )?;
    output.seek(SeekFrom::Start(0))?;
    io::copy(&mut output.take(size), &mut stdout)?;
    stdout.flush()?;
    Ok(status)
}

fn supervise(
    child: &mut Child,
    config: &Config,
    parent: i32,
    known: &mut BTreeMap<i32, u64>,
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
        if unsafe { libc::getppid() } != parent {
            return Ok(Outcome::ParentLost);
        }
        if tree.iter().filter(|row| !row.zombie).count() > 4096 {
            return Ok(Outcome::Exit(123));
        }
        if tree
            .iter()
            .fold(0u64, |sum, row| sum.saturating_add(row.rss))
            > MAX_MEMORY_BYTES
        {
            return Ok(Outcome::Exit(122));
        }
        if let Some(status) = exit_status(root)? {
            return Ok(Outcome::Exit(status));
        }
        if Instant::now() >= deadline {
            return Ok(Outcome::Timeout);
        }

        std::thread::sleep(Duration::from_millis(20));
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
    fn configuration_is_closed_and_bounded() {
        assert!(Config::parse(args()).is_ok());

        for value in ["0", "1800001", "-1", "nan"] {
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
