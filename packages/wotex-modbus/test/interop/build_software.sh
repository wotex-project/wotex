#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'usage: build_software.sh /absolute/disposable/workspace' >&2
  exit 64
fi
script_directory=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$script_directory/software_fixture.py" build "$1"
