#!/usr/bin/python3
"""Bound and supervise one external conformance target without a shell."""

import argparse
import ctypes
import glob
import os
import platform
import resource
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time


child = None
descendants = set()


def kill_group():
    for pid in sorted(descendants, reverse=True):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    if child is not None and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def terminate(signum, _frame):
    kill_group()
    os._exit(128 + signum)


def bounded(resource_name, value):
    limit = getattr(resource, resource_name, None)
    if limit is not None:
        resource.setrlimit(limit, (value, value))


def limits(args):
    bounded("RLIMIT_CPU", args.cpu_seconds)
    bounded("RLIMIT_NOFILE", args.open_files)
    bounded("RLIMIT_FSIZE", args.file_size_bytes)
    bounded("RLIMIT_CORE", 0)


def darwin_rows():
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
    count = libproc.proc_listallpids(None, 0)
    pids = (ctypes.c_int * (count + 64))()
    found = libproc.proc_listallpids(pids, ctypes.sizeof(pids))
    rows = []

    for pid in pids[:found]:
        bsd = ctypes.create_string_buffer(256)
        task = ctypes.create_string_buffer(256)
        if libproc.proc_pidinfo(pid, 3, 0, bsd, 256) <= 0:
            continue
        if libproc.proc_pidinfo(pid, 4, 0, task, 256) <= 0:
            continue
        parent = struct.unpack_from("=IIIII", bsd.raw)[4]
        resident = struct.unpack_from("=QQ", task.raw)[1]
        rows.append((pid, parent, resident))

    return rows


def linux_rows():
    rows = []
    page_size = os.sysconf("SC_PAGE_SIZE")
    for stat_path in glob.glob("/proc/[0-9]*/stat"):
        try:
            with open(stat_path, encoding="ascii") as stat_file:
                stat = stat_file.read().split()
            with open(stat_path[:-4] + "statm", encoding="ascii") as statm_file:
                statm = statm_file.read().split()
            rows.append((int(stat[0]), int(stat[3]), int(statm[1]) * page_size))
        except (OSError, ValueError, IndexError):
            continue
    return rows


def process_tree(root):
    if platform.system() == "Darwin":
        rows = darwin_rows()
    elif platform.system() == "Linux":
        rows = linux_rows()
    else:
        raise OSError("unsupported process accounting platform")

    selected = {root}
    changed = True
    while changed:
        changed = False
        for pid, parent, _rss in rows:
            if parent in selected and pid not in selected:
                selected.add(pid)
                changed = True

    live = [(pid, resident) for pid, _parent, resident in rows if pid in selected]
    return live


def wait_bounded(args):
    global descendants
    deadline = time.monotonic() + args.wall_ms / 1000.0

    while child.poll() is None:
        tree = process_tree(child.pid)
        descendants.update(pid for pid, _rss in tree if pid != child.pid)
        memory_bytes = sum(resident for _pid, resident in tree)

        if len(tree) > args.processes:
            kill_group()
            child.wait()
            return 123

        if memory_bytes > args.memory_bytes:
            kill_group()
            child.wait()
            return 122

        if time.monotonic() >= deadline:
            kill_group()
            child.wait()
            return 124

        time.sleep(0.01)

    return None


def parser():
    value = argparse.ArgumentParser(add_help=False)
    value.add_argument("--wall-ms", type=int, required=True)
    value.add_argument("--cpu-seconds", type=int, required=True)
    value.add_argument("--memory-bytes", type=int, required=True)
    value.add_argument("--processes", type=int, required=True)
    value.add_argument("--open-files", type=int, required=True)
    value.add_argument("--file-size-bytes", type=int, required=True)
    value.add_argument("--temp-dir", required=True)
    value.add_argument("command", nargs=argparse.REMAINDER)
    return value


def main():
    global child
    args = parser().parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command

    if not command or not os.path.isabs(command[0]) or not os.path.isdir(args.temp_dir):
        return 125

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGHUP, terminate)
    signal.signal(signal.SIGINT, terminate)
    run_dir = tempfile.mkdtemp(prefix="run-", dir=args.temp_dir)

    try:
        os.chdir(run_dir)
        child_environment = os.environ.copy()
        child_environment["HOME"] = run_dir
        child_environment["TMPDIR"] = run_dir

        with tempfile.TemporaryFile(dir=run_dir) as output:
            try:
                child = subprocess.Popen(
                    command,
                    stdin=sys.stdin.buffer,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                    preexec_fn=lambda: limits(args),
                    close_fds=True,
                    env=child_environment,
                )
                bounded_exit = wait_bounded(args)
                if bounded_exit is not None:
                    return bounded_exit
            except (OSError, ValueError, subprocess.SubprocessError):
                kill_group()
                return 125

            output.seek(0)
            while True:
                block = output.read(65536)
                if not block:
                    break
                sys.stdout.buffer.write(block)
            sys.stdout.buffer.flush()

        return child.returncode if child.returncode >= 0 else 128 - child.returncode
    finally:
        os.chdir(args.temp_dir)
        shutil.rmtree(run_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
