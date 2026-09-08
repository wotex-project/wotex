// Explicit test-only target. Never compiled into the production helper.
use serde_json::{json, Value};
use std::{
    io::{self, BufRead, Write},
    process::Command,
    time::Duration,
};

fn main() -> io::Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("detached-child") {
        record_pid(&args[1], std::process::id())?;
        std::thread::sleep(Duration::from_secs(30));
        return Ok(());
    }
    let mut line = String::new();
    io::stdin().lock().read_line(&mut line)?;
    let request: Value = serde_json::from_str(&line)?;
    let id = request["vector"]["id"].as_str().unwrap();
    let mut vector = id;
    let actual = match args[0].as_str() {
        "probe" => {
            let outside_write = if std::fs::write(&args[1], "escaped").is_ok() {
                "available"
            } else {
                "denied"
            };
            let home = std::path::PathBuf::from(std::env::var_os("HOME").unwrap());
            std::fs::write(home.join("private-write"), "admitted")?;
            // UDP connect checks route admission without sending a packet. A
            // private Linux network namespace may permit local socket creation.
            let network = if std::net::UdpSocket::bind("0.0.0.0:0")
                .and_then(|socket| socket.connect("192.0.2.1:9"))
                .is_ok()
            {
                "available"
            } else {
                "denied"
            };
            let mut cpu: libc::rlimit = unsafe { std::mem::zeroed() };
            let mut files: libc::rlimit = unsafe { std::mem::zeroed() };
            unsafe {
                libc::getrlimit(libc::RLIMIT_CPU, &mut cpu);
                libc::getrlimit(libc::RLIMIT_NOFILE, &mut files);
            }
            json!({"network": network, "outside_write": outside_write,
                "private_cwd": std::fs::canonicalize(std::env::current_dir()?)? == std::fs::canonicalize(&home)?,
                "private_write": home.join("private-write").is_file(),
                "cpu_seconds": cpu.rlim_cur, "open_files": files.rlim_cur})
        }
        "descendant" | "normal-child" => {
            let child = Command::new("/bin/sleep").arg("30").spawn()?;
            record_pid(&args[1], child.id())?;
            if args[0] == "descendant" {
                std::thread::sleep(Duration::from_secs(30));
            }
            json!({})
        }
        "escaped" => {
            use std::os::unix::process::CommandExt;
            let mut child = Command::new(std::env::current_exe()?);
            child.args(["detached-child", &args[1]]);
            unsafe {
                child.pre_exec(|| {
                    if libc::setsid() == -1 {
                        Err(io::Error::last_os_error())
                    } else {
                        Ok(())
                    }
                });
            }
            child.spawn()?;
            std::thread::sleep(Duration::from_millis(100));
            json!({})
        }
        "cpu" => loop {
            std::hint::black_box(123456u64.wrapping_mul(654321));
        },
        "memory" => {
            let memory = vec![42u8; 64 * 1024 * 1024];
            std::hint::black_box(&memory);
            std::thread::sleep(Duration::from_secs(30));
            json!({})
        }
        "processes" => {
            Command::new("/bin/sleep").arg("30").spawn()?;
            std::thread::sleep(Duration::from_secs(30));
            json!({})
        }
        "malformed" => {
            println!("{{");
            return Ok(());
        }
        "wrong-vector" => {
            vector = "other";
            json!({})
        }
        "crash" => std::process::exit(42),
        "oversized" => {
            io::stdout().write_all(&vec![b'x'; 2_000_000])?;
            return Ok(());
        }
        "concurrent" => {
            std::fs::write("marker", id)?;
            std::thread::sleep(Duration::from_millis(50));
            json!({"marker": std::fs::read_to_string("marker")?})
        }
        _ => return Err(io::Error::other("unknown test probe")),
    };
    println!(
        "{}",
        json!({"protocol": "wotex.conformance.target", "protocol_version": "1.0",
        "vector_id": vector, "outcome": "observed", "actual": actual, "codes": []})
    );
    Ok(())
}

fn record_pid(path: &str, pid: u32) -> io::Result<()> {
    #[cfg(target_os = "linux")]
    let text = format!(
        "{pid}@{}",
        std::fs::read_link("/proc/self/ns/pid")?.to_string_lossy()
    );
    #[cfg(not(target_os = "linux"))]
    let text = pid.to_string();
    std::fs::write(path, text)
}
