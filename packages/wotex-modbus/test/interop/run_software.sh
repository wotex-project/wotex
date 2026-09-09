#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'usage: run_software.sh /absolute/disposable/workspace' >&2
  exit 64
fi
script_directory=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd -- "$script_directory/../.."
exec mix wotex.software.run --workspace "$1"
