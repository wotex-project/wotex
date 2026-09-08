use std::{collections::BTreeMap, ffi::OsString, path::PathBuf};

#[derive(Clone, Debug)]
pub struct Config {
    pub wall_ms: u64,
    pub cpu_seconds: u64,
    pub memory_bytes: u64,
    pub processes: usize,
    pub open_files: u64,
    pub file_size_bytes: u64,
    pub temp_dir: PathBuf,
    pub command: Vec<OsString>,
}

impl Config {
    pub fn parse(args: Vec<OsString>) -> Result<Self, &'static str> {
        if args.len() > 80 || args.iter().any(|arg| arg.len() > 4096) {
            return Err("argument budget exceeded");
        }
        let split = args
            .iter()
            .position(|arg| arg == "--")
            .ok_or("missing separator")?;
        if split != 14 || args.len() <= split + 1 || args.len() > split + 30 {
            return Err("invalid arguments");
        }
        let mut fields = BTreeMap::new();
        for pair in args[..split].chunks_exact(2) {
            let key = pair[0].to_str().ok_or("invalid key")?;
            if fields.insert(key, &pair[1]).is_some() {
                return Err("duplicate option");
            }
        }
        let number = |key, min, max| -> Result<u64, &'static str> {
            let text = fields
                .get(key)
                .and_then(|value| value.to_str())
                .ok_or("missing option")?;
            if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
                return Err("invalid number");
            }
            let value = text.parse::<u64>().map_err(|_| "invalid number")?;
            if value < min || value > max {
                Err("number outside budget")
            } else {
                Ok(value)
            }
        };
        let config = Self {
            wall_ms: number("--wall-ms", 1, 120_000)?,
            cpu_seconds: number("--cpu-seconds", 1, 120)?,
            memory_bytes: number("--memory-bytes", 16_777_216, 34_359_738_368)?,
            processes: number("--processes", 1, 1024)? as usize,
            open_files: number("--open-files", 1, 1024)?,
            file_size_bytes: number("--file-size-bytes", 1, 8_388_608)?,
            temp_dir: PathBuf::from(fields.get("--temp-dir").ok_or("missing directory")?),
            command: args[split + 1..].to_vec(),
        };
        if !config.temp_dir.is_absolute()
            || !config.temp_dir.is_dir()
            || !PathBuf::from(&config.command[0]).is_absolute()
        {
            return Err("paths must be absolute");
        }
        Ok(config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args() -> Vec<OsString> {
        [
            "--wall-ms",
            "1000",
            "--cpu-seconds",
            "1",
            "--memory-bytes",
            "16777216",
            "--processes",
            "1",
            "--open-files",
            "64",
            "--file-size-bytes",
            "1024",
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
    fn closed_options_and_positive_budgets() {
        assert!(Config::parse(args()).is_ok());
        for bad in ["0", "-1", "120001", "nan", "1000x", "+1"] {
            let mut changed = args();
            changed[1] = bad.into();
            assert!(Config::parse(changed).is_err());
        }
        let mut duplicate = args();
        duplicate[2] = "--wall-ms".into();
        assert!(Config::parse(duplicate).is_err());
        let mut relative = args();
        relative[15] = "echo".into();
        assert!(Config::parse(relative).is_err());
        assert!(Config::parse(vec!["x".repeat(4097).into()]).is_err());
    }
}
