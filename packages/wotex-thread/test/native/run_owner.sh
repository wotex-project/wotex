#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
  echo 'usage: run_owner.sh /absolute/host /absolute/simulated-rcp /absolute/empty-results' >&2
  exit 2
fi
for argument do
  case "$argument" in /*) ;; *) echo 'all paths must be absolute' >&2; exit 2;; esac
done
[ -x "$1" ] && [ -x "$2" ] || { echo 'built host and RCP are required' >&2; exit 2; }
[ ! -e "$3" ] || { echo 'results path must not exist' >&2; exit 2; }
mkdir -m 700 -p "$3"
owner_tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/owner_test.py
export ASAN_OPTIONS="detect_leaks=1:abort_on_error=1:log_path=$3/asan"
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1:log_path=$3/ubsan"
result=0
python3 -B "$owner_tests" "$1" "$2" > "$3/owner.log" 2>&1 || result=$?
cat "$3/owner.log"
python3 - "$1" "$2" "$3" "$result" <<'PY'
import hashlib,json,platform,sys
from pathlib import Path
host,rcp,result=map(Path,sys.argv[1:4])
logs=list(result.glob('asan.*'))+list(result.glob('ubsan.*'))
code=int(sys.argv[4])
manifest=dict(host_sha256=hashlib.sha256(host.read_bytes()).hexdigest(),
              rcp_sha256=hashlib.sha256(rcp.read_bytes()).hexdigest(),
              host_platform=platform.platform(),python=platform.python_version(),
              sanitizer_reports=[p.name for p in logs],test_exit=code,
              scope='WTH-S03 WTH-C07 WTH-V04 native ownership; software radio and injected faults')
(result/'owner-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
if logs or code: raise SystemExit(1)
PY
