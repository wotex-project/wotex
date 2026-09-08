#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: test/native/run_protocol.sh ABSOLUTE_BUILD_DIRECTORY" >&2
  exit 2
fi
case "$1" in /*) ;; *) echo "build directory must be absolute" >&2; exit 2 ;; esac
wotex_thread_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cmake -S "$wotex_thread_root/priv/openthread" -B "$1" \
  -DCMAKE_BUILD_TYPE=Debug -DWOTEX_NATIVE_SANITIZERS=ON \
  -DWOTEX_NATIVE_TEST_SOURCE="$wotex_thread_root/test/native"
cmake --build "$1" --parallel 2
ctest --test-dir "$1" --output-on-failure
