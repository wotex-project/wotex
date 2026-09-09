#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'usage: run_software.sh /absolute/disposable/workspace' >&2
  exit 64
fi
script_directory=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
python3 -B "$script_directory/software_fixture_test.py"
exec python3 "$script_directory/software_fixture.py" run "$1"
