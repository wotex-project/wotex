#!/bin/bash
# Sourced by the owned guest so its finalizer also owns this fixture process.
# The host selects one BEAM lane per guest boot through /results/lane.
set -euo pipefail
lane=$(cat /results/lane)
test "$lane" = latest || test "$lane" = lower
export HEX_HOME=/opt/wbl/hex WOTEX_PATH_DEPS=1 ERL_FLAGS='+S 4:4' MIX_ENV=test
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export WOTEX_BLE_SOFTWARE_CONFIG=/run/wbl/software.json WOTEX_REQUIRE_SOFTWARE=1
export WOTEX_BLE_NATIVE_WORKSPACE=/opt/wbl/native
rm -f /run/wbl/software.json /run/wbl/control.sock
/opt/peer/bin/python -B -u /opt/wbl/fixture/public_peer.py > /results/peer.log 2>&1 &
peer_process=$!
pids+=("$peer_process")
for attempt in $(seq 1 300); do
  test -f /run/wbl/software.json && break
  kill -0 "$peer_process"
  sleep .1
done
test -f /run/wbl/software.json
export MIX_HOME="/opt/wbl/mix/$lane" MIX_REBAR3="/opt/wbl/rebar-source/$lane/rebar3"
export WOTEX_BLE_SOFTWARE_REPORT=/results/exunit.json
if test "$lane" = latest; then
  export PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
else
  export PATH=/opt/lower/elixir/bin:/opt/lower/erlang/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi
cd "/software/$lane/wotex-ble"
mix --version > /results/runtime.log 2>&1
mix test test/interop/bluez_test.exs test/interop/bluez_runtime_test.exs --include interop --exclude hardware --seed 0 > /results/exunit.log 2>&1
kill -TERM "$peer_process"
for attempt in $(seq 1 100); do
  kill -0 "$peer_process" 2>/dev/null || break
  sleep .01
done
! kill -0 "$peer_process" 2>/dev/null
wait "$peer_process"
unset 'pids[${#pids[@]}-1]'
test -f /results/public-peer-result.json
