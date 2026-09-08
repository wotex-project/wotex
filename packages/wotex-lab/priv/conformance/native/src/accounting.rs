use std::{collections::BTreeMap, io};

#[derive(Clone, Copy, Debug)]
pub struct Row {
    pub pid: i32,
    pub parent: i32,
    pub group: i32,
    pub birth: u64,
    pub rss: u64,
    pub zombie: bool,
}

// Bound both per-tick enumeration and retained descendant identities. A host
// beyond this observation ceiling fails closed instead of allocating endlessly.
pub const MAX_ROWS: usize = 65_536;

pub fn selected(rows: &[Row], root: i32, known: &BTreeMap<i32, u64>) -> Vec<Row> {
    let mut owned: BTreeMap<i32, u64> = rows
        .iter()
        .filter(|row| {
            row.pid == root || row.group == root || known.get(&row.pid) == Some(&row.birth)
        })
        .map(|row| (row.pid, row.birth))
        .collect();
    // Linear-time breadth-first descendant discovery, not one full scan per depth.
    let mut children: BTreeMap<i32, Vec<Row>> = BTreeMap::new();
    for row in rows {
        children.entry(row.parent).or_default().push(*row);
    }
    let mut pending: Vec<i32> = owned.keys().copied().collect();
    while let Some(parent) = pending.pop() {
        if let Some(children) = children.get(&parent) {
            for child in children {
                if owned.insert(child.pid, child.birth).is_none() {
                    pending.push(child.pid);
                }
            }
        }
    }
    rows.iter()
        .filter(|row| owned.get(&row.pid) == Some(&row.birth))
        .copied()
        .collect()
}

#[cfg(target_os = "macos")]
pub fn rows() -> io::Result<Vec<Row>> {
    let mut pids = vec![0i32; MAX_ROWS];
    // SAFETY: libproc receives an initialized, aligned buffer and its exact size.
    let found = unsafe {
        libc::proc_listallpids(
            pids.as_mut_ptr().cast(),
            std::mem::size_of_val(pids.as_slice()) as i32,
        )
    };
    if found <= 0 || found as usize >= MAX_ROWS {
        return Err(io::Error::other(
            "process enumeration unavailable or oversized",
        ));
    }
    let mut result = Vec::with_capacity(found as usize);
    for pid in pids.into_iter().take(found as usize).filter(|pid| *pid > 0) {
        // SAFETY: these C-layout integer structs have valid all-zero values.
        let mut info: libc::proc_bsdinfo = unsafe { std::mem::zeroed() };
        let mut task: libc::proc_taskinfo = unsafe { std::mem::zeroed() };
        let info_size = std::mem::size_of_val(&info) as i32;
        let task_size = std::mem::size_of_val(&task) as i32;
        // SAFETY: kernel writes no more than each provided struct's exact size.
        let read = unsafe {
            libc::proc_pidinfo(
                pid,
                libc::PROC_PIDTBSDINFO,
                0,
                (&mut info as *mut libc::proc_bsdinfo).cast(),
                info_size,
            )
        };
        if read != info_size {
            continue;
        }
        let read = unsafe {
            libc::proc_pidinfo(
                pid,
                libc::PROC_PIDTASKINFO,
                0,
                (&mut task as *mut libc::proc_taskinfo).cast(),
                task_size,
            )
        };
        if read != task_size {
            continue;
        }
        result.push(Row {
            pid,
            parent: info.pbi_ppid as i32,
            group: info.pbi_pgid as i32,
            birth: info
                .pbi_start_tvsec
                .saturating_mul(1_000_000)
                .saturating_add(info.pbi_start_tvusec),
            rss: task.pti_resident_size,
            zombie: info.pbi_status == 5,
        });
    }
    Ok(result)
}

#[cfg(target_os = "linux")]
pub fn rows() -> io::Result<Vec<Row>> {
    use std::io::Read;
    let mut result = Vec::new();
    let mut entries = 0;
    // SAFETY: sysconf has no pointer arguments or process mutation.
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if page <= 0 {
        return Err(io::Error::other("page size unavailable"));
    }
    for entry in std::fs::read_dir("/proc")? {
        let entry = entry?;
        entries += 1;
        if entries > MAX_ROWS {
            return Err(io::Error::other("process table oversized"));
        }
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|name| name.parse::<i32>().ok())
        else {
            continue;
        };
        let Ok(file) = std::fs::File::open(entry.path().join("stat")) else {
            continue;
        };
        let mut stat = String::new();
        if file.take(8193).read_to_string(&mut stat).is_err() || stat.len() > 8192 {
            continue;
        }
        if let Some(row) = parse_stat(pid, &stat, page as u64) {
            result.push(row);
        }
    }
    Ok(result)
}

#[cfg(any(target_os = "linux", test))]
fn parse_stat(pid: i32, stat: &str, page: u64) -> Option<Row> {
    // The comm field may contain spaces and parentheses; split only after its
    // final closing parenthesis. Fields after it begin with state (field 3).
    let fields: Vec<_> = stat.rsplit_once(')')?.1.split_whitespace().collect();
    Some(Row {
        pid,
        parent: fields.get(1)?.parse().ok()?,
        group: fields.get(2)?.parse().ok()?,
        birth: fields.get(19)?.parse().ok()?,
        rss: fields.get(21)?.parse::<u64>().ok()?.checked_mul(page)?,
        zombie: *fields.first()? == "Z",
    })
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
compile_error!("only Linux and macOS process accounting is admitted");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_names_do_not_shift_accounting_fields() {
        let mut fields = vec!["0"; 22];
        for (index, value) in [(0, "S"), (1, "8"), (2, "42"), (19, "1234"), (21, "7")] {
            fields[index] = value;
        }
        let stat = format!("42 (a strange ) name) {}", fields.join(" "));
        let row = parse_stat(42, &stat, 4096).unwrap();
        assert_eq!(
            (row.parent, row.group, row.birth, row.rss),
            (8, 42, 1234, 7 * 4096)
        );
        assert!(parse_stat(42, "malformed", 4096).is_none());
    }

    #[test]
    fn identity_survives_reparenting_but_not_pid_reuse() {
        let row = |pid, parent, group, birth| Row {
            pid,
            parent,
            group,
            birth,
            rss: 1,
            zombie: false,
        };
        let rows = [
            row(10, 1, 10, 1),
            row(11, 10, 10, 2),
            row(12, 11, 12, 3),
            row(13, 1, 13, 4),
            row(14, 1, 14, 99),
        ];
        let known = BTreeMap::from([(13, 4), (14, 5)]);
        let pids: Vec<_> = selected(&rows, 10, &known)
            .iter()
            .map(|row| row.pid)
            .collect();
        assert_eq!(pids, vec![10, 11, 12, 13]);
    }

    #[test]
    fn actual_process_table_contains_self() {
        assert!(rows()
            .unwrap()
            .iter()
            .any(|row| row.pid == std::process::id() as i32));
    }
}
